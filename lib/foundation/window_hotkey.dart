/// Windows virtual-key values are persisted, not Flutter key identifiers.
class WindowHotkey {
  const WindowHotkey({required this.modifiers, required this.keyCode});

  static const alt = 1;
  static const control = 2;
  static const shift = 4;
  static const suggested = WindowHotkey(
    modifiers: control | alt,
    keyCode: 0x48,
  );

  final int modifiers;
  final int keyCode;

  bool get isValid =>
      modifiers > 0 &&
      modifiers & ~7 == 0 &&
      modifiers & (control | alt) != 0 &&
      ((keyCode >= 0x30 && keyCode <= 0x39) ||
          (keyCode >= 0x41 && keyCode <= 0x5a) ||
          (keyCode >= 0x70 && keyCode <= 0x7a));

  String get label => [
    if (modifiers & control != 0) 'Ctrl',
    if (modifiers & alt != 0) 'Alt',
    if (modifiers & shift != 0) 'Shift',
    if (keyCode >= 0x70) 'F${keyCode - 0x6f}' else String.fromCharCode(keyCode),
  ].join(' + ');

  Map<String, int> toJson() => {'modifiers': modifiers, 'keyCode': keyCode};

  static WindowHotkey? fromJson(Object? value) {
    if (value is! Map ||
        value['modifiers'] is! int ||
        value['keyCode'] is! int) {
      return null;
    }
    final result = WindowHotkey(
      modifiers: value['modifiers'] as int,
      keyCode: value['keyCode'] as int,
    );
    return result.isValid ? result : null;
  }

  @override
  bool operator ==(Object other) =>
      other is WindowHotkey &&
      modifiers == other.modifiers &&
      keyCode == other.keyCode;

  @override
  int get hashCode => Object.hash(modifiers, keyCode);
}

class WindowHotkeyConfiguration {
  const WindowHotkeyConfiguration({this.enabled = false, this.hotkey});

  final bool enabled;
  final WindowHotkey? hotkey;

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'hotkey': hotkey?.toJson(),
  };

  static WindowHotkeyConfiguration fromJson(Object? value) {
    if (value is! Map) return const WindowHotkeyConfiguration();
    final hotkey = WindowHotkey.fromJson(value['hotkey']);
    return WindowHotkeyConfiguration(
      enabled: value['enabled'] == true && hotkey != null,
      hotkey: hotkey,
    );
  }
}

class WindowHotkeyFailure implements Exception {
  const WindowHotkeyFailure(this.code, [this.cause]);
  final String code;
  final Object? cause;

  String get message => switch (code) {
    'hotkey_conflict' => 'This shortcut is already in use. Choose another one.',
    'invalid_hotkey' => 'Use Ctrl or Alt with a letter, number or F1-F11.',
    'hotkey_save_failed' =>
      'Could not save the shortcut. Retry before leaving.',
    _ =>
      'The global shortcut is unavailable. Re-enable it or choose another shortcut in settings.',
  };

  @override
  String toString() => message;
}

abstract interface class WindowHotkeyBackend {
  Future<int> open();
  Future<void> stage(int owner, WindowHotkey? hotkey);
  Future<void> commit(int owner);
  Future<void> cancel(int owner);
  Future<void> suspend(int owner, bool value);
  Future<void> close(int owner);
}
