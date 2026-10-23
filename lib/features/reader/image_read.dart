import 'package:venera_next/foundation/cache_manager.dart';
import 'package:venera_next/foundation/file_system.dart';
import 'image_position.dart';

/// Reads the original address and keeps the accepted cache/file Future. The
/// caller's ImageWork owns cancellation and waits for its actual completion.
Future<Uint8List?> readReaderImageBytes(
  ReaderImageAddress image, {
  bool original = false,
}) async {
  if (image.imageKey.startsWith('file://')) {
    return File(image.imageKey.substring(7)).readAsBytes();
  }
  final cache = CacheManager();
  final file = original
      ? await cache.findUnmodifiedCache(image.cacheKey) ??
            await cache.findCache('${image.cacheKey}@original')
      : await cache.findCache(image.cacheKey);
  return file?.readAsBytes();
}
