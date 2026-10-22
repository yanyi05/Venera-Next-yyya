import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:venera_next/features/reader/image_banner_crop.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Uint8List fixture() {
    final image = img.Image(width: 10, height: 100);
    for (var y = 0; y < 100; y++) {
      for (var x = 0; x < 10; x++) {
        image.setPixelRgb(x, y, y, 0, 0);
      }
    }
    return Uint8List.fromList(img.encodePng(image));
  }

  for (final band in [
    const Rect.fromLTRB(0, 0, 1, .2),
    const Rect.fromLTRB(0, .4, 1, .6),
    const Rect.fromLTRB(0, .8, 1, 1),
  ]) {
    test('joins remaining rows after removing $band', () async {
      final bytes = fixture();
      final before = Uint8List.fromList(bytes);
      final output = img.decodePng(await cropImageBannerBand(bytes, band))!;
      expect(output.height, 80);
      expect(output.width, 10);
      for (var y = 0; y < 80; y++) {
        final expectedRow = y < (band.top * 100).round() ? y : y + 20;
        expect(output.getPixel(0, y).r, expectedRow);
      }
      expect(bytes, orderedEquals(before));
    });
  }

  test(
    'multiple overlapping bands are removed once in original coordinates',
    () async {
      final output = img.decodePng(
        await cropImageBannerBands(fixture(), [
          const Rect.fromLTRB(0, .05, 1, .15),
          const Rect.fromLTRB(0, .1, 1, .2),
          const Rect.fromLTRB(0, .8, 1, .9),
        ]),
      )!;
      expect(output.height, 75);
      final retained = [
        for (var y = 0; y < 100; y++)
          if (!(y >= 5 && y < 20) && !(y >= 80 && y < 90)) y,
      ];
      for (var y = 0; y < retained.length; y++) {
        expect(output.getPixel(0, y).r, retained[y]);
      }
    },
  );

  test('invalid or excessive bands preserve input', () async {
    final bytes = fixture();
    for (final band in [
      Rect.zero,
      const Rect.fromLTRB(0, 0, 1, .5),
      const Rect.fromLTRB(0, .6, 1, .4),
      const Rect.fromLTRB(0, double.nan, 1, .4),
    ]) {
      expect(await cropImageBannerBand(bytes, band), orderedEquals(bytes));
    }
  });
}
