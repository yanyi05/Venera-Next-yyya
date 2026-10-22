import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/foundation/image_processing.dart' as processing;

List<int> pixels(processing.Image image) => [
  for (var i = 0; i < image.width * image.height; i++)
    image.getPixelAtIndex(i).value,
];

void main() {
  test(
    'copies full rows and partial rectangles without changing neighbors',
    () {
      final source = processing.Image(
        Uint32List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]),
        4,
        3,
      );
      expect(pixels(source.copyRange(1, 1, 2, 2)), [6, 7, 10, 11]);
      expect(pixels(source.copyRange(0, 1, 4, 2)), [5, 6, 7, 8, 9, 10, 11, 12]);
      final whole = processing.Image.empty(4, 4);
      whole.fillImageAt(0, 1, source);
      expect(pixels(whole), [
        0,
        0,
        0,
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        9,
        10,
        11,
        12,
      ]);
      final target = processing.Image.empty(5, 4);
      target.fillImageAt(2, 1, source.copyRange(1, 1, 2, 2));
      expect(pixels(target), [
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        6,
        7,
        0,
        0,
        0,
        10,
        11,
        0,
        0,
        0,
        0,
        0,
        0,
      ]);
      target.fillImageRangeAt(0, 3, source, 1, 0, 3, 1);
      expect(pixels(target).sublist(15), [2, 3, 4, 0, 0]);
    },
  );

  test('aliased self-copies retain sequential script behavior', () {
    final image = processing.Image(Uint32List.fromList([1, 2, 3, 4]), 4, 1);
    image.fillImageRangeAt(1, 0, image, 0, 0, 3, 1);
    expect(pixels(image), [1, 1, 1, 1]);
  });

  test('overlapping typed views retain sequential script behavior', () {
    final data = Uint32List.fromList([1, 2, 3, 4, 5]);
    final source = processing.Image(Uint32List.sublistView(data, 0, 4), 4, 1);
    final target = processing.Image(Uint32List.sublistView(data, 1, 5), 4, 1);
    target.fillImageAt(0, 0, source);
    expect(data, [1, 1, 1, 1, 1]);
  });

  test('rotation preserves pixel order on rectangular images', () {
    final source = processing.Image(
      Uint32List.fromList([1, 2, 3, 4, 5, 6]),
      2,
      3,
    );
    final rotated = source.copyAndRotate90();
    expect((rotated.width, rotated.height), (3, 2));
    expect(pixels(rotated), [5, 3, 1, 6, 4, 2]);
  });

  test('native source image operation removes multiple bands losslessly', () {
    final source = processing.Image(
      Uint32List.fromList(List.generate(100, (i) => i)),
      1,
      100,
    );
    final output = source.removeHorizontalBands([
      {'top': .1, 'bottom': .2},
      {'top': .8, 'bottom': .9},
    ]);
    expect(output.height, 80);
    expect(pixels(output), [
      for (var i = 0; i < 100; i++)
        if (!(i >= 10 && i < 20) && !(i >= 80 && i < 90)) i,
    ]);
    expect(pixels(source), List.generate(100, (i) => i));
  });

  test('out of bounds rectangles fail without writing the destination', () {
    final target = processing.Image.empty(3, 3);
    final source = processing.Image.empty(2, 2);
    expect(() => target.fillImageAt(2, 2, source), throwsArgumentError);
    expect(
      () => target.fillImageRangeAt(0, 0, source, 1, 1, 2, 2),
      throwsArgumentError,
    );
    expect(pixels(target), List.filled(9, 0));
    expect(() => source.copyRange(-1, 0, 1, 1), throwsRangeError);
  });
}
