import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:venera_next/features/reader/continuous_data.dart';
import 'package:venera_next/features/reader/continuous_view.dart';
import 'package:venera_next/features/reader/reader_controller.dart';
import 'package:venera_next/features/reader/reader_viewport.dart';
import 'package:venera_next/foundation/image_work.dart';

void main() {
  testWidgets('idle window trim keeps the same visible chapter and page', (
    tester,
  ) async {
    final root = Directory.systemTemp.createTempSync('waterfall-window-');
    final file = File('${root.path}/page.png')
      ..writeAsBytesSync(img.encodePng(img.Image(width: 40, height: 80)));
    final image = 'file://${file.path}';
    final work = ImageWork();
    final binding = ReaderViewportBinding();
    final navigation = ReaderController(
      pageCount: () => 1,
      chapterCount: () => 20,
      animationEnabled: () => false,
      viewport: () => binding.current,
      onChanged: () {},
      onPageChanged: () {},
      onError: (e, s) => fail('$e'),
    )..replaceChapterImages([image]);
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderContinuousView(
            imageWork: work,
            data: ReaderContinuousData(
              vertical: true,
              reverse: false,
              crossChapter: true,
              firstChapter: true,
              lastChapter: false,
              maxChapter: 20,
              preloadCount: 0,
              splitWideImages: false,
              invertSplit: false,
              scrollSpeed: 1,
              limitImageWidth: false,
              sideMargin: 0,
              doubleTapCollect: false,
              centerLongPressZoom: true,
              sourceKey: null,
              comicId: 'book',
            ),
            navigation: navigation,
            loadChapter: (chapter, scope) async => [image],
            chapterId: (c) => 'chapter-$c',
            chapterTitle: (c) => 'Chapter $c',
            onViewportChanged: binding.update,
            onUpdate: () {},
            onFloatingButton: (_) {},
            onCollectImage: () {},
            onActiveChapterChanged: () {},
            onContentLoading: (_) {},
            onPreviousError: (e, s) => fail('$e'),
            onNavigationError: (c, e, s) => fail('$e'),
            readerSize: () => const Size(800, 600),
            readImage: (_) async => file.readAsBytes(),
          ),
        ),
      );
      final state = tester.state<ContinuousModeState>(
        find.byType(ReaderContinuousView),
      );
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      for (var i = 0; i < 12; i++) {
        if (state.scrollController.hasClients) {
          state.scrollController.jumpTo(
            state.scrollController.position.maxScrollExtent,
          );
        }
        for (var frame = 0; frame < 5; frame++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
      }
      final before = tester
          .widget<ScrollablePositionedList>(
            find.byType(ScrollablePositionedList),
          )
          .itemCount;
      final chapter = navigation.state.chapter, page = navigation.state.page;
      expect(before, greaterThan(7));
      await tester.pump(const Duration(milliseconds: 700));
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
      final after = tester
          .widget<ScrollablePositionedList>(
            find.byType(ScrollablePositionedList),
          )
          .itemCount;
      expect(after, lessThan(before));
      expect(
        (navigation.state.chapter, navigation.state.page),
        (chapter, page),
      );
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      var closed = false;
      final closing = work.dispose().then((_) => closed = true);
      for (var frame = 0; frame < 50 && !closed; frame++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      expect(closed, isTrue);
      await closing;
      navigation.dispose();
      root.deleteSync(recursive: true);
    }
  });
}
