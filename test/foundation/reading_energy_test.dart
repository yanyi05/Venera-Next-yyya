import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/foundation/reading_energy.dart';

void main() {
  test(
    'thermal and low power categories preserve foreground reading',
    () async {
      final policy = ReadingEnergyPolicy();
      expect(policy.prefetchConcurrency, 2);
      policy.update(1, false);
      expect(policy.prefetchConcurrency, 1);
      expect(policy.deferAutomaticDownloads, false);
      policy.update(2, false);
      expect(policy.prefetchConcurrency, 0);
      final stop = Completer<void>();
      var ready = false;
      final waiting = policy
          .waitForAutomaticDownloads(stop.future)
          .then((value) => ready = value);
      await pumpEventQueue();
      expect(ready, false);
      policy.update(0, true);
      expect(policy.prefetchConcurrency, 1);
      await pumpEventQueue();
      expect(ready, false);
      policy.update(0, false);
      await waiting;
      expect(ready, true);
      stop.complete();
      policy.update(3, false);
      final cancel = Completer<void>();
      final cancelled = policy.waitForAutomaticDownloads(cancel.future);
      cancel.complete();
      expect(await cancelled, false);
      policy.update(99, false);
      expect(policy.thermal, 3);
      policy.update(0, false);
      policy.dispose();
    },
  );

  test(
    'one native subscription serves overlapping readers; final release drains',
    () async {
      final policy = ReadingEnergyPolicy();
      final cleanup = Completer<void>();
      var watches = 0;
      var cancellations = 0;
      final source = StreamController<Object?>(
        onCancel: () {
          cancellations++;
          return cleanup.future;
        },
      );
      final monitor = ReadingEnergyMonitor(
        policy: policy,
        watch: () {
          watches++;
          return source.stream;
        },
        onError: (error, stack) => fail('$error'),
      );
      final first = monitor.acquire();
      final second = monitor.acquire();
      expect(watches, 1);
      source.add({'thermal': 2, 'lowPower': false});
      await pumpEventQueue();
      expect(policy.deferAutomaticDownloads, true);
      await first();
      await first();
      expect(cancellations, 0);
      expect(policy.deferAutomaticDownloads, true);
      var drained = false;
      final closing = second().then((_) => drained = true);
      await pumpEventQueue();
      expect(cancellations, 1);
      expect(drained, false);
      expect(policy.deferAutomaticDownloads, false);
      cleanup.complete();
      await closing;
      await source.close();
      policy.dispose();
    },
  );
}
