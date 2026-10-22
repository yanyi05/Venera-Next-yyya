import 'dart:convert';

/// Causal registers retain concurrent versions until a later edit observes them.
/// Missing keys are tombstones, never evidence that an old snapshot is newer.
class RecordSyncDocument {
  RecordSyncDocument(this.device);
  final String device;
  final Map<String, int> clock = {};
  final Map<String, List<Map<String, dynamic>>> records = {};
  Map<String, dynamic> baseline = {};
  Map<String, dynamic>? pendingBefore;
  Map<String, dynamic>? pendingAfter;
  final Set<String> seen = {};
  final Map<String, String> uploads = {};
  final Map<String, List<Map<String, dynamic>>> outbox = {};

  static String canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return '{${keys.map((k) => '${jsonEncode(k)}:${canonical(value[k])}').join(',')}}';
    }
    if (value is List) return '[${value.map(canonical).join(',')}]';
    return jsonEncode(value);
  }

  static bool equal(Object? a, Object? b) => canonical(a) == canonical(b);

  void capture(
    Map<String, dynamic> current, {
    int? timestamp,
    int Function(String, dynamic)? seedTime,
  }) {
    final changed = {
      ...baseline.keys,
      ...current.keys,
    }.where((k) => !equal(baseline[k], current[k])).toList();
    if (changed.isEmpty) return;
    final context = Map<String, int>.of(clock);
    final counter = (clock[device] ?? 0) + 1;
    clock[device] = counter;
    for (final key in changed) {
      final event = <String, dynamic>{
        'device': device,
        'counter': counter,
        'context': context,
        'time':
            seedTime?.call(key, current[key]) ??
            timestamp ??
            DateTime.now().millisecondsSinceEpoch,
        'value': current[key],
      };
      records[key] = [event];
      outbox[key] = [event];
    }
    baseline = Map.of(current);
  }

  void merge(Map<String, dynamic> packet) {
    if (packet['format'] != 1 || packet['records'] is! Map) {
      throw const FormatException('Unsupported record sync document');
    }
    final incoming = Map<String, dynamic>.from(packet['records'] as Map);
    // Validate the entire packet before accepting any causal metadata.
    for (final entry in incoming.entries) {
      if (jsonDecode(entry.key) is! List || entry.value is! List) {
        throw const FormatException('Invalid sync record');
      }
      for (final raw in entry.value as List) {
        final e = Map<String, dynamic>.from(raw as Map);
        if (e['device'] is! String ||
            (e['device'] as String).isEmpty ||
            e['counter'] is! int ||
            (e['counter'] as int) < 1 ||
            e['time'] is! int ||
            e['context'] is! Map ||
            !(e['context'] as Map).entries.every(
              (x) => x.key is String && x.value is int && (x.value as int) >= 0,
            ) ||
            ((e['context'] as Map)[e['device']] as int? ?? 0) >=
                (e['counter'] as int)) {
          throw const FormatException('Invalid causal revision');
        }
      }
    }
    for (final entry in incoming.entries) {
      final all = <String, Map<String, dynamic>>{};
      for (final raw in [...?records[entry.key], ...entry.value as List]) {
        final e = Map<String, dynamic>.from(raw as Map);
        final id = '${e['device']}:${e['counter']}';
        if (all.containsKey(id) && !equal(all[id], e)) {
          throw const FormatException('Conflicting revision identity');
        }
        all[id] = e;
      }
      final frontier = all.values
          .where(
            (e) => !all.values.any(
              (other) =>
                  (other['context'][e['device']] as int? ?? 0) >=
                  (e['counter'] as int),
            ),
          )
          .toList();
      records[entry.key] = frontier;
      for (final e in all.values) {
        void observe(String id, int n) {
          if ((clock[id] ?? 0) < n) clock[id] = n;
        }

        observe(e['device'] as String, e['counter'] as int);
        (e['context'] as Map).forEach(
          (id, n) => observe(id as String, n as int),
        );
      }
    }
  }

  Map<String, dynamic> get projection {
    final result = <String, dynamic>{};
    for (final entry in records.entries) {
      final candidates = [...entry.value]
        ..sort((a, b) {
          // Concurrent removal wins; a deliberate later re-add still wins by causality.
          if ((a['value'] == null) != (b['value'] == null)) {
            return a['value'] == null ? 1 : -1;
          }
          final key = jsonDecode(entry.key) as List;
          if (key.first == 'duration' &&
              a['value'] is num &&
              b['value'] is num) {
            return (a['value'] as num).compareTo(b['value'] as num);
          }
          final time = (a['time'] as int).compareTo(b['time'] as int);
          if (time != 0) return time;
          final device = (a['device'] as String).compareTo(
            b['device'] as String,
          );
          return device != 0
              ? device
              : (a['counter'] as int).compareTo(b['counter'] as int);
        });
      if (candidates.isNotEmpty && candidates.last['value'] != null) {
        result[entry.key] = candidates.last['value'];
        if ((jsonDecode(entry.key) as List).first == 'table') {
          // Legacy archives may omit columns added in this app version. Keep
          // the union of concurrent schemas so importing an older row cannot
          // remove a column required by the current repository.
          final columns = <String, dynamic>{};
          for (final candidate in candidates.reversed) {
            for (final column in candidate['value'] as List) {
              columns.putIfAbsent(column['name'] as String, () => column);
            }
          }
          result[entry.key] = columns.values.toList();
        }
      }
    }
    result.removeWhere((key, value) {
      final parts = jsonDecode(key) as List;
      if ((parts[0] == 'chapter' || parts[0] == 'duration') &&
          !result.containsKey(parts[1])) {
        return true;
      }
      if (parts[0] == 'row' &&
          !result.containsKey(jsonEncode(['table', parts[1], parts[2]]))) {
        return true;
      }
      return false;
    });
    return result;
  }

  /// Replay only entries still matching the pre-import image. New local edits
  /// made after a crash are preserved and captured as later causal revisions.
  Map<String, dynamic> recover(Map<String, dynamic> actual) {
    final before = pendingBefore;
    final after = pendingAfter;
    if (before == null || after == null) return actual;
    final recovered = Map<String, dynamic>.of(actual);
    for (final key in {...before.keys, ...after.keys}) {
      if (equal(actual[key], before[key])) {
        if (after.containsKey(key)) {
          recovered[key] = after[key];
        } else {
          recovered.remove(key);
        }
      }
    }
    return recovered;
  }

  Map<String, dynamic> get packet => {'format': 1, 'records': outbox};
  void acknowledge(Map<String, dynamic> sent) {
    (sent['records'] as Map).forEach((key, value) {
      final pending = outbox[key];
      if (pending != null &&
          pending.every(
            (e) => (value as List).any(
              (included) =>
                  equal(e, included) ||
                  (included['context'][e['device']] as int? ?? 0) >=
                      (e['counter'] as int),
            ),
          )) {
        outbox.remove(key);
      }
    });
  }

  Map<String, dynamic> toJson() => {
    'device': device,
    'format': 1,
    'records': records,
    'baseline': baseline,
    'clock': clock,
    'outbox': outbox,
    'seen': seen.toList(),
    'uploads': uploads,
    'pendingBefore': pendingBefore,
    'pendingAfter': pendingAfter,
  };

  factory RecordSyncDocument.fromJson(Map<String, dynamic> json) {
    final result = RecordSyncDocument(json['device'] as String)..merge(json);
    result.clock.addAll(Map<String, int>.from(json['clock'] as Map));
    result.baseline = Map<String, dynamic>.from(json['baseline'] as Map);
    result.seen.addAll((json['seen'] as List).cast<String>());
    result.uploads.addAll(
      Map<String, String>.from(json['uploads'] as Map? ?? {}),
    );
    (json['outbox'] as Map).forEach((key, value) {
      result.outbox[key as String] = (value as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    });
    result.pendingBefore = (json['pendingBefore'] as Map?)
        ?.cast<String, dynamic>();
    result.pendingAfter = (json['pendingAfter'] as Map?)
        ?.cast<String, dynamic>();
    return result;
  }
}
