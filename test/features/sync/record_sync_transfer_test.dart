import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:venera_next/app_runtime/record_data_sync.dart';
import 'package:venera_next/features/sync/record_sync_application.dart';
import 'package:venera_next/features/sync/data_sync_commit.dart';
import 'package:venera_next/features/sync/record_sync_snapshot.dart';
import 'package:venera_next/network/request_scope.dart';
import 'package:venera_next/network/webdav.dart';
import 'package:webdav_client/webdav_client.dart' as dav;

void main() {
  late Directory root;
  late _Server server;
  late _App a;
  late _App b;
  final endpoint = WebDavEndpoint(
    url: 'https://dav.example.test',
    user: '',
    password: '',
  );
  Future<void> sync(_App app, {int compactAfter = 64}) async {
    final scope = RequestScope();
    try {
      await RecordDataSyncTransfer(
        application: app,
        compactAfter: compactAfter,
        createClient: (_) => _Client(server),
      ).download(endpoint, scope: scope);
    } finally {
      scope.dispose();
    }
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('record-transport-test-');
    server = _Server();
    a = _App('${root.path}/a');
    b = _App('${root.path}/b');
  });
  tearDown(() => root.deleteSync(recursive: true));

  test(
    'cleanup failure retains confirmed commit evidence and does not re-publish acknowledged data',
    () async {
      server.failClose = true;
      await expectLater(
        sync(a),
        throwsA(
          isA<DataSyncFailure>().having(
            (e) => e.commitState,
            'commit',
            DataSyncCommitState.applied,
          ),
        ),
      );
      expect(server.files, hasLength(1));
      server.failClose = false;
      await sync(a);
      expect(server.files, hasLength(1));
    },
  );

  test('cleanup failure preserves the original network error', () async {
    server.offline = true;
    server.failClose = true;
    await expectLater(
      sync(a),
      throwsA(
        isA<DataSyncFailure>().having(
          (e) => e.failures.length,
          'both failures',
          2,
        ),
      ),
    );
  });

  test(
    'verified checkpoint bounds remote batches and preserves tombstones for an offline device',
    () async {
      a.favorite('old');
      await sync(a, compactAfter: 2);
      await sync(b, compactAfter: 2);
      a.deleteFavorite('old');
      await sync(a, compactAfter: 2);
      expect(server.files, hasLength(1));
      expect(server.deletes, 2);
      await sync(b, compactAfter: 2);
      expect(b.favorites, isEmpty);
      final c = _App('${root.path}/c')..favorite('old');
      await sync(c, compactAfter: 2);
      expect(c.favorites, isEmpty);
    },
  );

  test(
    'compaction preserves fields excluded on this device for other devices',
    () async {
      await sync(a);
      a.setting('theme', 'blue');
      await sync(a);
      b.excluded = 'theme';
      b.setting('theme', 'local-light');
      await sync(b, compactAfter: 2);
      expect(b.readSetting('theme'), 'local-light');
      expect(server.files, hasLength(1));
      final c = _App('${root.path}/c');
      await sync(c);
      expect(c.readSetting('theme'), 'blue');
    },
  );

  test(
    'legacy backup bootstraps records without replacing independent local favorites',
    () async {
      b.edit(25, '1,2,25');
      b.favorite('cloud');
      a.favorite('local');
      final archive = Archive();
      for (final name in ['history.db', 'local_favorite.db', 'appdata.json']) {
        final bytes = File('${b.dataPath}/$name').readAsBytesSync();
        archive.addFile(ArchiveFile(name, bytes.length, bytes));
      }
      final legacy = Uint8List.fromList(ZipEncoder().encode(archive));
      server.files['1-99.venera'] = legacy;
      await sync(a);
      expect(a.row['page'], 25);
      expect(a.favorites, ['cloud', 'local']);
      expect(server.files['1-99.venera'], legacy);
      expect(server.deletes, 0);
      await sync(b);
      expect(b.favorites, ['cloud', 'local']);
    },
  );

  test(
    'two devices converge favorites, visited chapters, rereading and deletions',
    () async {
      await sync(a);
      await sync(b);
      a.edit(5, '1,2,3');
      a.favorite('A');
      b.edit(2, '1,2,4');
      b.favorite('B');
      await sync(a);
      await sync(b);
      await sync(a);
      expect(a.row['page'], 2);
      expect(a.row['readEpisode'], '1,2,3,4');
      expect(a.favorites, ['A', 'B']);
      expect(
        RecordSyncSnapshot.read(a.dataPath, ''),
        RecordSyncSnapshot.read(b.dataPath, ''),
      );
      a.deleteFavorite('A');
      await sync(a);
      // B reconnects with the old favorite still present; it must not resurrect it.
      await sync(b);
      expect(b.favorites, ['B']);
      b.edit(1, '');
      await sync(b);
      await sync(a);
      expect(a.row['readEpisode'], '');
    },
  );

  test(
    'offline edits are recovered after recreating the transfer and reconnecting',
    () async {
      server.offline = true;
      a.edit(8, '1,2,3');
      await expectLater(sync(a), throwsStateError);
      a.edit(9, '1,2,3,4');
      server.offline = false;
      await sync(a);
      await sync(b);
      expect(b.row['page'], 9);
      expect(b.row['readEpisode'], '1,2,3,4');
    },
  );

  test(
    'interrupted PUT is repaired after restart even when newer edits exist',
    () async {
      server.interruptNextWrite = true;
      await expectLater(sync(a), throwsStateError);
      expect(server.files.length, 1);
      a.edit(7, '1,2,7');
      await sync(a);
      expect(server.files.length, 2);
      await sync(b);
      expect(b.row['page'], 7);
      expect(b.row['readEpisode'], '1,2,7');
      expect(
        server.files.length,
        3,
      ); // B also publishes its initial local snapshot.
      expect(server.deletes, 0);
    },
  );

  test(
    'edits made during directory request are captured before applying remote records',
    () async {
      await sync(a);
      await sync(b);
      a.favorite('remote');
      await sync(a);
      server.onList = () {
        b.edit(11, '1,2,11');
        server.onList = null;
      };
      await sync(b);
      await sync(a);
      expect(b.row['page'], 11);
      expect(a.row['page'], 11);
      expect(b.favorites, ['remote']);
    },
  );

  test('corrupt remote batch is not acknowledged or applied', () async {
    await sync(a);
    final name = server.files.keys.single;
    server.files[name] = Uint8List.fromList([1, 2, 3]);
    final before = RecordSyncSnapshot.read(b.dataPath, '');
    await expectLater(sync(b), throwsFormatException);
    expect(RecordSyncSnapshot.read(b.dataPath, ''), before);
    expect(b.synced, 0);
  });

  test('a failed application commit is replayed on the next attempt', () async {
    await sync(a);
    await sync(b);
    a.favorite('recover');
    await sync(a);
    b.failApply = true;
    await expectLater(sync(b), throwsStateError);
    b.edit(12, '1,2,12');
    b.failApply = false;
    await sync(b);
    await sync(a);
    expect(b.favorites, ['recover']);
    expect(a.row['page'], 12);
  });
}

