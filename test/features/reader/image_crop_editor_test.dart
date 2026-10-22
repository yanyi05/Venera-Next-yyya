import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:venera_next/features/reader/reader_image_banner_crop_editor.dart';

void main() {
  late Uint8List bytes;
  setUp(
    () => bytes = Uint8List.fromList(
      img.encodePng(img.Image(width: 40, height: 100)),
    ),
  );

  Future<void> open(
    WidgetTester tester,
    ValueChanged<ReaderImageBannerCropEdit?> result,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => result(
                await showDialog<ReaderImageBannerCropEdit>(
                  context: context,
                  builder: (_) => ReaderImageBannerCropEditor(
                    bytes: bytes,
                    initialBands: const [Rect.fromLTRB(0, .1, 1, .2)],
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    for (
      var i = 0;
      i < 100 && find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpAndSettle();
  }

  testWidgets('preview preserves selection and applies normalized bands', (
    tester,
  ) async {
    ReaderImageBannerCropEdit? result;
    await open(tester, (value) => result = value);
    await tester.tap(find.text('裁切预览'));
    await tester.pump();
    expect(find.text('返回原图'), findsOneWidget);
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    expect(result?.bands, const [Rect.fromLTRB(0, .1, 1, .2)]);
    expect(tester.takeException(), isNull);
  });

  for (final action in ['恢复原图', '使用源处理']) {
    testWidgets('$action has a distinct persisted override', (tester) async {
      ReaderImageBannerCropEdit? result;
      await open(tester, (value) => result = value);
      await tester.tap(find.text(action));
      await tester.pumpAndSettle();
      expect(result, isNotNull);
      expect(result!.bands, action == '恢复原图' ? isEmpty : isNull);
      expect(tester.takeException(), isNull);
    });
  }
}
