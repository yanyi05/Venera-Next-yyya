import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/features/settings/window_hotkey_setting.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/foundation/context.dart';
import 'package:venera_next/foundation/translations.dart';
import 'package:venera_next/foundation/window_hotkey.dart';
import 'package:venera_next/foundation/window_hotkey_controller.dart';

import '../../support/window_hotkey_fixture.dart';

Widget _host(
  WindowHotkeyController controller, {
  double scale = 1,
  Brightness brightness = Brightness.light,
}) => MaterialApp(
  theme: ThemeData(brightness: brightness),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(
    body: SingleChildScrollView(
      child: WindowHotkeySetting(controller: controller),
    ),
  ),
);

Future<void> _combination(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool ctrl = true,
  bool alt = true,
}) async {
  if (ctrl) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (alt) await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  if (alt) await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  if (ctrl) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

void main() {
  setUp(() {
    final language = appdata.settings['language'];
    appdata.settings['language'] = 'en-US';
    registerShowMessageHandler((_, _) {});
    addTearDown(() => appdata.settings['language'] = language);
  });

  testWidgets(
    'default-off editor records keys, rejects invalid input and supports Tab/Escape',
    (tester) async {
      final native = FakeWindowHotkeyBackend();
      final controller = WindowHotkeyController(
        backend: native,
        load: () => const WindowHotkeyConfiguration(),
        persist: (_, _) async {},
      );
      await controller.start();
      addTearDown(() {
        unawaited(controller.close());
      });
      await tester.pumpWidget(_host(controller));
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(native.suspended, isTrue);
      expect(native.current, isNull);
      expect(native.pending, isNull);
      expect(find.text('Ctrl + Alt + H'), findsOneWidget);
      await _combination(tester, LogicalKeyboardKey.f12);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
            .onPressed,
        isNull,
      );
      await _combination(
        tester,
        LogicalKeyboardKey.keyJ,
        ctrl: false,
        alt: false,
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
            .onPressed,
        isNull,
      );
      await _combination(tester, LogicalKeyboardKey.f11);
      expect(find.text('Ctrl + Alt + F11'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        tester.widget<InputDecorator>(find.byType(InputDecorator)).isFocused,
        isFalse,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(native.suspended, isFalse);
      expect(controller.configuration.enabled, isFalse);
    },
  );

  testWidgets(
    'conflicting edit leaves original active after cancellation; successful edit, disable and clear persist',
    (tester) async {
      final native = FakeWindowHotkeyBackend();
      var saved = firstHotkeyConfig;
      final controller = WindowHotkeyController(
        backend: native,
        load: () => saved,
        persist: (next, _) async => saved = next,
      );
      await controller.start();
      addTearDown(() {
        unawaited(controller.close());
      });
      await tester.pumpWidget(_host(controller));
      await tester.tap(find.widgetWithText(TextButton, 'Set'));
      await tester.pumpAndSettle();
      await _combination(tester, LogicalKeyboardKey.keyJ);
      native.conflict = const WindowHotkey(modifiers: 3, keyCode: 0x4a);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(
            'This shortcut is already in use. Choose another one.',
          ),
        ),
        findsOneWidget,
      );
      expect(native.current, firstHotkey);
      expect(saved.toJson(), firstHotkeyConfig.toJson());
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(native.suspended, isFalse);
      native.conflict = null;
      await tester.tap(find.widgetWithText(TextButton, 'Set'));
      await tester.pumpAndSettle();
      await _combination(tester, LogicalKeyboardKey.keyJ);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(native.current?.keyCode, 0x4a);
      expect(native.suspended, isFalse);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(saved.enabled, isFalse);
      expect(saved.hotkey?.keyCode, 0x4a);
      expect(native.current, isNull);
      await tester.tap(find.widgetWithText(TextButton, 'Clear'));
      await tester.pumpAndSettle();
      expect(saved.hotkey, isNull);
      expect(find.text('Not set'), findsOneWidget);
    },
  );

  testWidgets(
    'save failure blocks leaving and retries captured shortcut without losing the original',
    (tester) async {
      final native = FakeWindowHotkeyBackend();
      var fail = true;
      final controller = WindowHotkeyController(
        backend: native,
        load: () => firstHotkeyConfig,
        persist: (_, _) async {
          if (fail) throw const WindowHotkeyFailure('hotkey_save_failed');
        },
      );
      await controller.start();
      addTearDown(() {
        unawaited(controller.close());
      });
      await tester.pumpWidget(_host(controller));
      await tester.tap(find.widgetWithText(TextButton, 'Set'));
      await tester.pumpAndSettle();
      await _combination(tester, LogicalKeyboardKey.keyJ);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);
      expect(native.current, firstHotkey);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(native.suspended, isTrue);
      fail = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(native.current?.keyCode, 0x4a);
      expect(native.suspended, isFalse);
    },
  );

  testWidgets(
    'pending save retains its route and native suspension until it completes',
    (tester) async {
      final native = FakeWindowHotkeyBackend();
      final gate = Completer<void>();
      final controller = WindowHotkeyController(
        backend: native,
        load: () => firstHotkeyConfig,
        persist: (_, _) => gate.future,
      );
      await controller.start();
      addTearDown(() {
        unawaited(controller.close());
      });
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      await tester.pumpWidget(_host(controller));
      await tester.tap(find.widgetWithText(TextButton, 'Set'));
      await tester.pumpAndSettle();
      await _combination(tester, LogicalKeyboardKey.keyJ);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pump();
      unawaited(
        Navigator.of(tester.element(find.byType(AlertDialog))).maybePop(),
      );
      await tester.pump();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(native.current, firstHotkey);
      expect(native.suspended, isTrue);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(native.current?.keyCode, 0x4a);
      expect(native.suspended, isFalse);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'Chinese narrow layout and recorder support large text in $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(500, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        appdata.settings['language'] = 'zh-CN';
        await AppTranslation.init();
        final native = FakeWindowHotkeyBackend();
        final controller = WindowHotkeyController(
          backend: native,
          load: () => firstHotkeyConfig,
          persist: (_, _) async {},
        );
        await controller.start();
        addTearDown(() {
          unawaited(controller.close());
        });
        await tester.pumpWidget(
          _host(controller, scale: 2, brightness: brightness),
        );
        await tester.tap(find.widgetWithText(TextButton, 'Set'.tl));
        await tester.pumpAndSettle();
        await _combination(tester, LogicalKeyboardKey.keyK);
        expect(find.text('Ctrl + Alt + K'), findsOneWidget);
        final semantics = tester.ensureSemantics();
        await tester.pump();
        expect(find.bySemanticsLabel('Press a shortcut here'.tl), findsWidgets);
        semantics.dispose();
        expect(tester.takeException(), isNull);
        await tester.tap(find.widgetWithText(TextButton, 'Cancel'.tl));
        await tester.pumpAndSettle();
        expect(native.suspended, isFalse);
      },
    );
  }
}
