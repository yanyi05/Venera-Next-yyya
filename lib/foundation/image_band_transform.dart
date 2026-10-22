import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:venera_next/foundation/image_crop_bands.dart';

Future<Uint8List> cropImageBannerBand(Uint8List bytes, Rect band) =>
    cropImageBannerBands(bytes, [band]);

/// Invalid, animated or unsupported input is preserved, never partially cut.
Future<Uint8List> cropImageBannerBands(Uint8List bytes, List<Rect> bands) =>
    compute(_crop, (
      bytes,
      [
        for (final b in bands) {'top': b.top, 'bottom': b.bottom},
      ],
    ));

Uint8List _crop((Uint8List, List<Map<String, double>>) input) {
  final (bytes, bands) = input;
  if (bands.isEmpty) return bytes;
  try {
    normalizeImageCropBands(bands);
    final decoded = img.decodeImage(bytes);
    if (decoded == null ||
        decoded.numFrames != 1 ||
        decoded.width * decoded.height > 12000000) {
      return bytes;
    }
    final rows = retainedImageRows(bands, decoded.height);
    final height = rows.fold<int>(0, (sum, row) => sum + row.bottom - row.top);
    if (height < 1 || height == decoded.height) return bytes;
    final result = img.Image(
      width: decoded.width,
      height: height,
      numChannels: 4,
    );
    var destination = 0;
    for (final row in rows) {
      final part = img.copyCrop(
        decoded,
        x: 0,
        y: row.top,
        width: decoded.width,
        height: row.bottom - row.top,
      );
      img.compositeImage(
        result,
        part,
        dstY: destination,
        blend: img.BlendMode.direct,
      );
      destination += part.height;
    }
    return Uint8List.fromList(img.encodePng(result));
  } catch (_) {
    return bytes;
  }
}
