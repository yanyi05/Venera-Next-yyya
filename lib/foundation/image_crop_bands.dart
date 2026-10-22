/// Normalized ranges measured against the input image. Overlaps are merged.
List<({double top, double bottom})> normalizeImageCropBands(Object? value) {
  if (value is! List || value.length > 32) {
    throw const FormatException('cropBands must contain at most 32 bands');
  }
  final bands = <({double top, double bottom})>[];
  for (final item in value) {
    if (item is! Map || item['top'] is! num || item['bottom'] is! num) {
      throw const FormatException('Each crop band needs top and bottom');
    }
    final top = (item['top'] as num).toDouble();
    final bottom = (item['bottom'] as num).toDouble();
    if (!top.isFinite ||
        !bottom.isFinite ||
        top < 0 ||
        bottom > 1 ||
        bottom - top < .005) {
      throw const FormatException('Invalid normalized crop band');
    }
    bands.add((top: top, bottom: bottom));
  }
  bands.sort((a, b) => a.top.compareTo(b.top));
  final merged = <({double top, double bottom})>[];
  for (final band in bands) {
    if (merged.isNotEmpty && band.top <= merged.last.bottom) {
      final previous = merged.removeLast();
      merged.add((
        top: previous.top,
        bottom: band.bottom > previous.bottom ? band.bottom : previous.bottom,
      ));
    } else {
      merged.add(band);
    }
  }
  final removed = merged.fold<double>(0, (sum, b) => sum + b.bottom - b.top);
  if (removed > .300000001) {
    throw const FormatException('Crop bands may remove at most 30%');
  }
  return merged;
}

List<({int top, int bottom})> retainedImageRows(Object? bands, int height) {
  final normalized = normalizeImageCropBands(bands);
  var cursor = 0;
  final rows = <({int top, int bottom})>[];
  for (final band in normalized) {
    final top = (band.top * height).round();
    final bottom = (band.bottom * height).round();
    if (top > cursor) rows.add((top: cursor, bottom: top));
    if (bottom > cursor) cursor = bottom;
  }
  if (cursor < height) rows.add((top: cursor, bottom: height));
  return rows;
}
