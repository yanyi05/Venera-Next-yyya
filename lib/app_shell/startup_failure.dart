import 'package:share_plus/share_plus.dart';
import 'package:venera_next/foundation/startup_journal.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/foundation/log_redaction.dart';
import 'package:venera_next/foundation/translations.dart';

/// Does not open stores or retry a bootstrap whose cleanup may have failed.
class StartupFailureApp extends StatefulWidget {
  const StartupFailureApp({
    required this.error,
    required this.stack,
    super.key,
  });

  final Object error;
  final StackTrace stack;

  @override
  State<StartupFailureApp> createState() => _StartupFailureAppState();
}

class _StartupFailureAppState extends State<StartupFailureApp> {
  bool _copied = false;
  bool _copyFailed = false;
  bool _recoveryScheduled = false;

  String get _diagnostic => redactLogText(
    'VeneraNext ${App.buildVersion} (${Platform.operatingSystem})\n'
    '阶段：${StartupJournal.current?.phase ?? 'environment'}\n'
    '上次启动：${StartupJournal.current?.previousPhase ?? 'unknown'}\n'
    '${widget.error}\n${widget.stack}',
  );

  @override
  void initState() {
    super.initState();
    unawaited(
      AppTranslation.init().then<void>((_) {
        if (mounted) setState(() {});
      }, onError: (Object _, StackTrace _) {}),
    );
  }

  Future<void> _copy() async {
    try {
      await Clipboard.setData(ClipboardData(text: _diagnostic));
      if (mounted) {
        setState(() {
          _copied = true;
          _copyFailed = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _copied = false;
          _copyFailed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'VeneraNext',
    theme: ThemeData(colorSchemeSeed: Colors.blue),
    darkTheme: ThemeData(
      colorSchemeSeed: Colors.blue,
      brightness: Brightness.dark,
    ),
    home: Scaffold(
      appBar: AppBar(title: const Text('VeneraNext')),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  'Startup failed'.tl,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Initialization could not finish. Keep your existing data and copy the diagnostic details for troubleshooting. Do not delete databases or reset settings first.'
                      .tl,
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: _copy,
                    icon: Icon(_copied ? Icons.check : Icons.copy),
                    label: Text(
                      (_copied ? 'Copied' : 'Copy diagnostic details').tl,
                    ),
                  ),
                ),
                if (_copyFailed) Text('Failed to copy diagnostic details'.tl),
                Builder(
                  builder: (buttonContext) => TextButton.icon(
                    icon: const Icon(Icons.share),
                    label: const Text('分享诊断记录'),
                    onPressed: () async {
                      final box =
                          buttonContext.findRenderObject() as RenderBox?;
                      try {
                        await SharePlus.instance.share(
                          ShareParams(
                            text: _diagnostic,
                            sharePositionOrigin: box == null
                                ? null
                                : box.localToGlobal(Offset.zero) & box.size,
                          ),
                        );
                      } catch (_) {
                        await _copy();
                      }
                    },
                  ),
                ),
                if (StartupJournal.current != null)
                  TextButton.icon(
                    icon: const Icon(Icons.health_and_safety),
                    label: const Text('下次启动停用已安装漫画源'),
                    onPressed: () {
                      try {
                        StartupJournal.current!.setSafeMode(true);
                        setState(() => _recoveryScheduled = true);
                      } catch (_) {
                        _copy();
                      }
                    },
                  ),
                if (_recoveryScheduled)
                  const Text('已设置。请完全关闭并重新打开应用；漫画源文件与收藏会保留。'),
                const SizedBox(height: 8),
                Text(
                  'Review personal information before sharing diagnostic details.'
                      .tl,
                ),
                const SizedBox(height: 16),
                SelectableText(_diagnostic),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
