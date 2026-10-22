import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:venera_next/features/sync/record_sync_document.dart';
import 'package:venera_next/features/sync/record_sync_snapshot.dart';
import 'package:venera_next/features/sync/record_sync_store.dart';

void main() {
  late Directory root;
  setUp(() {
    root = Directory.systemTemp.createTempSync('record-sync-test-');
    File('${root.path}/appdata.json').writeAsStringSync(
      jsonEncode({
        'settings': {
          'webdav': ['private'],
          'deviceId': 'local',
          'theme': 'dark',
          'secret': 'keep',
        },
        'searchHistory': ['comic'],
      }),
    );
    Directory('${root.path}/comic_source').createSync();
    File('${root.path}/comic_source/baozi.js').writeAsStringSync('source');
    final db = sqlite3.open('${root.path}/history.db');
    db.execute(
      'CREATE TABLE history (id TEXT PRIMARY KEY, ep INT, page INT, time INT, readEpisode TEXT, read_duration_ms INTEGER NOT NULL DEFAULT 0);',
    );
    db.execute("INSERT INTO history VALUES ('comic', 2, 5, 10, '1,2', 100);");
    db.execute('CREATE INDEX history_time ON history(time);');
    db.dispose();
    final favorites = sqlite3.open('${root.path}/local_favorite.db');
    favorites.execute(
      'CREATE TABLE "收藏""夹" (id TEXT, type INT, name TEXT, PRIMARY KEY(id,type));',
    );
    favorites.execute('INSERT INTO "收藏""夹" VALUES (?, ?, ?);', ['c', 1, '漫画']);
    favorites.dispose();
  });
  tearDown(() => root.deleteSync(recursive: true));

  test(
    'record projection round trips SQL, chapter sets, sources and local exclusions',
    () {
      final records = RecordSyncSnapshot.read(root.path, 'secret');
      expect(
        records.containsKey(RecordSyncSnapshot.key(['setting', 'webdav'])),
        isFalse,
      );
      expect(
        records.containsKey(RecordSyncSnapshot.key(['setting', 'secret'])),
        isFalse,
      );
      RecordSyncSnapshot.write(root.path, records, 'secret');
      expect(RecordSyncSnapshot.read(root.path, 'secret'), records);
      final settings =
          (jsonDecode(File('${root.path}/appdata.json').readAsStringSync())
              as Map)['settings'];
      expect(settings['webdav'], ['private']);
      expect(settings['secret'], 'keep');
      final db = sqlite3.open('${root.path}/history.db');
      expect(
        db.select(
          "SELECT name FROM sqlite_master WHERE type='index' AND name='history_time';",
        ),
        hasLength(1),
      );
      db.execute("INSERT INTO history (id) VALUES ('new');");
      expect(
        db
            .select("SELECT read_duration_ms FROM history WHERE id='new';")
            .single['read_duration_ms'],
        0,
      );
      db.dispose();
    },
  );

  test(
    'two snapshots merge independently read chapters and favorite additions',
    () {
      final first = RecordSyncSnapshot.read(root.path, '');
      final a = RecordSyncDocument('a')..capture(first, timestamp: 1);
      final b = RecordSyncDocument('b')..merge(a.packet);
      b.baseline = Map.of(b.projection);
      final rowKey = first.keys.firstWhere((k) {
        final parts = jsonDecode(k) as List;
        return parts[0] == 'row' && parts[2] == 'history';
      });
      final aState = Map<String, dynamic>.of(first)
        ..[RecordSyncSnapshot.key(['chapter', rowKey, '3'])] = true;
      final bState = Map<String, dynamic>.of(first)
        ..[RecordSyncSnapshot.key(['chapter', rowKey, '4'])] = true;
      a.capture(aState, timestamp: 2);
      b.capture(bState, timestamp: 3);
      a.merge(b.packet);
      RecordSyncSnapshot.write(root.path, a.projection, '');
      final db = sqlite3.open('${root.path}/history.db');
      expect(
        db.select('SELECT readEpisode FROM history;').single['readEpisode'],
        '1,2,3,4',
      );
      db.dispose();
    },
  );

  test('outbox and incomplete projection survive reopening the journal', () {
    var store = RecordSyncStore('${root.path}/journal.db');
    final d = store.load('endpoint')
      ..capture(RecordSyncSnapshot.read(root.path, ''), timestamp: 1);
    d.pendingBefore = d.baseline;
    d.pendingAfter = {};
    store.save('endpoint', d);
    store.close();
    store = RecordSyncStore('${root.path}/journal.db');
    final restored = store.load('endpoint');
    expect(restored.device, d.device);
    expect(restored.outbox, d.outbox);
    expect(restored.pendingAfter, isEmpty);
    expect(store.load('different-selection').device, isNot(d.device));
    store.close();
  });

  test('remote SQL identifiers cannot execute extra statements', () {
    final records = RecordSyncSnapshot.read(root.path, '');
    records[RecordSyncSnapshot.key([
      'table',
      'local_favorite.db',
      'x"); DROP TABLE history; --',
    ])] = [
      {'name': 'id', 'type': 'TEXT); DROP TABLE history; --', 'pk': 1},
    ];
    expect(
      () => RecordSyncSnapshot.write(root.path, records, ''),
      throwsFormatException,
    );
    final db = sqlite3.open('${root.path}/history.db');
    expect(db.select('SELECT * FROM history;'), hasLength(1));
    db.dispose();
  });
}
