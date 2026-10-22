import 'dart:convert';
import 'dart:ui';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:venera_next/features/reader/image_position.dart';
import 'package:venera_next/foundation/appdata.dart';

/// Per-page manual override for Baozi banner cropping. Coordinates are
/// normalized and describe the horizontal strip to remove from the source.
abstract final class ReaderImageBannerCrops {
  static const _settingKey = 'readerImageBannerCrops';
  static final changes = ChangeNotifier();
  static final Map<String, int> _revision = {};

  static String _key(ReaderImageAddress address) =>
      sha256.convert(utf8.encode(address.cacheKey)).toString();

  static Rect? read(ReaderImageAddress address) {
    final raw = appdata.settings[_settingKey];
    if (raw is! Map) return null;
    final value = raw[_key(address)];
    if (value is! Map || value['top'] is! num || value['bottom'] is! num) {
      return null;
    }
    final top = (value['top'] as num).toDouble().clamp(0.0, 1.0).toDouble();
    final bottom = (value['bottom'] as num).toDouble().clamp(0.0, 1.0).toDouble();
    if (bottom - top < .005) return null;
    return Rect.fromLTRB(0, top, 1, bottom);
  }

  static int revision(ReaderImageAddress address) =>
      _revision[_key(address)] ?? 0;

  static Future<void> write(ReaderImageAddress address, Rect? band) async {
    final key = _key(address);
    final values = <String, dynamic>{};
    final raw = appdata.settings[_settingKey];
    if (raw is Map) {
      for (final entry in raw.entries) {
        if (entry.key is String) values[entry.key as String] = entry.value;
      }
    }
    if (band == null) {
      values.remove(key);
    } else {
      final top = band.top.clamp(0.0, 1.0).toDouble();
      final bottom = band.bottom.clamp(0.0, 1.0).toDouble();
      if (bottom - top < .005) return;
      values[key] = {'top': top, 'bottom': bottom};
    }
    await appdata.updateSettings((settings) {
      settings[_settingKey] = values;
    });
    _revision[key] = (_revision[key] ?? 0) + 1;
    changes.notifyListeners();
  }
}
