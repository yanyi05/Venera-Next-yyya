import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/foundation/window_hotkey.dart';
import 'package:venera_next/foundation/window_hotkey_controller.dart';

import '../support/window_hotkey_fixture.dart';

void main() {
  test('only supported Win32 combinations survive legacy JSON', () {
    for (final invalid in [
      null,
      'Ctrl+H',
      {},
      {'enabled': true},
    ]) {
      expect(WindowHotkeyConfiguration.fromJson(invalid).enabled, isFalse);
    }
    for (final modifiers in [0, 4, 8, 10, -1]) {
      expect(
        WindowHotkey(modifiers: modifiers, keyCode: 0x48).isValid,
        isFalse,
      );
    }
    for (final key in [0, 0x20, 0x40, 0x5b, 0x7b, 0x100]) {
      expect(WindowHotkey(modifiers: 2, keyCode: key).isValid, isFalse);
    }
    for (final key in [0x30, 0x39, 0x41, 0x5a, 0x70, 0x7a]) {
      expect(WindowHotkey(modifiers: 7, keyCode: key).isValid, isTrue);
    }
    expect(firstHotkey.label, 'Ctrl + Alt + H');
    expect(
      const WindowHotkey(modifiers: 5, keyCode: 0x7a).label,
      'Alt + Shift + F11',
    );
    expect(WindowHotkey.fromJson(firstHotkey.toJson()), firstHotkey);
    expect(
      WindowHotkeyConfiguration.fromJson(firstHotkeyConfig.toJson()).toJson(),
      firstHotkeyConfig.toJson(),
    );
  });

  test('default disabled startup does not reserve the suggestion', () async {
    final native = FakeWindowHotkeyBackend();
    final controller = WindowHotkeyController(
      backend: native,
      load: () => const WindowHotkeyConfiguration(),
      persist: (_, _) async {},
    );
    await controller.start();
    await controller.start();
    expect(native.calls, ['open', 'suspend:false']);
    expect(controller.configuration.enabled, isFalse);
    expect(controller.registered, isFalse);
    for (final invalid in [
      const WindowHotkeyConfiguration(enabled: true),
      const WindowHotkeyConfiguration(
        hotkey: WindowHotkey(modifiers: 8, keyCode: 72),
      ),
    ]) {
      await expectLater(
        controller.configure(invalid),
        throwsA(isA<WindowHotkeyFailure>()),
      );
    }
    expect(native.calls, ['open', 'suspend:false']);
    await controller.close();
  });

  test(
    'startup commit ambiguity unregisters all keys without rewriting the saved preference',
    () async {
      final native = FakeWindowHotkeyBackend()..loseCommitResponse = true;
      var writes = 0;
      final controller = WindowHotkeyController(
        backend: native,
        load: () => firstHotkeyConfig,
        persist: (_, _) async {
          writes++;
        },
      );
      await controller.start();
      expect(controller.error, isNotNull);
      expect(controller.configuration.enabled, isTrue);
      expect(controller.registered, isFalse);
      expect(native.current, isNull);
      expect(native.pending, isNull);
      expect(writes, 0);
      await controller.configure(firstHotkeyConfig);
      expect(native.current, firstHotkey);
      expect(controller.error, isNull);
      await controller.close();
    },
  );

  test(
    'candidate stays inactive until durable; conflicts keep the old key',
    () async {
      final native = FakeWindowHotkeyBackend();
      var saved = firstHotkeyConfig;
      final gate = Completer<void>();
      var writes = 0;
      final controller = WindowHotkeyController(
        backend: native,
        load: () => saved,
        persist: (next, _) async {
          writes++;
          await gate.future;
          saved = next;
        },
      );
      await controller.start();
      native.conflict = secondHotkey;
      await expectLater(
        controller.configure(secondHotkeyConfig),
        throwsA(
          isA<WindowHotkeyFailure>().having(
            (e) => e.code,
            'code',
            'hotkey_conflict',
          ),
        ),
      );
      expect(writes, 0);
      expect(native.current, firstHotkey);
      native.conflict = null;
      final changing = controller.configure(secondHotkeyConfig);
      await pumpEventQueue();
      expect(native.current, firstHotkey);
      expect(native.pending, secondHotkey);
      expect(native.suspended, isTrue);
      expect(controller.busy, isTrue);
      gate.complete();
      await changing;
      expect(native.current, secondHotkey);
      expect(native.suspended, isFalse);
      expect(saved.toJson(), secondHotkeyConfig.toJson());
      expect(controller.error, isNull);
      await controller.close();
    },
  );

  test(
    'failed persistence cancels reservation and retry can disable or clear',
    () async {
      final native = FakeWindowHotkeyBackend();
      var fail = true;
      var saved = firstHotkeyConfig;
      final controller = WindowHotkeyController(
        backend: native,
        load: () => saved,
        persist: (next, _) async {
          if (fail) throw const WindowHotkeyFailure('hotkey_save_failed');
          saved = next;
        },
      );
      await controller.start();
      await expectLater(
        controller.configure(secondHotkeyConfig),
        throwsA(isA<WindowHotkeyFailure>()),
      );
      expect(native.current, firstHotkey);
      expect(native.pending, isNull);
      expect(saved.toJson(), firstHotkeyConfig.toJson());
      fail = false;
      await controller.configure(
        const WindowHotkeyConfiguration(hotkey: firstHotkey),
      );
      expect(native.current, isNull);
      expect(controller.configuration.hotkey, firstHotkey);
      await controller.configure(const WindowHotkeyConfiguration());
      expect(controller.configuration.hotkey, isNull);
      expect(controller.registered, isFalse);
      await controller.close();
    },
  );

  test(
    'lost commit response restores the previous registration and preference',
    () async {
      final native = FakeWindowHotkeyBackend();
      var saved = firstHotkeyConfig;
      final controller = WindowHotkeyController(
        backend: native,
        load: () => saved,
        persist: (next, _) async => saved = next,
      );
      await controller.start();
      native.loseCommitResponse = true;
      await expectLater(
        controller.configure(secondHotkeyConfig),
        throwsA(isA<WindowHotkeyFailure>()),
      );
      expect(saved.toJson(), firstHotkeyConfig.toJson());
      expect(native.current, firstHotkey);
      expect(controller.registered, isTrue);
      await controller.close();
    },
  );

  test(
    'unrepairable native commit unregisters rather than keeping an unknown key',
    () async {
      final native = FakeWindowHotkeyBackend();
      var saved = firstHotkeyConfig;
      final controller = WindowHotkeyController(
        backend: native,
        load: () => saved,
        persist: (next, _) async => saved = next,
      );
      await controller.start();
      final release = await controller.hold();
      native.failCommit = true;
      await expectLater(
        controller.configure(secondHotkeyConfig),
        throwsA(
          isA<WindowHotkeyFailure>().having(
            (e) => e.code,
            'code',
            'hotkey_save_failed',
          ),
        ),
      );
      expect(saved.toJson(), firstHotkeyConfig.toJson());
      expect(native.current, isNull);
      expect(controller.registered, isFalse);
      native.failCommit = false;
      await controller.configure(firstHotkeyConfig);
      expect(native.current, firstHotkey);
      expect(native.suspended, isTrue);
      release();
      await pumpEventQueue();
      expect(native.suspended, isFalse);
      await controller.close();
    },
  );

  test(
    'recording and exit holds interrupt even a pending save and release independently',
    () async {
      final native = FakeWindowHotkeyBackend();
      final gate = Completer<void>();
      final controller = WindowHotkeyController(
        backend: native,
        load: () => firstHotkeyConfig,
        persist: (_, _) => gate.future,
      );
      await controller.start();
      final saving = controller.configure(secondHotkeyConfig);
      await pumpEventQueue();
      final recording = controller.hold();
      final exit = controller.hold();
      expect(native.suspended, isTrue);
      gate.complete();
      await saving;
      final releaseRecording = await recording;
      final releaseExit = await exit;
      releaseExit();
      releaseExit();
      await pumpEventQueue();
      expect(native.suspended, isTrue);
      releaseRecording();
      await pumpEventQueue();
      expect(native.suspended, isFalse);
      final held = await controller.hold();
      final close = controller.close();
      expect(identical(close, controller.close()), isTrue);
      held();
      await close;
      expect(native.current, isNull);
      expect(native.suspended, isTrue);
      await expectLater(controller.hold(), throwsStateError);
      await expectLater(
        controller.configure(firstHotkeyConfig),
        throwsStateError,
      );
    },
  );

  test('close during native open never enables a saved key', () async {
    final native = FakeWindowHotkeyBackend()..openGate = Completer<void>();
    final controller = WindowHotkeyController(
      backend: native,
      load: () => firstHotkeyConfig,
      persist: (_, _) async {},
    );
    final start = controller.start();
    await pumpEventQueue();
    final closing = controller.close();
    native.openGate!.complete();
    await Future.wait([start, closing]);
    expect(native.current, isNull);
    expect(native.calls.any((call) => call.startsWith('stage:')), isFalse);
    expect(native.suspended, isTrue);
  });

  test(
    'mount handoff drains accepted saves before replacement loads preferences',
    () async {
      final native = FakeWindowHotkeyBackend();
      final gate = Completer<void>();
      var saved = firstHotkeyConfig;
      var loads = 0;
      final host = WindowHotkeyHost(
        (ready) => WindowHotkeyController(
          backend: native,
          ready: ready,
          load: () {
            loads++;
            return saved;
          },
          persist: (next, _) async {
            await gate.future;
            saved = next;
          },
        ),
      );
      final first = host.attach();
      await first.start();
      final saving = first.configure(secondHotkeyConfig);
      await pumpEventQueue();
      final next = host.attach();
      final starting = next.start();
      expect(native.suspended, isTrue);
      await pumpEventQueue();
      expect(loads, 1);
      gate.complete();
      await Future.wait([saving, starting]);
      expect(loads, 2);
      expect(native.current, secondHotkey);
      await first.close();
      expect(native.current, secondHotkey);
      await next.close();
    },
  );

  test(
    'startup native failure is observable and a settings assignment retries',
    () async {
      final native = FakeWindowHotkeyBackend()..failOpen = true;
      final controller = WindowHotkeyController(
        backend: native,
        load: () => firstHotkeyConfig,
        persist: (_, _) async {},
      );
      await controller.start();
      expect(controller.initialized, isTrue);
      expect(controller.error, isNotNull);
      native.failOpen = false;
      await controller.configure(firstHotkeyConfig);
      expect(controller.error, isNull);
      expect(native.current, firstHotkey);
      await controller.close();
    },
  );
}
