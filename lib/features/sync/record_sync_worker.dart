import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:crypto/crypto.dart';
import 'record_sync_document.dart';
import 'record_sync_snapshot.dart';
import 'record_sync_store.dart';

/// Owns every sync journal connection, full document and CPU-heavy operation.
/// Messages carry paths and small results, never the full 3 MB document.
class RecordSyncWorker {
  final _messages = ReceivePort();
  final _ready = Completer<SendPort>();
  final _requests = <int, Completer<dynamic>>{};
  int _id = 0;
  bool _closed = false;
  bool _exited = false;

  static Future<RecordSyncWorker> open(
    String path,
    String scope,
    String root,
  ) async {
    final worker = RecordSyncWorker();
    worker._messages.listen(worker._receive);
    try {
      await Isolate.spawn(
        _workerMain,
        worker._messages.sendPort,
        onExit: worker._messages.sendPort,
        onError: worker._messages.sendPort,
      );
      await worker.call('open', {'path': path, 'scope': scope, 'root': root});
      return worker;
    } catch (_) {
      await worker.close();
      rethrow;
    }
  }

  void _receive(dynamic message) {
    if (message is SendPort) {
      _ready.complete(message);
      return;
    }
    if (message is List && message.length == 3 && message[0] is int) {
      final pending = _requests.remove(message[0]);
      if (message[1] == true) {
        pending?.complete(message[2]);
      } else {
        final error = message[2] as List;
        pending?.completeError(
          error[0] == 'format'
              ? FormatException(error[1] as String)
              : StateError(error[1] as String),
          StackTrace.fromString(error[2] as String),
        );
      }
      return;
    }
    final failure = StateError('Record sync worker exited unexpectedly');
    _exited = true;
    if (!_ready.isCompleted) _ready.completeError(failure);
    for (final request in _requests.values) {
      request.completeError(failure);
    }
    _requests.clear();
  }

  Future<dynamic> call(
    String command, [
    Map<String, dynamic> data = const {},
  ]) async {
    if (_closed || _exited) throw StateError('Record sync worker is closed');
    final port = await _ready.future;
    final id = ++_id;
    final result = Completer<dynamic>();
    _requests[id] = result;
    port.send([id, command, data]);
    return result.future;
  }

  Future<void> close() async {
    if (_closed) return;
    try {
      if (!_exited && _ready.isCompleted) await call('close');
    } finally {
      _closed = true;
      _messages.close();
    }
  }
}

void _workerMain(SendPort parent) async {
  final requests = ReceivePort();
  parent.send(requests.sendPort);
  _WorkerState? state;
  await for (final dynamic message in requests) {
    final id = message[0] as int;
    final command = message[1] as String;
    final data = Map<String, dynamic>.from(message[2] as Map);
    try {
      dynamic result;
      if (command == 'open') {
        state = _WorkerState(
          data['path'] as String,
          data['scope'] as String,
          data['root'] as String,
        );
      } else if (command == 'close') {
        state?.store.close();
        parent.send([id, true, null]);
        requests.close();
        return;
      } else {
        result = state!.handle(command, data);
      }
      parent.send([id, true, result]);
    } catch (error, stack) {
      parent.send([
        id,
        false,
        [
          error is FormatException ? 'format' : 'state',
          error.toString(),
          stack.toString(),
        ],
      ]);
    }
  }
}

class _WorkerState {
  _WorkerState(String path, this.scope, this.root)
    : store = RecordSyncStore(path) {
    try {
      document = store.load(scope);
    } catch (_) {
      store.close();
      rethrow;
    }
  }
  final RecordSyncStore store;
  final String scope, root;
  late final RecordSyncDocument document;
  Map<String, dynamic>? _legacy;
  Map<String, dynamic>? _target;
  Map<String, dynamic>? _recovered;
  List<String> _accepted = [];
  void save() => store.save(scope, document);
  static const prefix = 'venera-records-v1-';

