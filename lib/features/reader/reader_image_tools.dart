import 'reader_image_masks.dart';
import 'image_position.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/foundation/image_crop.dart';

abstract final class ReaderImageTools {
  static String _key(String comicId, String? sourceKey) => sha256
      .convert(utf8.encode(jsonEncode([sourceKey ?? 'local', comicId])))
      .toString();
  static ReaderCrop cropForImage(ReaderImageAddress address, ReaderCrop crop) =>
      ReaderImageMasks.read(address).isEmpty ? crop : const ReaderCrop();
  static ReaderCrop crop(String comicId, String? sourceKey) {
    final values = appdata.settings['readerImageCrop'];
    return ReaderCrop.fromJson(
      values is Map ? values[_key(comicId, sourceKey)] : null,
    );
  }

  static Future<void> saveCrop(
    String comicId,
    String? sourceKey,
    ReaderCrop crop,
  ) => appdata.updateSettings((settings) {
    final raw = settings['readerImageCrop'];
    final values = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
    if (crop.enabled) {
      values[_key(comicId, sourceKey)] = crop.toJson();
    } else {
      values.remove(_key(comicId, sourceKey));
    }
    settings['readerImageCrop'] = values;
  });
}
