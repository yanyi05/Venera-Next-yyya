import 'package:flutter/widgets.dart';
import 'package:venera_next/foundation/window_hotkey_controller.dart';

class WindowHotkeyScope extends InheritedWidget {
  const WindowHotkeyScope({
    super.key,
    required this.controller,
    required super.child,
  });
  final WindowHotkeyController controller;

  static WindowHotkeyController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<WindowHotkeyScope>()
      ?.controller;

  @override
  bool updateShouldNotify(WindowHotkeyScope oldWidget) =>
      controller != oldWidget.controller;
}
