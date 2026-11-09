import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/foundation/cache_manager.dart';

void main() {
  late Directory root;
  late CacheManager cache;
  setUp(() {
    root = Directory.systemTemp.createTempSync('venera-storage-');
    cache = CacheManager.open(dataPath: root.path, cacheRoot: root.path);
  });
  tearDown(() async {
    await cache.dispose();
    await root.delete(recursive: true);
  });
  test(
    'grouped cleanup respects recent reads and never deletes downloads',
    () async {
      final download = File('${root.path}/download/comic.jpg');
      download.parent.createSync();
      download.writeAsBytesSync([9, 9]);
      await cache.writeComicCache(
        'page',
        [1, 2, 3],
        sourceKey: 'test',
        comicId: 'comic',
      );
      await cache.writeCache('cover', [4]);
      final snapshot = await cache.storageSnapshot();
      final group = snapshot.entries
          .firstWhere((entry) => entry.key == 'page')
          .group;
      expect(snapshot.estimate({group}), 3);
      expect(
        await cache.clearSnapshot(snapshot, {
          group,
        }, keepSince: DateTime.now().subtract(const Duration(days: 7))),
        0,
      );
      expect(await cache.clearSnapshot(snapshot, {group}), 3);
      expect(await cache.findCache('page'), isNull);
      expect(await cache.findCache('cover'), isNotNull);
      expect(download.readAsBytesSync(), [9, 9]);
      expect(cache.currentSize, 1);
    },
  );
  test(
    'confirmation snapshot cannot delete a replacement write or refreshed read',
    () async {
      await cache.writeComicCache(
        'page',
        [1],
        sourceKey: 'test',
        comicId: 'comic',
      );
      final snapshot = await cache.storageSnapshot();
      final group = snapshot.entries.single.group;
      await cache.writeComicCache(
        'page',
        [2, 3],
        sourceKey: 'test',
        comicId: 'comic',
      );
      expect(await cache.clearSnapshot(snapshot, {group}), 0);
      expect(await (await cache.findCache('page'))!.readAsBytes(), [2, 3]);
      final updated = await cache.storageSnapshot();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await cache.findCache('page');
      expect(await cache.clearSnapshot(updated, {group}), 0);
    },
  );
}
