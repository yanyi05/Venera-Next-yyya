import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:venera_next/foundation/app_data_sync_fields.dart';
import 'record_sync_document.dart';

/// Converts an isolated archive directory, never live databases, into records.
abstract final class RecordSyncSnapshot {
  static const databases = ['history.db', 'local_favorite.db'];
  static String key(List<Object?> parts) => jsonEncode(parts);
  static String quote(String value) => '"${value.replaceAll('"', '""')}"';
  static Set<String> exclusions(String custom) => {
    ...appDataLocalFields.difference(appDataOptionalArchiveFields),
    ...splitAppDataFields(custom),
    'dataVersion',
  };

  static Map<String, dynamic> read(String directory, String custom) {
    final result = <String, dynamic>{};
    final data =
        jsonDecode(File(p.join(directory, 'appdata.json')).readAsStringSync())
            as Map;
    (data['settings'] as Map).forEach((name, value) {
      if (!exclusions(custom).contains(name)) {
        result[key(['setting', name])] = value;
      }
    });
    result[key(['searchHistory'])] = data['searchHistory'] ?? [];
    for (final name in databases) {
      final path = p.join(directory, name);
      if (!File(path).existsSync()) continue;
      final db = sqlite3.open(path);
      try {
        for (final t in db.select(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';",
        )) {
          final table = t['name'] as String;
          final columns = db.select('PRAGMA table_info(${quote(table)});');
          final schema = [
            for (final c in columns)
              {'name': c['name'], 'type': c['type'], 'pk': c['pk']},
          ];
          result[key(['table', name, table])] = schema;
          final primary = columns.where((c) => (c['pk'] as int) > 0).toList()
            ..sort((a, b) => (a['pk'] as int).compareTo(b['pk'] as int));
          for (final r in db.select('SELECT * FROM ${quote(table)};')) {
            final row = <String, dynamic>{
              for (final c in columns)
                c['name'] as String: _encode(r[c['name'] as String]),
            };
            final identity = primary.isEmpty
                ? row.values.toList()
                : primary.map((c) => row[c['name']]).toList();
            final rowKey = key(['row', name, table, identity]);
            if (name == 'history.db' && table == 'history') {
              final chapters = (row.remove('readEpisode') as String? ?? '')
                  .split(',')
                  .where((s) => s.isNotEmpty);
              for (final chapter in chapters) {
                result[key(['chapter', rowKey, chapter])] = true;
              }
              result[key(['duration', rowKey])] =
                  row.remove('read_duration_ms') ?? 0;
            }
            result[rowKey] = row;
          }
        }
      } finally {
        db.dispose();
      }
    }
    final sources = Directory(p.join(directory, 'comic_source'));
    if (sources.existsSync()) {
      for (final file in sources.listSync().whereType<File>()) {
        result[key(['source', p.basename(file.path)])] = base64Encode(
          file.readAsBytesSync(),
        );
      }
    }
    return result;
  }

  static Object? _encode(Object? value) =>
      value is Uint8List ? {'blob': base64Encode(value)} : value;
  static Object? _decode(Object? value) =>
      value is Map ? base64Decode(value['blob'] as String) : value;

