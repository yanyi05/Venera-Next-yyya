import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/app_runtime/interactive_bindings.dart';
import 'package:venera_next/foundation/window_hotkey_controller.dart';

import '../support/window_hotkey_fixture.dart';

void main() {
  test(
    'Windows mount owns hotkeys; exit cancellation resumes without stopping downloads',
    () async {
      final native = FakeWindowHotkeyBackend();
      final hotkeys = WindowHotkeyController(
        backend: native,
        load: () => firstHotkeyConfig,
        persist: (_, _) async {},
      );
      var downloadsClosed = 0;
      final runtime = InteractiveBindings(
        android: false,
        windows: true,
        links: () => throw StateError('unused'),
        shares: () => throw StateError('unused'),
        heartbeat: () async {},
        windowHotkey: hotkeys,
        closeDownloads: () async {
          downloadsClosed++;
        },
      )..start();
      await hotkeys.start();
      expect(native.current, firstHotkey);
      final release = await runtime.prepareForExit();
      expect(native.suspended, isTrue);
      expect(downloadsClosed, 0);
      release();
      await pumpEventQueue();
      expect(native.suspended, isFalse);
      expect(downloadsClosed, 0);
      await runtime.dispose();
      expect(native.current, isNull);
      expect(downloadsClosed, 1);
    },
  );

  test(
    'non-Windows interactive mount never opens a native hotkey owner',
    () async {
      final native = FakeWindowHotkeyBackend();
      final hotkeys = WindowHotkeyController(
        backend: native,
        load: () => firstHotkeyConfig,
        persist: (_, _) async {},
      );
      final runtime = InteractiveBindings(
        android: false,
        windows: false,
        links: () => throw StateError('unused'),
        shares: () => throw StateError('unused'),
        heartbeat: () async {},
        windowHotkey: hotkeys,
      )..start();
      await pumpEventQueue();
      expect(native.opens, 0);
      await runtime.dispose();
      expect(native.calls, isEmpty);
    },
  );
}
