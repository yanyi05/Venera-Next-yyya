import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:venera_next/foundation/cache_manager.dart';
import 'package:venera_next/foundation/image_band_transform.dart';

void main() {
  test(
    'manual crop cache keys include original bytes and all crop bands',
    () async {
      final root = Directory.systemTemp.createTempSync('manual-crop-cache-');
      final previous = CacheManager.instance;
      final cache = CacheManager.open(
        dataPath: root.path,
        cacheRoot: root.path,
      );
      CacheManager.instance = cache;
      try {
        final bytes = Uint8List.fromList(
          img.encodePng(img.Image(width: 8, height: 100)),
        );
        final first = await cachedCropImageBannerBands(bytes, [
          const Rect.fromLTRB(0, .2, 1, .3),
        ]);
        final size = cache.currentSize;
        expect(img.decodePng(first)!.height, 90);
        expect(
          await cachedCropImageBannerBands(bytes, [
            const Rect.fromLTRB(0, .2, 1, .3),
          ]),
          first,
        );
        expect(cache.currentSize, size);
        final other = await cachedCropImageBannerBands(bytes, [
          const Rect.fromLTRB(0, .2, 1, .4),
        ]);
        expect(img.decodePng(other)!.height, 80);
        final changed = Uint8List.fromList(
          img.encodePng(img.Image(width: 10, height: 100)),
        );
        expect(
          img
              .decodePng(
                await cachedCropImageBannerBands(changed, [
                  const Rect.fromLTRB(0, .2, 1, .3),
                ]),
              )!
              .width,
          10,
        );
      } finally {
        await cache.dispose();
        CacheManager.instance = previous;
        root.deleteSync(recursive: true);
      }
    },
  );
}
