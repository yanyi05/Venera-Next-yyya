import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/foundation/image_crop_bands.dart';

void main() {
  test('merges overlaps and sorts in original coordinates', () {
    expect(
      normalizeImageCropBands([
        {'top': .8, 'bottom': .9},
        {'top': .05, 'bottom': .15},
        {'top': .1, 'bottom': .2},
      ]),
      [(top: .05, bottom: .2), (top: .8, bottom: .9)],
    );
    expect(
      retainedImageRows([
        {'top': 0, 'bottom': .1},
        {'top': .4, 'bottom': .5},
        {'top': .9, 'bottom': 1},
      ], 100),
      [(top: 10, bottom: 40), (top: 50, bottom: 90)],
    );
  });

  test('rejects unsafe input instead of partially applying it', () {
    for (final input in <Object?>[
      null,
      {},
      [null],
      [
        {'top': double.nan, 'bottom': .1},
      ],
      [
        {'top': -.1, 'bottom': .1},
      ],
      [
        {'top': .5, 'bottom': .4},
      ],
      [
        {'top': 0, 'bottom': .31},
      ],
      [
        {'top': 0, 'bottom': .2},
        {'top': .6, 'bottom': .8},
      ],
      List.filled(33, {'top': 0, 'bottom': .1}),
    ]) {
      expect(() => normalizeImageCropBands(input), throwsFormatException);
    }
  });
}
