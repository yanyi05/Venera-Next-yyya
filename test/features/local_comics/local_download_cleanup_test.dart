import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:venera_next/features/local_comics/local.dart';
import 'package:venera_next/features/local_comics/local_download_removal.dart';
import 'package:venera_next/features/local_comics/local_repository.dart';
import 'package:venera_next/features/local_comics/local_storage_guard.dart';
import 'package:venera_next/features/local_comics/local_related_data.dart';
import 'package:venera_next/features/comic_source/comic_source_api.dart'
    show ComicChapters;
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/foundation/comic_type.dart';
import 'package:venera_next/foundation/reading_activity.dart';

class _Related extends Fake implements LocalComicRelatedData {
  int deletions = 0;
  @override
  Future<void> deleteRecords({
    required Database localDatabase,
    required List<LocalComic> comics,
    required void Function() markCommitted,
    required void Function() validate,
  }) async {
    deletions++;
    throw StateError('Cleanup must preserve history and favorites');
  }
}

void main() {
  const type = ComicType(987654321);
  late Directory root;
  late LocalManager library;
  late _Related related;
  setUp(() async {
    root = Directory.systemTemp.createTempSync('manual-download-cleanup-');
    App.dataPath = root.path;
    File('${root.path}/local_path').writeAsStringSync(root.path);
    related = _Related();
    library = LocalManager.independent(
      initializeSources: () async {},
      relatedData: related,
    );
    await library.init();
  });
  tearDown(() async {
    await library.pendingDownloadTaskWrites;
    library.dispose();
    await root.delete(recursive: true);
  });
  LocalComic comic({
    List<String> ids = const ['a', 'b'],
    ComicType source = type,
  }) => LocalComic(
    id: 'book',
    title: 'Book',
    subtitle: '',
    tags: [],
    directory: 'book',
    chapters: const ComicChapters({
      'a': 'Chapter A',
      'b': 'Chapter B',
      'c': 'Chapter C',
    }),
    cover: 'cover.jpg',
    comicType: source,
    downloadedChapters: ids,
    createdAt: DateTime(2026),
  );
  Future<LocalComic> seed({ComicType source = type}) async {
    final book = comic(source: source);
    for (final id in book.downloadedChapters) {
      File('${root.path}/book/$id/page.jpg')
        ..createSync(recursive: true)
        ..writeAsStringSync(id);
    }
    File('${root.path}/book/cover.jpg').writeAsStringSync('cover');
    await library.add(book);
    return library.find(book.id, source)!;
  }

  LocalDownloadRemoval plan(LocalComic book, {List<String>? chapters}) =>
      LocalDownloadRemoval(
        book,
        chapters: chapters,
        protection: {
          for (final id in chapters ?? book.downloadedChapters)
            id: library.automaticChapterProtection(book.id, book.comicType, id),
        },
      );

  test(
    'partial cleanup removes selected chapter only and preserves cover and related data',
    () async {
      final book = await seed();
      await library.removeDownloadedContent(plan(book, chapters: ['a']));
      expect(File('${root.path}/book/a/page.jpg').existsSync(), isFalse);
      expect(File('${root.path}/book/b/page.jpg').readAsStringSync(), 'b');
      expect(File('${root.path}/book/cover.jpg').readAsStringSync(), 'cover');
      expect(library.find('book', type)!.downloadedChapters, ['b']);
      expect(related.deletions, 0);
    },
  );
  for (final source in [type, ComicType.local]) {
    test(
      'whole cleanup removes files, retains history/favorites; source=${source.value}',
      () async {
        final book = await seed(source: source);
        await library.removeDownloadedContent(plan(book));
        expect(Directory('${root.path}/book').existsSync(), isFalse);
        expect(library.find('book', source), isNull);
        expect(related.deletions, 0);
      },
    );
  }
  test(
    'stale whole-book confirmation cannot delete newly downloaded content',
    () async {
      final book = await seed();
      final selected = plan(book);
      await library.add(comic(ids: ['a', 'b', 'c']));
      await expectLater(
        library.removeDownloadedContent(selected),
        throwsStateError,
      );
      expect(File('${root.path}/book/a/page.jpg').existsSync(), isTrue);
      expect(library.find('book', type)!.downloadedChapters.toSet(), {
        'a',
        'b',
        'c',
      });
    },
  );
  test(
    'reader entering while queued prevents all filesystem changes',
    () async {
      final book = await seed();
      final gate = Completer<void>();
      final ready = Completer<void>();
      final blocked = library.runWithExclusiveStorage(() async {
        ready.complete();
        await gate.future;
      });
      await ready.future;
      final remove = expectLater(
        library.removeDownloadedContent(plan(book)),
        throwsA(anyOf(isA<StateError>(), isA<LocalComicStorageBusy>())),
      );
      final release = ReadingActivity.instance.enter();
      gate.complete();
      try {
        await Future.wait([blocked, remove]);
      } finally {
        release();
      }
      expect(File('${root.path}/book/a/page.jpg').existsSync(), isTrue);
      expect(library.find('book', type), isNotNull);
      expect(ReadingActivity.instance.hasMaintenance, isFalse);
    },
  );
  test(
    'protection changes require a new confirmation; explicitly reviewed protection can be removed',
    () async {
      final book = await seed();
      final selected = plan(book, chapters: ['a']);
      final db = sqlite3.open('${root.path}/local.db');
      try {
        final repo = LocalRepository(db)..initialize();
        repo.registerAutomaticChapters('book', type, ['a']);
        library.protectAutomaticChapter('book', type, 'a', true);
        await expectLater(
          library.removeDownloadedContent(selected),
          throwsStateError,
        );
        expect(File('${root.path}/book/a/page.jpg').existsSync(), isTrue);
        final confirmed = plan(library.find('book', type)!, chapters: ['a']);
        expect(confirmed.protectedCount, 1);
        await library.removeDownloadedContent(confirmed);
        expect(File('${root.path}/book/a/page.jpg').existsSync(), isFalse);
        expect(library.automaticChapterProtection('book', type, 'a'), isNull);
      } finally {
        db.dispose();
      }
    },
  );
}
