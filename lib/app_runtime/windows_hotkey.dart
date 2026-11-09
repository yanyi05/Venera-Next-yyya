import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/foundation/log.dart';
import 'package:venera_next/foundation/window_hotkey.dart';
import 'package:venera_next/foundation/window_hotkey_controller.dart';

const windowHotkeySettingKey = 'windowsWindowHotkey';

WindowHotkeyHost createWindowsHotkeyHost() => WindowHotkeyHost(
  (ready) => WindowHotkeyController(
    backend: WindowsHotkeyBackend(),
    ready: ready,
    load: () => WindowHotkeyConfiguration.fromJson(
      appdata.settings[windowHotkeySettingKey],
    ),
    persist: (next, previous) async {
      final before = jsonDecode(
        jsonEncode(appdata.settings[windowHotkeySettingKey]),
      );
      try {
        await appdata.updateSettings((draft) {
          draft[windowHotkeySettingKey] = next.toJson();
        }, sync: false);
      } catch (error) {
        try {
          await appdata.restoreSettingsFields({windowHotkeySettingKey: before});
        } catch (rollback) {
          await appdata.restoreSettingsFields({
            windowHotkeySettingKey: before,
          }, persist: false);
          throw WindowHotkeyFailure('hotkey_save_failed', (error, rollback));
        }
        throw WindowHotkeyFailure('hotkey_save_failed', error);
      }
    },
    onError: (error, stack) => Log.error('Window hotkey', error, stack),
  ),
);

class WindowsHotkeyBackend implements WindowHotkeyBackend {
  WindowsHotkeyBackend({
    this.channel = const MethodChannel('venera/window_hotkey'),
  });
  final MethodChannel channel;

  Future<T?> _call<T>(String method, [Object? arguments]) async {
    try {
      return await channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (error) {
      throw WindowHotkeyFailure(error.code, error);
    }
  }

  @override
  Future<int> open() async => await _call<int>('open') ?? 0;
  @override
  Future<void> stage(int owner, WindowHotkey? hotkey) => _call<void>('stage', {
    'owner': owner,
    'modifiers': hotkey?.modifiers ?? 0,
    'keyCode': hotkey?.keyCode ?? 0,
  });
  @override
  Future<void> commit(int owner) => _call<void>('commit', {'owner': owner});
  @override
  Future<void> cancel(int owner) => _call<void>('cancel', {'owner': owner});
  @override
  Future<void> suspend(int owner, bool value) =>
      _call<void>('suspend', {'owner': owner, 'value': value});
  @override
  Future<void> close(int owner) => _call<void>('close', {'owner': owner});
}
