import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/app_runtime/smart_downloads.dart';
import 'package:venera_next/features/local_comics/local.dart';
import 'package:venera_next/features/local_comics/download_task.dart';
import 'package:venera_next/features/local_comics/smart_download_policy.dart';
import 'package:venera_next/foundation/comic_type.dart';
import 'package:venera_next/foundation/reading_activity.dart';
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/foundation/appdata.dart';

class _Library extends Fake implements LocalManager {
  final changes = ChangeNotifier();
  var removed = 0;
  final entries = <({String id, ComicType type, String chapter, int readAt})>[
    (id: 'book', type: const ComicType(123), chapter: 'old-auto', readAt: 1),
  ];
  @override
  void addListener(VoidCallback listener) => changes.addListener(listener);
  @override
  void removeListener(VoidCallback listener) =>
      changes.removeListener(listener);
  @override
  List<DownloadTask> get downloadingTasks => [];
  @override
  List<({String id, ComicType type, String chapter, int readAt})>
  automaticCleanupCandidates() => entries;
  @override
  Future<void> cleanAutomaticChapter(
    ({String id, ComicType type, String chapter, int readAt}) entry,
    bool Function() isAllowed,
  ) async {
    if (isAllowed() && !ReadingActivity.instance.isReading) {
      removed++;
      entries.remove(entry);
    }
  }
}

void main() {
  testWidgets(
    'cleanup works with predownload off, stops during reading and on background',
    (tester) async {
      final root = Directory.systemTemp.createTempSync('cleanup-runtime-');
      final checkpoint = appdata.captureImportCheckpoint();
      App.dataPath = root.path;
      final library = _Library();
      final runtime = SmartDownloadsRuntime(library: () => library);
      try {
        await tester.runAsync(
          () => appdata.updateSettings((draft) {
            draft['smartDownloads'] = const SmartDownloadPolicy(
              cleanupEnabled: true,
              retentionHours: 1,
            ).toJson();
          }, sync: false),
        );
        runtime.start();
        final release = ReadingActivity.instance.enter();
        await tester.pump(const Duration(seconds: 4));
        expect(library.removed, 0);
        release();
        await tester.pump(const Duration(seconds: 2));
        await tester.pump();
        expect(library.removed, 1);
        library.entries.add((
          id: 'book',
          type: const ComicType(123),
          chapter: 'second',
          readAt: 1,
        ));
        library.changes.notifyListeners();
        await tester.pump(const Duration(milliseconds: 250));
        runtime.stop();
        await tester.pump(const Duration(seconds: 3));
        expect(library.removed, 1);
      } finally {
        runtime.stop();
        library.changes.dispose();
        await tester.runAsync(
          () => appdata.restoreImportCheckpoint(checkpoint, persist: false),
        );
        root.deleteSync(recursive: true);
      }
    },
  );
}
