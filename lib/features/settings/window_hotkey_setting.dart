import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:venera_next/components/settings_save_state.dart';
import 'package:venera_next/foundation/translations.dart';
import 'package:venera_next/foundation/window_hotkey.dart';
import 'package:venera_next/foundation/window_hotkey_controller.dart';

class WindowHotkeySetting extends StatefulWidget {
  const WindowHotkeySetting({super.key, required this.controller});
  final WindowHotkeyController controller;

  @override
  State<WindowHotkeySetting> createState() => _WindowHotkeySettingState();
}

abstract class _HotkeySaveState<W extends StatefulWidget>
    extends SettingsSaveState<W> {
  String? errorText;

  Future<void> assign(
    WindowHotkeyController controller,
    WindowHotkeyConfiguration next, {
    VoidCallback? onSaved,
  }) async {
    if (!acceptsSettingsChanges || savingSettings || hasSettingsSaveError) {
      return;
    }
    setState(() => errorText = null);
    var applied = false;
    await saveSetting(
      controller,
      () async {
        try {
          await controller.configure(next);
          applied = true;
          if (mounted) setState(() => errorText = null);
        } on WindowHotkeyFailure catch (error) {
          if (mounted) setState(() => errorText = error.message.tl);
          if (error.code == 'hotkey_save_failed') rethrow;
        }
      },
      onSaved: () {
        if (applied) onSaved?.call();
      },
    );
  }

  Widget errorLabel(String? message) => message == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Semantics(
            liveRegion: true,
            child: Text(
              message,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        );
}

class _WindowHotkeySettingState extends _HotkeySaveState<WindowHotkeySetting> {
  bool _editing = false;

  Future<void> _edit({bool? enabled}) async {
    if (_editing ||
        !acceptsSettingsChanges ||
        savingSettings ||
        hasSettingsSaveError) {
      return;
    }
    setState(() => _editing = true);
    final controller = widget.controller;
    void Function()? release;
    try {
      release = await controller.hold();
      if (!mounted || !acceptsSettingsChanges || controller.isClosed) return;
      await showDialog<void>(
        context: context,
        builder: (_) => _HotkeyDialog(
          controller: controller,
          enabled: enabled ?? controller.configuration.enabled,
        ),
      );
    } on WindowHotkeyFailure catch (error) {
      if (mounted) setState(() => errorText = error.message.tl);
    } finally {
      release?.call();
      if (mounted) setState(() => _editing = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final config = controller.configuration;
      final enabled =
          controller.initialized &&
          !controller.isClosed &&
          !controller.busy &&
          !_editing &&
          !savingSettings &&
          !hasSettingsSaveError &&
          acceptsSettingsChanges;
      return protectSettings(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              title: Text('Global hide/restore shortcut'.tl),
              subtitle: Text(
                'Windows only. Stored on this device. Hidden is not exited.'.tl,
              ),
              value: config.enabled,
              onChanged: enabled
                  ? (value) {
                      if (value && config.hotkey == null) {
                        _edit(enabled: true);
                      } else {
                        assign(
                          controller,
                          WindowHotkeyConfiguration(
                            enabled: value,
                            hotkey: config.hotkey,
                          ),
                        );
                      }
                    }
                  : null,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                children: [
                  Text(config.hotkey?.label ?? 'Not set'.tl),
                  TextButton(
                    onPressed: enabled ? _edit : null,
                    child: Text('Set'.tl),
                  ),
                  if (config.hotkey != null)
                    TextButton(
                      onPressed: enabled
                          ? () => assign(
                              controller,
                              const WindowHotkeyConfiguration(),
                            )
                          : null,
                      child: Text('Clear'.tl),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Only the main window is hidden, not other windows. This is not privacy protection. If hidden, launch VeneraNext again to restore its window.'
                    .tl,
              ),
            ),
            errorLabel(errorText ?? controller.error?.message.tl),
            if (savingSettings || hasSettingsSaveError) settingsSaveStatus,
          ],
        ),
      );
    },
  );
}

class _HotkeyDialog extends StatefulWidget {
  const _HotkeyDialog({required this.controller, required this.enabled});
  final WindowHotkeyController controller;
  final bool enabled;
  @override
  State<_HotkeyDialog> createState() => _HotkeyDialogState();
}

