import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/features/sync/record_sync_document.dart';

String k(String value) => jsonEncode(['test', value]);
RecordSyncDocument clone(RecordSyncDocument d, String device) {
  final copy = RecordSyncDocument(device)
    ..merge({'format': 1, 'records': d.records});
  copy.baseline = Map.of(copy.projection);
  return copy;
}

void main() {
  test(
    'two offline devices retain independent edits and latest reread position',
    () {
      final a = RecordSyncDocument('a')
        ..capture({k('progress'): 30}, timestamp: 1);
      final b = clone(a, 'b');
      a.capture({k('progress'): 35, k('favorite-A'): true}, timestamp: 10);
      b.capture({k('progress'): 2, k('favorite-B'): true}, timestamp: 20);
      final ap = {'format': 1, 'records': a.records};
      final bp = {'format': 1, 'records': b.records};
      a.merge(bp);
      b.merge(ap);
      expect(a.projection, b.projection);
      expect(a.projection, {
        k('progress'): 2,
        k('favorite-A'): true,
        k('favorite-B'): true,
      });
    },
  );

  test('causally later edits win even after device clock moves backwards', () {
    final a = RecordSyncDocument('a')..capture({k('p'): 10}, timestamp: 99999);
    final b = clone(a, 'b')..capture({k('p'): 20}, timestamp: 2);
    a.merge(b.packet);
    expect(a.projection[k('p')], 20);
  });

  test(
    'read chapter union, reset and deletion survive stale device reconnect',
    () {
      final a = RecordSyncDocument('a')
        ..capture({k('chapter1'): true}, timestamp: 1);
      final b = clone(a, 'b');
      a.capture({k('chapter1'): true, k('chapter2'): true}, timestamp: 2);
      b.capture({k('chapter1'): true, k('chapter3'): true}, timestamp: 3);
      a.merge(b.packet);
      a.baseline = Map.of(a.projection);
      expect(a.projection.length, 3);
      final stale =
          jsonDecode(jsonEncode({'format': 1, 'records': a.records}))
              as Map<String, dynamic>;
      a.capture({}, timestamp: 4);
      a.merge(stale);
      expect(a.projection, isEmpty);
      b.merge({'format': 1, 'records': a.records});
      expect(b.projection, isEmpty);
    },
  );

  test(
    'concurrent delete wins but intentional re-add after merge is allowed',
    () {
      final a = RecordSyncDocument('a')..capture({k('f'): 'old'}, timestamp: 1);
      final b = clone(a, 'b');
      a.capture({}, timestamp: 10);
      b.capture({k('f'): 'edited'}, timestamp: 20);
      a.merge(b.packet);
      expect(a.projection, isEmpty);
      a.baseline = {};
      a.capture({k('f'): 're-added'}, timestamp: 2);
      b.merge(a.packet);
      expect(b.projection[k('f')], 're-added');
    },
  );

  test(
    'merge is commutative, associative and idempotent with three writers',
    () {
      final base = RecordSyncDocument('base')
        ..capture({k('p'): 0}, timestamp: 1);
      final a = clone(base, 'a')..capture({k('p'): 1}, timestamp: 2);
      final b = clone(base, 'b')..capture({k('p'): 2}, timestamp: 2);
      final c = clone(base, 'c')..capture({}, timestamp: 3);
      final permutations = [
        [a, b, c],
        [a, c, b],
        [b, a, c],
        [b, c, a],
        [c, a, b],
        [c, b, a],
      ];
      for (final order in permutations) {
        final result = RecordSyncDocument('reader');
        for (final d in [...order, ...order.reversed]) {
          result.merge({'format': 1, 'records': d.records});
        }
        expect(result.projection, isEmpty);
        expect(result.records[k('p')]!.length, 3);
      }
    },
  );

  test(
    'upload acknowledgement never clears a newer edit to the same record',
    () {
      final a = RecordSyncDocument('a')..capture({k('p'): 1}, timestamp: 1);
      final sent = jsonDecode(jsonEncode(a.packet)) as Map<String, dynamic>;
      a.capture({k('p'): 2}, timestamp: 2);
      a.acknowledge(sent);
      expect(a.outbox, isNotEmpty);
      a.acknowledge(jsonDecode(jsonEncode(a.packet)) as Map<String, dynamic>);
      expect(a.outbox, isEmpty);
    },
  );

  test(
    'crash during apply replays unchanged fields and preserves later local edits',
    () {
      final a = RecordSyncDocument('a')
        ..capture({k('p'): 1, k('f'): true}, timestamp: 1);
      a.pendingBefore = {k('p'): 1, k('f'): true};
      a.pendingAfter = {k('p'): 2, k('new'): true};
      final restored = RecordSyncDocument.fromJson(
        jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>,
      );
      expect(restored.recover({k('p'): 1, k('f'): true}), {
        k('p'): 2,
        k('new'): true,
      });
      expect(restored.recover({k('p'): 3, k('f'): true}), {
        k('p'): 3,
        k('new'): true,
      });
      expect(restored.recover({k('p'): 2, k('new'): true}), {
        k('p'): 2,
        k('new'): true,
      });
    },
  );

  test('malformed revisions fail without advancing the local causal clock', () {
    final a = RecordSyncDocument('a')..capture({k('p'): 1}, timestamp: 1);
    final before = jsonEncode(a.toJson());
    expect(
      () => a.merge({
        'format': 1,
        'records': {
          k('p'): [
            {
              'device': 'b',
              'counter': -1,
              'context': {},
              'time': 1,
              'value': 99,
            },
          ],
        },
      }),
      throwsFormatException,
    );
    expect(jsonEncode(a.toJson()), before);
  });
}
