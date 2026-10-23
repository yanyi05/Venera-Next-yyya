import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/features/settings/interface_customization.dart';
import 'package:venera_next/foundation/interface_customization.dart';
import 'package:venera_next/foundation/appdata.dart';

void main() {
  testWidgets(
    'mobile editor previews without persisting, and restores its draft',
    (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final initial = appdata.settings[InterfaceCustomization.storageKey];
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
            child: const InterfaceCustomizationSettings(),
          ),
        ),
      );
      expect(find.text('界面与按钮'), findsOneWidget);
      await tester.tap(find.byType(Switch).first);
      await tester.pump();
      expect(tester.widget<Switch>(find.byType(Switch).first).value, isFalse);
      expect(appdata.settings[InterfaceCustomization.storageKey], initial);
      final button = find.text('恢复本页默认布局');
      await tester.scrollUntilVisible(
        button,
        500,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(button);
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('收藏图片'),
        -500,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.widget<Switch>(find.byType(Switch).first).value, isTrue);
      expect(appdata.settings[InterfaceCustomization.storageKey], initial);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
