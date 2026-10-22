import 'package:flutter/material.dart';
import 'package:venera_next/components/appbar.dart';
import 'package:venera_next/components/settings_save_state.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/features/local_comics/smart_download_policy.dart';

class SmartDownloadSettingsPage extends StatefulWidget {
  const SmartDownloadSettingsPage({super.key});
  @override
  State<SmartDownloadSettingsPage> createState() =>
      _SmartDownloadSettingsPageState();
}

class _SmartDownloadSettingsPageState
    extends SettingsSaveState<SmartDownloadSettingsPage> {
  SmartDownloadPolicy get policy =>
      SmartDownloadPolicy.fromJson(appdata.settings['smartDownloads']);
  Future<void> _save(String key, dynamic value) async {
    await saveSetting(
      'smartDownloads',
      () => appdata.updateSettings((draft) {
        final values = SmartDownloadPolicy.fromJson(
          draft['smartDownloads'],
        ).toJson();
        values[key] = value;
        draft['smartDownloads'] = SmartDownloadPolicy.fromJson(values).toJson();
      }, sync: false),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final current = policy;
    final editable = acceptsSettingsChanges && !savingSettings;
    return protectSettings(
      Scaffold(
        appBar: Appbar(
          title: const Text('智能预下载'),
          actions: [settingsSaveStatus],
        ),
        body: ListView(
          children: [
            SwitchListTile(
              title: const Text('自动预下载后续章节'),
              subtitle: const Text('默认关闭。开启后，阅读一章时提前下载其后的章节。'),
              value: current.enabled,
              onChanged: editable ? (v) => _save('enabled', v) : null,
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: DropdownButtonFormField<SmartDownloadNetwork>(
                key: ValueKey('network-${current.network.name}'),
                initialValue: current.network,
                decoration: const InputDecoration(labelText: '允许的网络'),
                items: const [
                  DropdownMenuItem(
                    value: SmartDownloadNetwork.wifi,
                    child: Text('仅 Wi-Fi'),
                  ),
                  DropdownMenuItem(
                    value: SmartDownloadNetwork.wifiAndMobile,
                    child: Text('Wi-Fi 或蜂窝数据'),
                  ),
                ],
                onChanged: editable ? (v) => _save('network', v!.name) : null,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: DropdownButtonFormField<SmartDownloadPower>(
                key: ValueKey('power-${current.power.name}'),
                initialValue: current.power,
                decoration: const InputDecoration(labelText: '允许的电源状态'),
                items: const [
                  DropdownMenuItem(
                    value: SmartDownloadPower.charging,
                    child: Text('仅充电时'),
                  ),
                  DropdownMenuItem(
                    value: SmartDownloadPower.anytime,
                    child: Text('随时允许'),
                  ),
                ],
                onChanged: editable ? (v) => _save('power', v!.name) : null,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: DropdownButtonFormField<int>(
                key: ValueKey('ahead-${current.ahead}'),
                initialValue: current.ahead,
                decoration: const InputDecoration(labelText: '提前下载章节数'),
                items: [
                  for (var n = 1; n <= 10; n++)
                    DropdownMenuItem(value: n, child: Text('$n 章')),
                ],
                onChanged: editable ? (v) => _save('ahead', v!) : null,
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '网络与电源条件必须同时满足。条件变化后暂停自动任务，恢复后继续；不会自动恢复你手动暂停的任务。\n\n'
                '阅读期间保持单并发；手动下载优先。已下载的章节会跳过，不会自动删除旧章节。\n\n'
                'iOS 仅在应用处于前台时安排预下载，锁屏／切到后台后暂停。网络类型未知时不启动自动下载；Wi-Fi 连接不代表网站一定可用。\n\n'
                '允许蜂窝数据会消耗流量。网络切换检测存在延迟，在途请求可能产生少量流量；若必须完全禁止蜂窝流量，可同时在 iOS 设置中关闭本应用的蜂窝数据权限。',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
