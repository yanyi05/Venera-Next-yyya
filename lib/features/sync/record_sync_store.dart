import 'dart:convert';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';
import 'record_sync_document.dart';

/// Device identity and outbox are deliberately outside exported app archives.
class RecordSyncStore {
  RecordSyncStore(String path) : db = sqlite3.open(path) {
    db.execute('PRAGMA synchronous=FULL;');
    db.execute(
      'CREATE TABLE IF NOT EXISTS state (id TEXT PRIMARY KEY, value TEXT NOT NULL);',
    );
    final identity = db.select("SELECT value FROM state WHERE id='device';");
    device = identity.isEmpty
        ? const Uuid().v4()
        : identity.single['value'] as String;
    if (identity.isEmpty) {
      db.execute("INSERT INTO state VALUES ('device', ?);", [device]);
    }
  }
  final Database db;
  late final String device;

  RecordSyncDocument load(String scope) {
    final rows = db.select('SELECT value FROM state WHERE id=?;', [scope]);
    return rows.isEmpty
        ? RecordSyncDocument('$device-${const Uuid().v4()}')
        : RecordSyncDocument.fromJson(
            Map<String, dynamic>.from(
              jsonDecode(rows.single['value'] as String) as Map,
            ),
          );
  }

  void save(String scope, RecordSyncDocument document) => db.execute(
    'INSERT OR REPLACE INTO state VALUES (?, ?);',
    [scope, jsonEncode(document.toJson())],
  );
  void close() => db.dispose();
}