  static void write(
    String directory,
    Map<String, dynamic> records,
    String custom,
  ) {
    final file = File(p.join(directory, 'appdata.json'));
    final data = jsonDecode(file.readAsStringSync()) as Map;
    final settings = data['settings'] as Map;
    settings.removeWhere((k, v) => !exclusions(custom).contains(k));
    for (final entry in records.entries) {
      final parts = jsonDecode(entry.key) as List;
      if (parts.first == 'setting' && !exclusions(custom).contains(parts[1])) {
        settings[parts[1]] = entry.value;
      }
      if (parts.first == 'searchHistory') data['searchHistory'] = entry.value;
    }
    file.writeAsStringSync(jsonEncode(data), flush: true);
    for (final name in databases) {
      final db = sqlite3.open(p.join(directory, name));
      try {
        db.execute('BEGIN IMMEDIATE;');
        final existing = db.select(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';",
        );
        final retained = <String>{};
        for (final table in existing) {
          final tableName = table['name'] as String;
          final desired = records[key(['table', name, tableName])];
          final current = [
            for (final c in db.select(
              'PRAGMA table_info(${quote(tableName)});',
            ))
              {'name': c['name'], 'type': c['type'], 'pk': c['pk']},
          ];
          if (RecordSyncDocument.equal(current, desired)) {
            // Keep constraints, indexes, defaults and triggers on unchanged tables.
            retained.add(tableName);
            db.execute('DELETE FROM ${quote(tableName)};');
          } else {
            db.execute('DROP TABLE ${quote(tableName)};');
          }
        }
        for (final entry in records.entries) {
          final parts = jsonDecode(entry.key) as List;
          if (parts.length != 3 || parts[0] != 'table' || parts[1] != name) {
            continue;
          }
          if (retained.contains(parts[2])) continue;
          final columns = entry.value as List;
          final primary = columns.where((c) => (c['pk'] as int) > 0).toList()
            ..sort((a, b) => (a['pk'] as int).compareTo(b['pk'] as int));
          String definition(dynamic c) {
            final type = (c['type'] as String).toUpperCase();
            if (!{
              'TEXT',
              'INT',
              'INTEGER',
              'REAL',
              'BLOB',
              'NUMERIC',
              '',
            }.contains(type)) {
              throw const FormatException('Unsupported sync column type');
            }
            return '${quote(c['name'] as String)} $type';
          }

          db.execute(
            'CREATE TABLE ${quote(parts[2] as String)} (${[...columns.map(definition), if (primary.isNotEmpty) 'PRIMARY KEY (${primary.map((c) => quote(c['name'] as String)).join(',')})'].join(',')});',
          );
        }
        for (final entry in records.entries) {
          final parts = jsonDecode(entry.key) as List;
          if (parts.length != 4 ||
              parts[0] != 'row' ||
              parts[1] != name ||
              !records.containsKey(key(['table', name, parts[2]]))) {
            continue;
          }
          final row = Map<String, dynamic>.from(entry.value as Map);
          if (name == 'history.db' && parts[2] == 'history') {
            final chapters = <String>[];
            for (final c in records.keys) {
              final ck = jsonDecode(c) as List;
              if (ck[0] == 'chapter' && ck[1] == entry.key) {
                chapters.add(ck[2] as String);
              }
            }
            chapters.sort(
              (a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0),
            );
            row['readEpisode'] = chapters.join(',');
            row['read_duration_ms'] =
                records[key(['duration', entry.key])] ?? 0;
          }
          db.execute(
            'INSERT INTO ${quote(parts[2] as String)} (${row.keys.map(quote).join(',')}) VALUES (${row.keys.map((_) => '?').join(',')});',
            row.values.map(_decode).toList(),
          );
        }
        db.execute('COMMIT;');
      } catch (_) {
        db.execute('ROLLBACK;');
        rethrow;
      } finally {
        db.dispose();
      }
    }
    final sources = Directory(p.join(directory, 'comic_source'))
      ..createSync(recursive: true);
    for (final file in sources.listSync().whereType<File>()) {
      file.deleteSync();
    }
    for (final entry in records.entries) {
      final parts = jsonDecode(entry.key) as List;
      if (parts[0] != 'source') continue;
      final name = parts[1] as String;
      if (name.isEmpty ||
          name != p.basename(name) ||
          name.contains('\\') ||
          name.contains('/') ||
          name == '.' ||
          name == '..') {
        throw const FormatException('Invalid source filename');
      }
      File(
        p.join(sources.path, name),
      ).writeAsBytesSync(base64Decode(entry.value as String), flush: true);
    }
  }
}
