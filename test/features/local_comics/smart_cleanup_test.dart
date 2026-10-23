import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:venera_next/features/local_comics/local.dart';
import 'package:venera_next/features/local_comics/images_download_task.dart';
import 'package:venera_next/features/local_comics/local_repository.dart';
import 'package:venera_next/features/local_comics/smart_download_policy.dart';
import 'package:venera_next/features/comic_source/comic_source_api.dart';
import 'package:venera_next/foundation/comic_type.dart';
import 'package:venera_next/foundation/reading_activity.dart';
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/foundation/appdata.dart';

class _Source extends Fake implements ComicSource {
  @override
  String get key => 'cleanup-provenance';
}

class _FinishedTask extends ImagesDownloadTask {
  _FinishedTask(LocalManager library, this.result, {required super.automatic})
    : super(storage: library, source: _Source(), comicId: result.id);
  final LocalComic result;
  @override
  ComicType get comicType => result.comicType;
  @override
  void resume() {}
  @override
  LocalComic toLocalComic() => result;
}

void main() {
  const type = ComicType(987654321);
  test('cleanup settings are opt-in, bounded and survive serialization', () {
    expect(SmartDownloadPolicy.fromJson(null).cleanupEnabled, isFalse);
    final p = SmartDownloadPolicy.fromJson({
      'cleanupEnabled': true,
      'retentionHours': 6,
    });
    expect(SmartDownloadPolicy.fromJson(p.toJson()).retentionHours, 6);
    expect(
      SmartDownloadPolicy.fromJson({'retentionHours': 0}).retentionHours,
      1,
    );
    expect(
      SmartDownloadPolicy.fromJson({'retentionHours': 99999}).retentionHours,
      8760,
    );
  });
  test(
    'only proven automatic completed chapters qualify; retain three per book',
    () {
      final db = sqlite3.openInMemory();
      addTearDown(db.dispose);
      final repo = LocalRepository(db)..initialize();
      repo.registerAutomaticChapters('book', type, [
        '1',
        '2',
        '3',
        '4',
        '5',
        '6',
      ]);
      repo.registerAutomaticChapters('import', ComicType.local, ['1']);
      expect(repo.automaticProtection('import', ComicType.local, '1'), isNull);
      repo.recordAutomaticReading(
        'book',
        type,
        {'1': 1, '2': 2, '3': 3, '4': 4, '5': 5, '6': 6, 'manual': 100},
        {'1', '2', '3', '4', '5'},
      );
      expect(repo.automaticReadChapters().map((e) => e.chapter), ['2', '1']);
      // Highest visited chapter alone is not completion.
      expect(
        repo.automaticReadChapters().any((e) => e.chapter == '6'),
        isFalse,
      );
      repo.protectAutomatic('book', type, chapter: '1', protect: true);
      expect(repo.automaticReadChapters().map((e) => e.chapter), ['2']);
      // Revisiting moves the timer forward and changes the retained set.
      repo.recordAutomaticReading('book', type, {'2': 100}, {});
      expect(repo.automaticReadChapters().map((e) => e.chapter), ['3']);
      repo.protectAutomatic('book', type, protect: true);
      expect(repo.automaticReadChapters(), isEmpty);
      expect(repo.automaticProtection('book', type, 'manual'), isNull);
    },
  );
  test(
    'tied completion timestamps preserve every chapter at retention boundary',
    () {
      final db = sqlite3.openInMemory();
      addTearDown(db.dispose);
      final repo = LocalRepository(db)..initialize();
      repo.registerAutomaticChapters('book', type, ['a', 'b', 'c', 'd']);
      repo.recordAutomaticReading(
        'book',
        type,
        {'a': 1, 'b': 1, 'c': 1, 'd': 1},
        {'a', 'b', 'c', 'd'},
      );
      expect(repo.automaticReadChapters(), isEmpty);
    },
  );
  test(
    'reader entry waits for accepted maintenance, then future maintenance rejects',
    () async {
      final activity = ReadingActivity.instance, gate = Completer<void>();
      final maintenance = activity.runMaintenance(() => gate.future);
      expect(activity.hasMaintenance, isTrue);
      final release = activity.enter();
      try {
        var finished = false;
        final waiting = activity.waitForMaintenance().then(
          (_) => finished = true,
        );
        await pumpEventQueue();
        expect(finished, isFalse);
        gate.complete();
        await maintenance;
        await waiting;
        expect(finished, isTrue);
        await expectLater(
          activity.runMaintenance(() async {}),
          throwsStateError,
        );
      } finally {
        release();
      }
    },
  );
  test(
    'real deletion preserves recent, protected and manual chapters, and rechecks eligibility',
    () async {
      final root = Directory.systemTemp.createTempSync('smart-cleanup-');
      LocalManager.current?.dispose();
      App.dataPath = root.path;
      App.cachePath = root.path;
      File('${root.path}/local_path').writeAsStringSync(root.path);
      final library = LocalManager(initializeSources: () async {});
      await library.init();
      final db = sqlite3.open('${root.path}/local.db');
      final repo = LocalRepository(db)..initialize();
      try {
        final chapters = ComicChapters({
          for (var i = 1; i <= 7; i++) '$i': 'Chapter $i',
        });
        final comic = LocalComic(
          id: 'book',
          title: 'Book',
          subtitle: '',
          tags: [],
          directory: 'book',
          chapters: chapters,
          cover: 'cover.jpg',
          comicType: type,
          downloadedChapters: chapters.ids.toList(),
          createdAt: DateTime(2026),
        );
        await library.add(comic);
        LocalComic provenance(List<String> ids) => LocalComic(
          id: 'provenance',
          title: 'Provenance',
          subtitle: '',
          tags: [],
          directory: 'provenance',
          chapters: const ComicChapters({'auto': 'Auto', 'manual': 'Manual'}),
          cover: 'cover.jpg',
          comicType: type,
          downloadedChapters: ids,
          createdAt: DateTime(2026),
        );
        await library.add(provenance(['manual']));
        final automaticTask = _FinishedTask(
          library,
          provenance(['auto', 'manual']),
          automatic: true,
        );
        library.addTask(automaticTask);
        library.completeTask(automaticTask);
        expect(
          library.automaticChapterProtection('provenance', type, 'auto'),
          isFalse,
        );
        expect(
          library.automaticChapterProtection('provenance', type, 'manual'),
          isNull,
        );
        final manualTask = _FinishedTask(
          library,
          provenance(['manual']),
          automatic: false,
        );
        library.addTask(manualTask);
        expect(
          library.automaticChapterProtection('provenance', type, 'auto'),
          isTrue,
        );
        library.removeTask(manualTask);
        for (var i = 1; i <= 7; i++) {
          final dir = Directory('${root.path}/book/$i')
            ..createSync(recursive: true);
          File('${dir.path}/page.jpg').writeAsStringSync('keep');
        }
        repo.registerAutomaticChapters('book', type, [
          '1',
          '2',
          '3',
          '4',
          '5',
          '6',
        ]);
        repo.recordAutomaticReading(
          'book',
          type,
          {for (var i = 1; i <= 6; i++) '$i': i},
          {'1', '2', '3', '4', '5', '6'},
        );
        final entry = library.automaticCleanupCandidates().firstWhere(
          (e) => e.chapter == '1',
        );
        library.protectAutomaticChapter('book', type, '1', true);
        await library.cleanAutomaticChapter(entry, () => true);
        expect(File('${root.path}/book/1/page.jpg').existsSync(), isTrue);
        library.protectAutomaticChapter('book', type, '1', false);
        final release = ReadingActivity.instance.enter();
        try {
          await library.cleanAutomaticChapter(entry, () => true);
        } finally {
          release();
        }
        expect(File('${root.path}/book/1/page.jpg').existsSync(), isTrue);
        await library.cleanAutomaticChapter(entry, () => false);
        expect(File('${root.path}/book/1/page.jpg').existsSync(), isTrue);
        await library.cleanAutomaticChapter(entry, () => true);
        expect(File('${root.path}/book/1/page.jpg').existsSync(), isFalse);
        expect(library.find('book', type)!.downloadedChapters, [
          '2',
          '3',
          '4',
          '5',
          '6',
          '7',
        ]);
        expect(File('${root.path}/book/7/page.jpg').existsSync(), isTrue);
        expect(library.automaticChapterProtection('book', type, '1'), isNull);
      } finally {
        db.dispose();
        await library.pendingDownloadTaskWrites;
        library.dispose();
        await appdata.saveData(false);
        root.deleteSync(recursive: true);
      }
    },
  );
}
