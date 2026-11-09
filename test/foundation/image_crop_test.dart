import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:venera_next/foundation/image_crop.dart';

void main() {
  Uint8List page() {
    final image = img.Image(width: 100, height: 120);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    img.fillRect(
      image,
      x1: 15,
      y1: 15,
      x2: 84,
      y2: 104,
      color: img.ColorRgb8(0, 0, 0),
    );
    return Uint8List.fromList(img.encodePng(image));
  }

  test(
    'auto removes white borders with padding and preserves every ink pixel',
    () {
      final original = page(), before = Uint8List.fromList(page());
      final result = img.decodePng(
        cropReaderImageSync(original, const ReaderCrop(mode: 'auto')),
      )!;
      expect(result.width, 74);
      expect(result.height, 94);
      var dark = 0;
      for (final pixel in result) {
        if (pixel.r == 0) dark++;
      }
      expect(dark, 70 * 90);
      expect(original, before);
    },
  );
  test('manual crops each side and off returns original bytes', () {
    final original = page();
    final result = img.decodePng(
      cropReaderImageSync(
        original,
        const ReaderCrop(
          mode: 'manual',
          left: .1,
          right: .1,
          top: .1,
          bottom: .1,
        ),
      ),
    )!;
    expect((result.width, result.height), (80, 96));
    expect(
      identical(cropReaderImageSync(original, const ReaderCrop()), original),
      isTrue,
    );
  });
  test('blank pages remain complete; malformed settings normalize safely', () {
    final blank = img.Image(width: 20, height: 30);
    img.fill(blank, color: img.ColorRgb8(255, 255, 255));
    final bytes = Uint8List.fromList(img.encodePng(blank));
    expect(cropReaderImageSync(bytes, const ReaderCrop(mode: 'auto')), bytes);
    final crop = ReaderCrop.fromJson({
      'mode': 'manual',
      'left': double.nan,
      'right': 9,
      'top': -5,
    });
    expect((crop.left, crop.right, crop.top), (0, .4, 0));
    expect(ReaderCrop.fromJson({'mode': 'unknown'}).enabled, isFalse);
  });
  test('isolate output matches synchronous crop', () async {
    final bytes = page();
    expect(
      await cropReaderImage(bytes, const ReaderCrop(mode: 'auto')),
      cropReaderImageSync(bytes, const ReaderCrop(mode: 'auto')),
    );
  });
  test('manual cropping respects JPEG display orientation', () {
    final image = img.Image(width: 100, height: 60);
    img.fill(image, color: img.ColorRgb8(50, 60, 70));
    image.exif.imageIfd.orientation = 6;
    final bytes = Uint8List.fromList(img.encodeJpg(image));
    final cropped = img.decodePng(
      cropReaderImageSync(bytes, const ReaderCrop(mode: 'manual', left: .1)),
    )!;
    expect((cropped.width, cropped.height), (54, 100));
  });
}