class _HotkeyDialogState extends _HotkeySaveState<_HotkeyDialog> {
  late WindowHotkey _hotkey =
      widget.controller.configuration.hotkey ?? WindowHotkey.suggested;
  late bool _enabled = widget.enabled;
  bool _valid = true;
  final _focus = FocusNode(debugLabel: 'record window hotkey');

  KeyEventResult _record(FocusNode node, KeyEvent event) {
    if (event is KeyRepeatEvent) return KeyEventResult.handled;
    if (event is! KeyDownEvent || savingSettings || hasSettingsSaveError) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.tab || key == LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }
    const modifiers = [
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.controlRight,
      LogicalKeyboardKey.altLeft,
      LogicalKeyboardKey.altRight,
      LogicalKeyboardKey.shiftLeft,
      LogicalKeyboardKey.shiftRight,
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.metaRight,
    ];
    if (modifiers.contains(key)) return KeyEventResult.handled;
    final keyboard = HardwareKeyboard.instance;
    final label = key.keyLabel.toUpperCase();
    final function = RegExp(r'^F([1-9]|1[01])$').firstMatch(label);
    final code = function != null
        ? 0x6f + int.parse(function.group(1)!)
        : RegExp(r'^[A-Z0-9]$').hasMatch(label)
        ? label.codeUnitAt(0)
        : 0;
    final hotkey = WindowHotkey(
      modifiers:
          (keyboard.isControlPressed ? WindowHotkey.control : 0) |
          (keyboard.isAltPressed ? WindowHotkey.alt : 0) |
          (keyboard.isShiftPressed ? WindowHotkey.shift : 0),
      keyCode: code,
    );
    setState(() {
      if (!keyboard.isMetaPressed && hotkey.isValid) {
        _hotkey = hotkey;
        _valid = true;
        errorText = null;
      } else {
        _valid = false;
        errorText = const WindowHotkeyFailure('invalid_hotkey').message.tl;
      }
    });
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final enabled =
        acceptsSettingsChanges && !savingSettings && !hasSettingsSaveError;
    return protectSettings(
      AlertDialog(
        title: Text('Set global shortcut'.tl),
        scrollable: true,
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Use Ctrl or Alt with a letter, number or F1-F11.'.tl),
              const SizedBox(height: 12),
              Focus(
                focusNode: _focus,
                autofocus: true,
                onFocusChange: (_) => setState(() {}),
                onKeyEvent: _record,
                child: Semantics(
                  label: 'Press a shortcut here'.tl,
                  value: _hotkey.label,
                  button: true,
                  excludeSemantics: true,
                  enabled: enabled,
                  focusable: true,
                  focused: _focus.hasFocus,
                  onTap: enabled ? _focus.requestFocus : null,
                  child: InkWell(
                    canRequestFocus: false,
                    onTap: enabled ? _focus.requestFocus : null,
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Press a shortcut here'.tl,
                        border: const OutlineInputBorder(),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: Theme.of(context).colorScheme.primary,
                            width: 2,
                          ),
                        ),
                      ),
                      isFocused: _focus.hasFocus,
                      child: Text(_hotkey.label),
                    ),
                  ),
                ),
              ),
              TextButton(
                onPressed: enabled
                    ? () => setState(() {
                        _hotkey = WindowHotkey.suggested;
                        _valid = true;
                        errorText = null;
                      })
                    : null,
                child: Text('Use Ctrl + Alt + H'.tl),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Enable after saving'.tl),
                value: _enabled,
                onChanged: enabled
                    ? (value) => setState(() => _enabled = value)
                    : null,
              ),
              errorLabel(errorText),
              if (savingSettings || hasSettingsSaveError) settingsSaveStatus,
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: savingSettings ? null : () => leaveSettings(),
            child: Text('Cancel'.tl),
          ),
          FilledButton(
            onPressed: enabled && _valid
                ? () => assign(
                    widget.controller,
                    WindowHotkeyConfiguration(
                      enabled: _enabled,
                      hotkey: _hotkey,
                    ),
                    onSaved: () => leaveSettings(),
                  )
                : null,
            child: Text('Save'.tl),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }
}
