import 'dart:convert';
import 'dart:ui';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:venera_next/foundation/image_crop_bands.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'reader_image_address.dart';

/// Missing override uses source processing; an empty override shows the original.
abstract final class ReaderImageBannerCrops {
  static const _settingKey = 'readerImageBannerCrops';
  static final changes = _ImageChanges();
  static final Map<String, int> _revision = {};
  static String _key(ReaderImageAddress address) =>
      sha256.convert(utf8.encode(address.cacheKey)).toString();

  static List<Rect>? readBands(ReaderImageAddress address) {
    final raw = appdata.settings[_settingKey];
    if (raw is! Map) return null;
    final value = raw[_key(address)];
    if (value is! Map) return null;
    try {
      final bands = normalizeImageCropBands(value['bands'] ?? [value]);
      return [for (final b in bands) Rect.fromLTRB(0, b.top, 1, b.bottom)];
    } on FormatException {
      return null;
    }
  }

  static int revision(ReaderImageAddress address) =>
      _revision[_key(address)] ?? 0;

  static void invalidate(ReaderImageAddress address) {
    _revision[_key(address)] = revision(address) + 1;
    changes.notifyChanged();
  }

  static Future<void> writeBands(
    ReaderImageAddress address,
    List<Rect>? bands,
  ) async {
    final normalized = bands == null
        ? null
        : normalizeImageCropBands([
            for (final b in bands) {'top': b.top, 'bottom': b.bottom},
          ]);
    final key = _key(address);
    await appdata.updateSettings((settings) {
      final raw = settings[_settingKey];
      final values = <String, dynamic>{
        if (raw is Map)
          for (final e in raw.entries)
            if (e.key is String) e.key as String: e.value,
      };
      if (normalized == null) {
        values.remove(key);
      } else {
        values[key] = {
          'bands': [
            for (final b in normalized) {'top': b.top, 'bottom': b.bottom},
          ],
        };
      }
      settings[_settingKey] = values;
    });
    invalidate(address);
  }
}

class _ImageChanges extends ChangeNotifier {
  void notifyChanged() => notifyListeners();
}