  dynamic handle(String command, Map<String, dynamic> data) {
    switch (command) {
      case 'seen':
        return document.seen.toList();
      case 'recover':
        if (document.pendingAfter == null) return null;
        final stage = data['stage'] as String;
        final excluded = data['excluded'] as String;
        final actual = RecordSyncSnapshot.read(stage, excluded);
        _recovered = document.recover(actual);
        final changed = !RecordSyncDocument.equal(actual, _recovered);
        if (changed) RecordSyncSnapshot.write(stage, _recovered!, excluded);
        return changed;
      case 'recovered':
        document.baseline = Map.of(document.pendingAfter!);
        document.pendingBefore = null;
        document.pendingAfter = null;
        document.capture(_recovered!);
        _recovered = null;
        save();
        return null;
      case 'legacy':
        final archive = File(data['archive'] as String);
        final seed = RecordSyncDocument(
          'legacy-${sha256.convert(archive.readAsBytesSync())}',
        );
        seed.capture(
          RecordSyncSnapshot.read(data['stage'] as String, ''),
          seedTime: _seedTime,
        );
        _legacy = seed.packet;
        return null;
      case 'plan':
        final stage = data['stage'] as String;
        final excluded = data['excluded'] as String;
        final actual = RecordSyncSnapshot.read(stage, excluded);
        document.capture(
          actual,
          seedTime: document.records.isEmpty ? _seedTime : null,
        );
        _accepted = [];
        void merge(Map<String, dynamic> packet, String name) {
          final records = Map<String, dynamic>.from(packet['records'] as Map);
          records.removeWhere((key, value) {
            final parts = jsonDecode(key) as List;
            return parts[0] == 'setting' &&
                RecordSyncSnapshot.exclusions('').contains(parts[1]);
          });
          document.merge({...packet, 'records': records});
          _accepted.add(name);
        }
        for (final item in data['incoming'] as List) {
          final name = item[0] as String;
          final bytes = File(item[1] as String).readAsBytesSync();
          if (name != '$prefix${sha256.convert(bytes)}.json') {
            throw const FormatException(
              'Incomplete or damaged record sync batch; retry later',
            );
          }
          merge(
            Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)) as Map),
            name,
          );
        }
        if (_legacy != null) merge(_legacy!, 'legacy-bootstrap');
        _target = document.projection;
        _target!.removeWhere((key, value) {
          final parts = jsonDecode(key) as List;
          return parts[0] == 'setting' &&
              RecordSyncSnapshot.exclusions(excluded).contains(parts[1]);
        });
        final changed = !RecordSyncDocument.equal(actual, _target);
        if (changed) {
          document.pendingBefore = Map.of(actual);
          document.pendingAfter = Map.of(_target!);
          save();
          RecordSyncSnapshot.write(stage, _target!, excluded);
        }
        return changed;
      case 'applied':
        document.baseline = Map.of(_target!);
        document.pendingBefore = null;
        document.pendingAfter = null;
        document.seen.addAll(_accepted);
        _legacy = null;
        save();
        _target = null;
        return null;
      case 'prepareUpload':
        final compact = data['compact'] == true;
        if (!compact && document.outbox.isEmpty) return null;
        final packet = compact
            ? {'format': 1, 'records': document.records, 'checkpoint': true}
            : document.packet;
        final payload = RecordSyncDocument.canonical(packet);
        final name = '$prefix${sha256.convert(utf8.encode(payload))}.json';
        document.uploads[name] = payload;
        save();
        return name;
      case 'uploads':
        return [
          for (final upload in document.uploads.entries)
            _uploadFile(upload.key, upload.value),
        ];
      case 'ack':
        final name = data['name'] as String;
        final payload = document.uploads[name]!;
        final packet = Map<String, dynamic>.from(jsonDecode(payload) as Map);
        if (packet['checkpoint'] == true &&
            sha256
                    .convert(
                      File(data['verification'] as String).readAsBytesSync(),
                    )
                    .toString() !=
                sha256.convert(utf8.encode(payload)).toString()) {
          throw const FormatException('Checkpoint verification failed');
        }
        document.acknowledge(packet);
        document.seen.add(name);
        document.uploads.remove(name);
        save();
        return null;
      case 'forget':
        document.seen.removeAll((data['names'] as List).cast<String>());
        save();
        return null;
      default:
        throw StateError('Unknown record sync worker command');
    }
  }

  Map<String, dynamic> _uploadFile(String name, String payload) {
    final file = File('$root/outgoing/$name');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(payload, flush: true);
    return {
      'name': name,
      'path': file.path,
      'checkpoint': (jsonDecode(payload) as Map)['checkpoint'] == true,
    };
  }

  static int _seedTime(String key, dynamic value) {
    final parts = jsonDecode(key) as List;
    if (parts[0] == 'row' && value is Map) {
      final time = value['time'];
      if (time is int) return time;
      if (time is String) {
        return DateTime.tryParse(time)?.millisecondsSinceEpoch ?? 0;
      }
    }
    return 0;
  }
}