class _App implements RecordSyncApplication {
  _App(this.dataPath) {
    Directory(dataPath).createSync(recursive: true);
    Directory(cachePath).createSync();
    Directory('$dataPath/comic_source').createSync();
    File('$dataPath/appdata.json').writeAsStringSync(
      jsonEncode({
        'settings': {'theme': 'dark'},
        'searchHistory': [],
      }),
    );
    final history = sqlite3.open('$dataPath/history.db');
    history.execute(
      'CREATE TABLE history (id TEXT PRIMARY KEY, page INT, time INT, readEpisode TEXT, read_duration_ms INT);',
    );
    history.execute("INSERT INTO history VALUES ('comic', 1, 1, '1,2', 0);");
    history.dispose();
    final favorites = sqlite3.open('$dataPath/local_favorite.db');
    favorites.execute(
      'CREATE TABLE favorites (id TEXT PRIMARY KEY, name TEXT);',
    );
    favorites.dispose();
  }
  @override
  final String dataPath;
  @override
  String get cachePath => '$dataPath/cache';
  @override
  String get excludedFields => excluded;
  String excluded = '';
  dynamic readSetting(String name) =>
      (jsonDecode(File('$dataPath/appdata.json').readAsStringSync())
          as Map)['settings'][name];
  void setting(String name, dynamic value) {
    final file = File('$dataPath/appdata.json');
    final data = jsonDecode(file.readAsStringSync()) as Map;
    data['settings'][name] = value;
    file.writeAsStringSync(jsonEncode(data));
  }

