import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/features/settings/cache_cleanup.dart';
import 'package:venera_next/foundation/cache_manager.dart';

void main() {
  testWidgets(
    'cache management explains scope and cancel does not clear disk data',
    (tester) async {
      final root = Directory.systemTemp.createTempSync('cache-cleanup-ui-');
      final manager = CacheManager.open(
        dataPath: root.path,
        cacheRoot: root.path,
      );
      await tester.runAsync(() => manager.writeCache('image', [1, 2, 3]));
      await tester.pumpWidget(
        MaterialApp(home: CacheCleanupSettings(manager: manager)),
      );
      await tester.pumpAndSettle();
      expect(find.text('缓存管理'), findsOneWidget);
      final tile = find.widgetWithText(ListTile, '清理全部临时缓存');
      await tester.scrollUntilVisible(tile, 200);
      await tester.tap(
        find.descendant(of: tile, matching: find.byType(TextButton)),
      );
      await tester.pumpAndSettle();
      expect(find.text('清理全部临时缓存？'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      final summary = await tester.runAsync(manager.summary);
      expect(summary!.entries, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await manager.dispose();
        await root.delete(recursive: true);
      });
    },
  );
}
