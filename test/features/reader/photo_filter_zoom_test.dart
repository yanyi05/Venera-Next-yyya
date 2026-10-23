import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_view/photo_view.dart';

void main() {
  for (final quality in FilterQuality.values) {
    testWidgets(
      'custom-child filter $quality keeps fitted layout and zoom transform',
      (tester) async {
        final controller = PhotoViewController();
        var childSize = const Size(100, 100);
        Widget build() => MaterialApp(
          home: PhotoView.customChild(
            controller: controller,
            childSize: childSize,
            filterQuality: quality,
            minScale: PhotoViewComputedScale.contained,
            maxScale: PhotoViewComputedScale.covered * 10,
            child: const SizedBox.expand(
              child: ColoredBox(color: Colors.white),
            ),
          ),
        );
        try {
          await tester.pumpWidget(build());
          await tester.pump();
          final initial = controller.getInitialScale!()!;
          expect(initial, greaterThan(0));
          expect(controller.scale, closeTo(initial, .001));
          controller.scale = initial * 1.5;
          await tester.pumpAndSettle();
          final matrix = tester
              .widget<Transform>(
                find
                    .descendant(
                      of: find.byType(PhotoView),
                      matching: find.byType(Transform),
                    )
                    .first,
              )
              .transform;
          expect(matrix.storage[0], closeTo(initial * 1.5, .001));
          childSize = const Size(200, 200);
          await tester.pumpWidget(build());
          await tester.pump();
          expect(controller.getInitialScale!()!, closeTo(initial / 2, .001));
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
          controller.dispose();
        }
      },
    );
  }
}