  @override
  Future<T> exclusive<T>(Future<T> Function() action) => action();
  int synced = 0;
  bool failApply = false;
  @override
  Future<void> recordSyncTime() async {
    synced++;
  }

  @override
  Future<void> capture(Directory staging) async {
    for (final name in ['history.db', 'local_favorite.db', 'appdata.json']) {
      File('$dataPath/$name').copySync('${staging.path}/$name');
    }
    Directory('${staging.path}/comic_source').createSync();
  }

  @override
  Future<void> apply(
    Directory staging,
    RequestScope scope,
    void Function(void Function())? publish,
  ) async {
    if (failApply) throw StateError('commit interrupted');
    for (final name in ['history.db', 'local_favorite.db', 'appdata.json']) {
      File('${staging.path}/$name').copySync('$dataPath/$name');
    }
  }

  void edit(int page, String chapters) {
    final db = sqlite3.open('$dataPath/history.db');
    db.execute('UPDATE history SET page=?, readEpisode=?, time=?;', [
      page,
      chapters,
      DateTime.now().millisecondsSinceEpoch,
    ]);
    db.dispose();
  }

  Map<String, Object?> get row {
    final db = sqlite3.open('$dataPath/history.db');
    try {
      return Map.of(db.select('SELECT * FROM history;').single);
    } finally {
      db.dispose();
    }
  }

  void favorite(String id) {
    final db = sqlite3.open('$dataPath/local_favorite.db');
    db.execute('INSERT OR REPLACE INTO favorites VALUES (?,?);', [id, id]);
    db.dispose();
  }

  void deleteFavorite(String id) {
    final db = sqlite3.open('$dataPath/local_favorite.db');
    db.execute('DELETE FROM favorites WHERE id=?;', [id]);
    db.dispose();
  }

  List<String> get favorites {
    final db = sqlite3.open('$dataPath/local_favorite.db');
    try {
      return db
          .select('SELECT id FROM favorites ORDER BY id;')
          .map((r) => r['id'] as String)
          .toList();
    } finally {
      db.dispose();
    }
  }
}

class _Server {
  bool failClose = false;
  final files = <String, Uint8List>{};
  bool offline = false;
  bool interruptNextWrite = false;
  int deletes = 0;
  void Function()? onList;
}

class _Dio extends dav.WdDio {
  _Dio(this.server);
  final _Server server;
  @override
  void close({bool force = false}) {
    super.close(force: force);
    if (server.failClose) throw StateError('close failed');
  }
}

class _Client extends dav.Client {
  _Client(this.server)
    : super(
        uri: 'https://dav.example.test',
        c: _Dio(server),
        auth: const dav.Auth(user: '', pwd: ''),
      );
  final _Server server;
  @override
  Future<List<dav.File>> readDir(
    String path, [
    CancelToken? cancelToken,
  ]) async {
    if (server.offline) throw StateError('offline');
    server.onList?.call();
    return server.files.keys.map((k) => dav.File(name: k)).toList();
  }

  @override
  Future<void> read2File(
    String path,
    String savePath, {
    void Function(int, int)? onProgress,
    CancelToken? cancelToken,
  }) async {
    File(savePath).writeAsBytesSync(server.files[path]!);
  }

  @override
  Future<void> write(
    String path,
    Uint8List data, {
    void Function(int, int)? onProgress,
    CancelToken? cancelToken,
  }) async {
    if (server.offline) throw StateError('offline');
    if (server.interruptNextWrite) {
      server.interruptNextWrite = false;
      server.files[path] = Uint8List.fromList(data.take(10).toList());
      throw StateError('connection lost during PUT');
    }
    server.files[path] = Uint8List.fromList(data);
  }

  @override
  Future<void> remove(String path, [CancelToken? cancelToken]) async {
    server.deletes++;
    server.files.remove(path);
  }
}
