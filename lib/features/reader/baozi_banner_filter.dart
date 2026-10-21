import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Removes a high-confidence, full-width Baozi promotional strip from a page.
/// Unknown formats, oversized images, and uncertain matches are returned as-is.
Future<Uint8List> removeBaoziBanner(Uint8List bytes) =>
    compute(_removeBaoziBanner, bytes);

Uint8List _removeBaoziBanner(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null || decoded.numFrames != 1) return bytes;
    final width = decoded.width;
    final height = decoded.height;
    if (width < 400 || height < 600 || width * height > 12 * 1000 * 1000) {
      return bytes;
    }

    // A full-width white band plus Baozi's centered yellow logo and dark text
    // is required. White gutters and speech bubbles alone are not enough.
    final xStep = (width / 360).ceil().clamp(1, 8).toInt();
    final goodRows = List<bool>.filled(height, false);
    for (var y = 0; y < height; y++) {
      var white = 0;
      var samples = 0;
      for (var x = 0; x < width; x += xStep) {
        final p = decoded.getPixel(x, y);
        if (p.r > 232 && p.g > 232 && p.b > 232) white++;
        samples++;
      }
      // Text and the logo interrupt some scanlines, so allow roughly half
      // the row to be non-white while still requiring a mostly white banner.
      goodRows[y] = samples > 0 && white / samples >= 0.52;
    }

    var start = 0;
    while (start < height) {
      if (!goodRows[start]) {
        start++;
        continue;
      }
      var end = start + 1;
      while (end < height && goodRows[end]) end++;
      final bandHeight = end - start;
      final minBand = (height * 0.025).round();
      final maxBand = (height * 0.20).round();
      if (bandHeight >= minBand && bandHeight <= maxBand &&
          _hasBaoziLogoAndText(decoded, start, end, xStep)) {
        final topHeight = start;
        final bottomHeight = height - end;
        if (topHeight < height * 0.12 || bottomHeight < height * 0.12) {
          start = end;
          continue;
        }
        final result = img.Image(width: width, height: height - bandHeight);
        final top = img.copyCrop(
          decoded,
          x: 0,
          y: 0,
          width: width,
          height: topHeight,
        );
        final bottom = img.copyCrop(
          decoded,
          x: 0,
          y: end,
          width: width,
          height: bottomHeight,
        );
        img.compositeImage(result, top, dstX: 0, dstY: 0);
        img.compositeImage(result, bottom, dstX: 0, dstY: topHeight);
        return Uint8List.fromList(img.encodeJpg(result, quality: 94));
      }
      start = end;
    }
    return bytes;
  } catch (_) {
    // Image decoding/cropping must never break the reader.
    return bytes;
  }
}

bool _hasBaoziLogoAndText(img.Image image, int top, int bottom, int step) {
  final width = image.width;
  final height = bottom - top;
  final left = (width * 0.32).round();
  final right = (width * 0.68).round();
  var yellow = 0;
  var dark = 0;
  var samples = 0;
  var minYellowX = width;
  var maxYellowX = -1;
  var minYellowY = bottom;
  var maxYellowY = top - 1;
  for (var y = top; y < bottom; y += step) {
    for (var x = left; x < right; x += step) {
      final p = image.getPixel(x, y);
      if (x > width * 0.36 &&
          x < width * 0.56 &&
          p.r > 175 &&
          p.g > 125 &&
          p.b < 115 &&
          p.r > p.g * 1.15) {
        yellow++;
        if (x < minYellowX) minYellowX = x;
        if (x > maxYellowX) maxYellowX = x;
        if (y < minYellowY) minYellowY = y;
        if (y > maxYellowY) maxYellowY = y;
      }
      if (p.r < 90 && p.g < 90 && p.b < 90) dark++;
      samples++;
    }
  }
  if (samples == 0 || yellow < (samples * 0.0015).ceil().clamp(12, 100000)) {
    return false;
  }
  final logoWidth = maxYellowX - minYellowX + 1;
  final logoHeight = maxYellowY - minYellowY + 1;
  final logoCenterX = (minYellowX + maxYellowX) / 2;
  final logoAspect = logoWidth / logoHeight;
  final isBaoziLogoShape =
      logoCenterX > width * 0.37 &&
      logoCenterX < width * 0.53 &&
      logoWidth > width * 0.025 &&
      logoWidth < width * 0.12 &&
      logoHeight > height * 0.15 &&
      logoHeight < height * 0.9 &&
      logoAspect > 0.55 &&
      logoAspect < 1.8;
  return isBaoziLogoShape && dark >= (samples * 0.012).ceil();
}

bool isBaoziComicImage(String imageKey) {
  final uri = Uri.tryParse(imageKey);
  if (uri == null || !uri.hasAuthority) return false;
  final host = uri.host.toLowerCase();
  return host == 'baozimh.com' ||
      host.endsWith('.baozimh.com') ||
      host == 'baozicdn.com' ||
      host.endsWith('.baozicdn.com') ||
      host == 'bzcdn.net' ||
      host.endsWith('.bzcdn.net');
}
