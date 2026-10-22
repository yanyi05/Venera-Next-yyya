import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Removes a high-confidence, full-width Baozi promotional strip from a page.
/// Unknown formats, oversized images, and uncertain matches are returned as-is.
Future<Uint8List> removeBaoziBanner(Uint8List bytes) =>
    compute(_removeBaoziBanner, bytes);

/// Finds the suspected banner band in normalized image coordinates without
/// modifying the supplied image.
Future<Rect?> detectBaoziBanner(Uint8List bytes) async {
  final result = await compute(_findBaoziBannerBand, bytes);
  if (result == null || result[2] <= 0) return null;
  return Rect.fromLTRB(0, result[0] / result[2], 1, result[1] / result[2]);
}

/// Removes a manually selected full-width horizontal band and joins the
/// remaining top and bottom portions.
Future<Uint8List> cropBaoziBannerBand(Uint8List bytes, Rect band) =>
    compute(_cropBaoziBannerBand, [bytes, band.top, band.bottom]);

List<int>? _findBaoziBannerBand(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null || decoded.numFrames != 1) return null;
    final width = decoded.width;
    final height = decoded.height;
    if (width < 400 || height < 600 || width * height > 12 * 1000 * 1000) {
      return null;
    }
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
      if (bandHeight >= (height * 0.025).round() &&
          bandHeight <= (height * 0.20).round() &&
          (start <= height * 0.03 || start >= height * 0.12) &&
          (height - end <= height * 0.03 || height - end >= height * 0.12) &&
          _hasBaoziLogoAndText(decoded, start, end, xStep)) {
        return [start, end, height];
      }
      start = end;
    }
  } catch (_) {}
  return null;
}

Uint8List _cropBaoziBannerBand(List<dynamic> args) {
  final bytes = args[0] as Uint8List;
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null || decoded.numFrames != 1) return bytes;
    final height = decoded.height;
    final top = ((args[1] as double) * height).round().clamp(0, height).toInt();
    final end = ((args[2] as double) * height).round().clamp(0, height).toInt();
    // Manual selections may touch the top or bottom edge (Baozi often places
    // its banner there). Keep bounds checks, but don't reject edge selections.
    final cropHeight = end - top;
    if (top < 0 || end > height ||
        cropHeight < height * 0.005 ||
        cropHeight > height * 0.30 ||
        height - cropHeight < height * 0.50) {
      return bytes;
    }
    final result = img.Image(width: decoded.width, height: height - (end - top));
    if (top > 0) {
      final upper = img.copyCrop(decoded, x: 0, y: 0, width: decoded.width, height: top);
      img.compositeImage(result, upper, dstX: 0, dstY: 0);
    }
    if (end < height) {
      final lower = img.copyCrop(decoded, x: 0, y: end, width: decoded.width, height: height - end);
      img.compositeImage(result, lower, dstX: 0, dstY: top);
    }
    return Uint8List.fromList(img.encodeJpg(result, quality: 94));
  } catch (_) {
    return bytes;
  }
}

Uint8List _removeBaoziBanner(Uint8List bytes) {
  // Use the same candidate finder as the preview/editor so automatic and
  // manual cropping agree, including banners placed at the image edges.
  final band = _findBaoziBannerBand(bytes);
  if (band == null || band[2] <= 0) return bytes;
  return _cropBaoziBannerBand([
    bytes,
    band[0] / band[2],
    band[1] / band[2],
  ]);
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
          p.r > 160 &&
          p.g > 100 &&
          p.b < 150 &&
          p.r > p.g * 1.03) {
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
