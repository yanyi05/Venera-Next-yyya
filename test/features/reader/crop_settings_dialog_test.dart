import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/features/reader/crop_settings_dialog.dart';
import 'package:venera_next/foundation/image_crop.dart';

void main() {
  testWidgets(
    'crop controls fit a narrow screen with large text and return a reversible setting',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      ReaderCrop? selected;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  selected = await showDialog<ReaderCrop>(
                    context: context,
                    builder: (_) => const ReaderCropDialog(
                      initial: ReaderCrop(mode: 'manual', left: .1),
                    ),
                  );
                },
                child: const Text('打开裁剪'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开裁剪'));
      await tester.pumpAndSettle();
      expect(find.byType(Slider), findsNWidgets(4));
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('应用'));
      await tester.pumpAndSettle();
      expect(selected?.mode, 'manual');
      expect(selected?.left, .1);
      expect(tester.takeException(), isNull);
    },
  );
}
