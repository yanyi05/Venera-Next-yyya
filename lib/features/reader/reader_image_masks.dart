import 'dart:convert';
import 'dart:ui';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:venera_next/foundation/appdata.dart';

import 'image_position.dart';

/// Persistent, per-image display masks. The original image and its cache entry
/// are never modified.
abstract final class ReaderImageMasks {
  static final changes = _ImageChanges();
  static const _settingKey = 'readerImageMasks';

  static String _key(ReaderImageAddress address) =>
      sha256.convert(utf8.encode(address.cacheKey)).toString();

  static List<Rect> read(ReaderImageAddress address) {
    final raw = appdata.settings[_settingKey];
    if (raw is! Map) return const [];
    final value = raw[_key(address)];
    final list = value is List
        ? value
        : value is Map && value['rectangles'] is List
        ? value['rectangles'] as List
        : const [];
    return [
      for (final item in list)
        if (item is Map &&
            item['l'] is num &&
            item['t'] is num &&
            item['r'] is num &&
            item['b'] is num)
          Rect.fromLTRB(
            (item['l'] as num).toDouble().clamp(0.0, 1.0).toDouble(),
            (item['t'] as num).toDouble().clamp(0.0, 1.0).toDouble(),
            (item['r'] as num).toDouble().clamp(0.0, 1.0).toDouble(),
            (item['b'] as num).toDouble().clamp(0.0, 1.0).toDouble(),
          ),
    ];
  }

  static Color readColor(ReaderImageAddress address) {
    final raw = appdata.settings[_settingKey];
    if (raw is! Map) return const Color(0xFFFFFFFF);
    final value = raw[_key(address)];
    if (value is Map && value['color'] is int) {
      return Color(value['color'] as int);
    }
    return const Color(0xFFFFFFFF);
  }

  static Future<void> write(
    ReaderImageAddress address,
    List<Rect> rectangles,
    Color color,
  ) async {
    final key = _key(address);
    final values = <String, dynamic>{};
    final raw = appdata.settings[_settingKey];
    if (raw is Map) {
      for (final entry in raw.entries) {
        if (entry.key is String) values[entry.key as String] = entry.value;
      }
    }
    if (rectangles.isEmpty) {
      values.remove(key);
    } else {
      values[key] = {
        'color': color.toARGB32(),
        'rectangles': [
          for (final rect in rectangles)
            {
              'l': rect.left.clamp(0.0, 1.0),
              't': rect.top.clamp(0.0, 1.0),
              'r': rect.right.clamp(0.0, 1.0),
              'b': rect.bottom.clamp(0.0, 1.0),
            },
        ],
      };
    }
    await appdata.updateSettings((settings) {
      settings[_settingKey] = values;
    });
    changes.notifyChanged();
  }
}

class _ImageChanges extends ChangeNotifier {
  void notifyChanged() => notifyListeners();
}
