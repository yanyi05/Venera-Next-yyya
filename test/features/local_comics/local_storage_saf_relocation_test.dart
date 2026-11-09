import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:venera_next/features/local_comics/local_comic_model.dart';
import 'package:venera_next/features/local_comics/local_repository.dart';
import 'package:venera_next/features/local_comics/local_storage_migration.dart';
import 'package:venera_next/features/local_comics/local_storage_relocation.dart';
import 'package:venera_next/foundation/comic_type.dart';
import 'package:venera_next/foundation/file_system.dart';

void main() {
  late Directory root;
  late Directory source;
  late Directory destination;
  late File mirror;
  late Database db;
  late LocalRepository repository;
  late LocalStorageRelocation relocation;
  late String published;
  final errors = <Object>[];

  LocalComic comic(String id, String directory) => LocalComic(
    id: id,
    title: id,
    subtitle: '',
    tags: ['retained'],
    directory: directory,
    chapters: null,
    cover: '1.jpg',
    comicType: ComicType.local,
    downloadedChapters: [],
    createdAt: DateTime(2024),
  );

  setUp(() {
    root = Directory.systemTemp.createTempSync('saf-relocation-');
    source = Directory(p.join(root.path, 'source'))..createSync();
    destination = Directory(p.join(root.path, 'destination'))..createSync();
    final book = Directory(p.join(source.path, 'Book'))..createSync();
    File(p.join(book.path, '1.jpg')).writeAsStringSync('retained page');
    mirror = File(p.join(root.path, 'local_path'));
    db = sqlite3.open(p.join(root.path, 'local.db'));
    repository = LocalRepository(db)..initialize();
    relocation = LocalStorageRelocation(db)..initialize();
    errors.clear();
  });
  tearDown(() {
    db.dispose();
    root.deleteSync(recursive: true);
  });

  // Exercise the real journal/copy/recovery pipeline with file-backed provider
  // adapters. This is not an Android permission/provider integration test.
  Future<T> withProvider<T>(
    String oldRoot,
    String newRoot,
    Future<T> Function(LocalStorageMigration migration) action,
  ) {
    final parent = Zone.current;
    String native(String value) {
      for (final binding in [
        (oldRoot, source.path),
        (newRoot, destination.path),
      ]) {
        if (p.equals(binding.$1, value)) return binding.$2;
        if (p.isWithin(binding.$1, value)) {
          return p.join(binding.$2, p.relative(value, from: binding.$1));
        }
      }
      return value;
    }

    return IOOverrides.runZoned(
      () => action(
        LocalStorageMigration(
          relocation: relocation,
          copyContents: (_, _) => copyDirectory(source, destination),
          publishPath: (value) => published = value,
          reportCleanupError: (error, stack) => errors.add(error),
          canonicalPath: (directory) async => directory.path,
          resolveReference: (value) async => value,
          clearContents: (_) => source.deleteContents(),
        ),
      ),
      createDirectory: (value) => parent.run(() => Directory(native(value))),
      createFile: (value) => parent.run(() => File(native(value))),
    );
  }

  for (final direction in ['to SAF', 'from SAF', 'between SAF roots']) {
    test(
      '$direction preserves references and reopens the selected library',
      () async {
        final oldRoot = direction == 'to SAF'
            ? source.path
            : 'android://primary:Comics';
        final newRoot = direction == 'from SAF'
            ? destination.path
            : 'android://ABCD-1234:Library';
        published = oldRoot;
        mirror.writeAsStringSync(oldRoot);
        repository.add(comic('absolute', p.join(oldRoot, 'Book')));
        repository.add(comic('relative', 'Book'));
        repository.add(comic('external', 'android://other:External/Book'));
        await withProvider(oldRoot, newRoot, (migration) async {
          expect(
            await migration.migrate(
              source: _SelectedDirectory(oldRoot, source),
              destination: _SelectedDirectory(newRoot, destination),
              pathFile: mirror,
            ),
            isNull,
          );
        });
        expect(published, newRoot);
        expect(mirror.readAsStringSync(), newRoot);
        expect(source.listSync(), isEmpty);
        expect(
          File(p.join(destination.path, 'Book', '1.jpg')).readAsStringSync(),
          'retained page',
        );
        expect(errors, isEmpty);
        db.dispose();
        db = sqlite3.open(p.join(root.path, 'local.db'));
        repository = LocalRepository(db);
        relocation = LocalStorageRelocation(db);
        expect(relocation.pending, isNull);
        expect(
          repository.find('absolute', ComicType.local)!.directory,
          p.join(newRoot, 'Book'),
        );
        expect(repository.find('relative', ComicType.local)!.directory, 'Book');
        expect(
          repository.find('external', ComicType.local)!.directory,
          'android://other:External/Book',
        );
      },
    );
  }

  for (final committed in [false, true]) {
    test(
      'SAF recovery after reopening respects committed=$committed',
      () async {
        const oldRoot = 'android://primary:Comics';
        const newRoot = 'android://ABCD-1234:Library';
        published = oldRoot;
        mirror.writeAsStringSync(oldRoot);
        repository.add(comic('1', p.join(oldRoot, 'Book')));
        await withProvider(oldRoot, newRoot, (_) async {
          final snapshot = relocation.snapshot();
          final targets = await relocation.destinations(
            oldRoot,
            newRoot,
            resolvePath: (value) async => value,
          );
          await copyDirectory(source, destination);
          relocation.prepare(oldRoot, newRoot, snapshot, targets);
          if (committed) relocation.commit(snapshot);
        });
        db.dispose();
        db = sqlite3.open(p.join(root.path, 'local.db'));
        repository = LocalRepository(db);
        relocation = LocalStorageRelocation(db);
        final expected = committed ? newRoot : oldRoot;
        await withProvider(oldRoot, newRoot, (migration) async {
          expect(await migration.recover(mirror), expected);
        });
        expect(published, expected);
        expect(mirror.readAsStringSync(), expected);
        expect(
          repository.find('1', ComicType.local)!.directory,
          p.join(expected, 'Book'),
        );
        expect(relocation.pending, isNull);
        for (final directory in [source, destination]) {
          expect(
            File(p.join(directory.path, 'Book', '1.jpg')).readAsStringSync(),
            'retained page',
          );
        }
        expect(errors, isEmpty);
      },
    );
  }

  for (final target in [
    'android://primary:Comics',
    'android://primary:Comics/Book',
    'android://primary:Comics/Book/Nested',
  ]) {
    test('SAF overlap $target is still rejected', () {
      expect(
        () => relocation.prepare(
          'android://primary:Comics/Book',
          target,
          relocation.snapshot(),
          {},
        ),
        throwsFormatException,
      );
      expect(relocation.pending, isNull);
    });
  }

  for (final invalid in [
    'android://',
    'android:///Book',
    'android://../Book',
    'android://primary:Comics/../Other',
    'android://primary:Comics/./Book',
    'android://primary:Comics\u0000',
  ]) {
    test('rejects malformed provider path $invalid without a journal', () {
      expect(
        () =>
            relocation.prepare(source.path, invalid, relocation.snapshot(), {}),
        throwsFormatException,
      );
      expect(relocation.pending, isNull);
      expect(
        File(p.join(source.path, 'Book', '1.jpg')).readAsStringSync(),
        'retained page',
      );
    });
  }
}

class _SelectedDirectory extends Fake implements Directory {
  _SelectedDirectory(this.path, this.native);
  @override
  final String path;
  final Directory native;
  @override
  Future<bool> exists() => native.exists();
  @override
  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) => native.list(recursive: recursive, followLinks: followLinks);
}
