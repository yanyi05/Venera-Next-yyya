import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/foundation/reading_activity.dart';

void main() {
  test(
    'background admission waits for every reader image; release is idempotent',
    () async {
      final gate = ReaderImagePriority();
      final first = gate.enter();
      final second = gate.enter();
      final stop = Completer<void>();
      var admitted = false;
      final waiting = gate
          .waitUntilIdle(stop.future)
          .then((value) => admitted = value);
      await pumpEventQueue();
      expect(admitted, isFalse);
      first();
      first();
      await pumpEventQueue();
      expect(admitted, isFalse);
      second();
      await waiting;
      expect(admitted, isTrue);
      stop.complete();
    },
  );

  test(
    'stopping a blocked download does not wait for reader completion',
    () async {
      final gate = ReaderImagePriority();
      final release = gate.enter();
      final stop = Completer<void>();
      final waiting = gate.waitUntilIdle(stop.future);
      stop.complete();
      expect(await waiting, isFalse);
      release();
    },
  );

  test(
    'new reader work before admission keeps the background blocked',
    () async {
      final gate = ReaderImagePriority();
      final release = gate.enter();
      final stop = Completer<void>();
      var admitted = false;
      final waiting = gate
          .waitUntilIdle(stop.future)
          .then((value) => admitted = value);
      release();
      final next = gate.enter();
      await pumpEventQueue();
      expect(admitted, isFalse);
      next();
      await waiting;
      expect(admitted, isTrue);
      stop.complete();
    },
  );
}
