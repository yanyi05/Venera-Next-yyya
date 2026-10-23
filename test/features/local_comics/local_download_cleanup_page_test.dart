import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/features/local_comics/local.dart';
import 'package:venera_next/features/local_comics/local_download_cleanup_page.dart';
import 'package:venera_next/features/comic_source/comic_source_api.dart'
    show ComicChapters;
import 'package:venera_next/foundation/comic_type.dart';
import 'package:venera_next/foundation/app.dart';

void main() {
  for (final size in [const Size(375, 812), const Size(812, 375)]) {
    testWidgets(
      'cleanup selection is explicit and cancellation preserves files at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        late Directory root;
        late LocalManager library;
        await tester.runAsync(() async {
          root = Directory.systemTemp.createTempSync('download-cleanup-ui-');
          App.dataPath = root.path;
          File('${root.path}/local_path').writeAsStringSync(root.path);
          library = LocalManager.independent(initializeSources: () async {});
          await library.init();
          for (final item in [
            ('online', 'Online Book', const ComicType(123)),
            ('import', 'Imported Book', ComicType.local),
          ]) {
            File('${root.path}/${item.$1}/a/page.jpg')
              ..createSync(recursive: true)
              ..writeAsStringSync('keep');
            await library.add(
              LocalComic(
                id: item.$1,
                title: item.$2,
                subtitle: '',
                tags: [],
                directory: item.$1,
                chapters: const ComicChapters({'a': 'Chapter A'}),
                cover: 'cover.jpg',
                comicType: item.$3,
                downloadedChapters: const ['a'],
                createdAt: DateTime(2026),
              ),
            );
          }
        });
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: const TextScaler.linear(1.5),
              ),
              child: LocalDownloadCleanupPage(manager: library),
            ),
          ),
        );
        final scroll = find.byType(Scrollable).first;
        await tester.scrollUntilVisible(
          find.text('Online Book'),
          200,
          scrollable: scroll,
        );
        expect(find.text('Imported Book'), findsNothing);
        tester
            .widget<CheckboxListTile>(find.byType(CheckboxListTile).first)
            .onChanged!(true);
        await tester.pump();
        expect(find.text('删除所选（1 本）'), findsOneWidget);
        await tester.tap(find.text('删除所选（1 本）'));
        await tester.pumpAndSettle();
        expect(find.text('删除所选本地下载？'), findsOneWidget);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(File('${root.path}/online/a/page.jpg').existsSync(), isTrue);
        expect(library.find('online', const ComicType(123)), isNotNull);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() async {
          await library.pendingDownloadTaskWrites;
          library.dispose();
          await root.delete(recursive: true);
        });
      },
    );
  }
}
