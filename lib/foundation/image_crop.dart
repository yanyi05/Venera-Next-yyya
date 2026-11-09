import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

class ReaderCrop {
  const ReaderCrop({
    this.mode = 'off',
    this.left = 0,
    this.top = 0,
    this.right = 0,
    this.bottom = 0,
  });
  final String mode;
  final double left, top, right, bottom;
  bool get enabled => mode == 'auto' || mode == 'manual';
  String get cacheKey => '$mode:$left:$top:$right:$bottom';
  Map<String, Object> toJson() => {
    'mode': mode,
    'left': left,
    'top': top,
    'right': right,
    'bottom': bottom,
  };
  factory ReaderCrop.fromJson(Object? value) {
    if (value is! Map) return const ReaderCrop();
    double margin(String key) {
      final raw = value[key];
      return raw is num && raw.isFinite ? raw.toDouble().clamp(0, .4) : 0;
    }

    return ReaderCrop(
      mode: const ['auto', 'manual'].contains(value['mode'])
          ? value['mode'] as String
          : 'off',
      left: margin('left'),
      top: margin('top'),
      right: margin('right'),
      bottom: margin('bottom'),
    );
  }
}

Future<Uint8List> cropReaderImage(Uint8List bytes, ReaderCrop crop) =>
    crop.enabled
    ? Isolate.run(() => cropReaderImageSync(bytes, crop))
    : Future.value(bytes);

Uint8List cropReaderImageSync(Uint8List bytes, ReaderCrop crop) {
  if (!crop.enabled) return bytes;
  final decoder = img.findDecoderForData(bytes);
  final info = decoder?.startDecode(bytes);
  // shortcut: bound extra decode memory and preserve animation; use a tiled
  // decoder before expanding cropping to very large strips or animated images.
  if (info == null ||
      info.width * info.height > 16000000 ||
      info.numFrames > 1) {
    return bytes;
  }
  final decoded = decoder!.decodeFrame(0);
  if (decoded == null) return bytes;
  final image =
      decoded.exif.imageIfd.hasOrientation &&
          decoded.exif.imageIfd.orientation != 1
      ? img.bakeOrientation(decoded)
      : decoded;
  var left = 0, top = 0, right = image.width, bottom = image.height;
  if (crop.mode == 'manual') {
    left = (image.width * crop.left).round();
    top = (image.height * crop.top).round();
    right -= (image.width * crop.right).round();
    bottom -= (image.height * crop.bottom).round();
  } else {
    var minX = image.width, minY = image.height, maxX = -1, maxY = -1;
    final white = image.maxChannelValue * (245 / 255);
    final transparent = image.maxChannelValue * (16 / 255);
    for (final pixel in image) {
      if (pixel.a > transparent &&
          (pixel.r < white || pixel.g < white || pixel.b < white)) {
        if (pixel.x < minX) minX = pixel.x;
        if (pixel.y < minY) minY = pixel.y;
        if (pixel.x > maxX) maxX = pixel.x;
        if (pixel.y > maxY) maxY = pixel.y;
      }
    }
    if (maxX < 0) {
      return bytes;
    }
    // Leave a small border around ink and never automatically trim over 20%.
    left = (minX - 2).clamp(0, (image.width * .2).floor());
    top = (minY - 2).clamp(0, (image.height * .2).floor());
    right = (maxX + 3).clamp((image.width * .8).ceil(), image.width);
    bottom = (maxY + 3).clamp((image.height * .8).ceil(), image.height);
  }
  if (right <= left ||
      bottom <= top ||
      (left == 0 &&
          top == 0 &&
          right == image.width &&
          bottom == image.height)) {
    return bytes;
  }
  return Uint8List.fromList(
    img.encodePng(
      img.copyCrop(
        image,
        x: left,
        y: top,
        width: right - left,
        height: bottom - top,
      ),
    ),
  );
}
