import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/src/core/photo_view_core.dart';
import 'package:venera_next/features/reader/auto_reading.dart';
import 'package:venera_next/features/reader/gallery_data.dart';
import 'package:venera_next/features/reader/gallery_view.dart';
import 'package:venera_next/features/reader/page_layout.dart';
import 'package:venera_next/features/reader/reader_controller.dart';
import 'package:venera_next/features/reader/reader_viewport.dart';
import 'package:venera_next/foundation/image_work.dart';

void main() {
  for (final vertical in [false, true]) {
    for (final reverse in [false, true]) {
      for (final changeLayout in [false, true]) {
        testWidgets(
          'automatic gallery survives both rotations: vertical=$vertical reverse=$reverse layout=$changeLayout',
          (tester) async {
            final fixture = _GalleryFixture();
            try {
              await fixture.mount(tester, vertical: vertical, reverse: reverse);
              fixture.automatic.start();
              await fixture.rotate(
                tester,
                const Size(667, 375),
                imagesPerPage: changeLayout ? 2 : 1,
              );
              await fixture.pumpUntil(
                tester,
                () =>
                    fixture.navigation.state.page > 1 &&
                    fixture.automatic.status == AutoReadingStatus.running,
              );
              expect(fixture.automatic.status, AutoReadingStatus.running);
              final oldPage = fixture.navigation.state.page;
              await fixture.rotate(tester, const Size(375, 667));
              await fixture.pumpUntil(
                tester,
                () =>
                    fixture.navigation.state.page > oldPage &&
                    fixture.automatic.status == AutoReadingStatus.running,
              );
              expect(fixture.automatic.status, AutoReadingStatus.running);
              expect(tester.takeException(), isNull);
            } finally {
              await fixture.dispose(tester);
            }
          },
        );
      }
    }
  }

  testWidgets('rotation does not treat a user zoom as the new initial scale', (
    tester,
  ) async {
    final fixture = _GalleryFixture();
    try {
      await fixture.mount(tester);
      final photo = fixture.photo;
      final core = tester.state<PhotoViewCoreState>(
        find.byWidgetPredicate(
          (widget) =>
              widget is PhotoViewCore && identical(widget.controller, photo),
        ),
      );
      const focalPoint = Offset(187, 333);
      core.onScaleStart(ScaleStartDetails(focalPoint: focalPoint));
      core.onScaleUpdate(
        ScaleUpdateDetails(
          focalPoint: focalPoint,
          scale: 1.75,
          pointerCount: 2,
        ),
      );
      core.onScaleEnd(ScaleEndDetails());
      await tester.pumpAndSettle();
      fixture.automatic.start();
      await fixture.rotate(tester, const Size(667, 375), expectReady: false);
      final page = fixture.navigation.state.page;
      await fixture.pumpFrames(tester, 70);
      expect(fixture.navigation.state.page, page);
      expect(
        fixture.gallery.autoReadingImages.state,
        AutoReadingImageState.blocked,
      );
      photo.reset();
      await fixture.pumpUntil(
        tester,
        () => fixture.navigation.state.page > page,
      );
      expect(tester.takeException(), isNull);
    } finally {
      await fixture.dispose(tester);
    }
  });
}

class _GalleryFixture {
  final directory = Directory.systemTemp.createTempSync('gallery-rotation-');
  final work = ImageWork();
  final viewport = ReaderViewportBinding();
  final key = GlobalKey<GalleryModeState>();
  var size = const Size(375, 667);
  late ReaderGalleryData data;
  late final navigation = ReaderController(
    pageCount: () => data.totalPages,
    chapterCount: () => 1,
    animationEnabled: () => true,
    viewport: () => viewport.current,
    onChanged: () {},
    onPageChanged: () {},
    onError: (error, stack) => fail('$error\n$stack'),
  );
  late final automatic = AutoReadingController(
    settings: () => const AutoReadingSettings(
      gallery: true,
      pageInterval: 1,
      pixelsPerSecond: 0,
      stepped: false,
      stepsPerSecond: 1,
      pixelsPerStep: 0,
    ),
    canAdvance: () => !navigation.state.isAnimating && gallery.autoReadingReady,
    advance: (_) => navigation.toPage(navigation.state.page + 1)
        ? AutoReadingStep.advanced
        : AutoReadingStep.finished,
  );

  GalleryModeState get gallery => key.currentState!;
  PhotoViewController get photo =>
      gallery.photoViewControllers[navigation.state.page]!;

  Future<void> mount(
    WidgetTester tester, {
    bool vertical = false,
    bool reverse = false,
  }) async {
    final image = img.Image(width: 120, height: 180)
      ..clear(img.ColorRgb8(60, 90, 120));
    final file = File('${directory.path}/page.png')
      ..writeAsBytesSync(img.encodePng(image));
    navigation.replaceChapterImages(List.filled(12, 'file://${file.path}'));
    data = ReaderGalleryData(
      content: navigation.content,
      layout: const ReaderPageLayout(
        imagesPerPage: 1,
        singleImageOnFirstPage: false,
      ),
      vertical: vertical,
      reverse: reverse,
      commentsAtEnd: false,
      firstChapter: true,
      lastChapter: true,
      preloadCount: 0,
      doubleTapCollect: false,
      centerLongPressZoom: false,
      pageAnimation: true,
      sourceKey: null,
      comicId: 'rotation',
      chapterId: 'one',
    );
    await tester.binding.setSurfaceSize(size);
    await tester.pumpWidget(build());
    await pumpUntil(tester, () => gallery.autoReadingReady);
  }

  Widget build() => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: ReaderGalleryView(
        key: key,
        data: data,
        imageWork: work,
        navigation: navigation,
        onViewportChanged: viewport.update,
        onReady: () {},
        onPageReported: (_, _) {},
        onChapterChanged: () {},
        onCollectImage: () {},
        readerSize: () => size,
        readImage: (_) async => null,
      ),
    ),
  );

  Future<void> rotate(
    WidgetTester tester,
    Size next, {
    int imagesPerPage = 1,
    bool expectReady = true,
  }) async {
    size = next;
    final previousImagesPerPage = data.layout.imagesPerPage;
    final layout = ReaderPageLayout(
      imagesPerPage: imagesPerPage,
      singleImageOnFirstPage: false,
    );
    navigation.resetAnimation();
    navigation.restorePage(
      data.layout.remapPage(
        navigation.state.page,
        layout,
        imageCount: data.images.length,
      ),
    );
    data = ReaderGalleryData(
      content: data.content,
      layout: layout,
      vertical: data.vertical,
      reverse: data.reverse,
      commentsAtEnd: false,
      firstChapter: true,
      lastChapter: true,
      preloadCount: 0,
      doubleTapCollect: false,
      centerLongPressZoom: false,
      pageAnimation: true,
      sourceKey: null,
      comicId: 'rotation',
      chapterId: 'one',
    );
    await tester.binding.setSurfaceSize(size);
    await tester.pumpWidget(build());
    if (previousImagesPerPage != imagesPerPage) {
      gallery.toPage(navigation.state.page);
    }
    await pumpFrames(tester, 15);
    if (expectReady) expect(gallery.autoReadingReady, isTrue);
  }

  Future<void> pumpFrames(WidgetTester tester, int count) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(() => pumpEventQueue());
    }
  }

  Future<void> pumpUntil(WidgetTester tester, bool Function() condition) async {
    for (var i = 0; i < 150 && !condition(); i++) {
      await pumpFrames(tester, 1);
    }
    expect(condition(), isTrue);
  }

  Future<void> dispose(WidgetTester tester) async {
    automatic.dispose();
    await tester.pumpWidget(const SizedBox());
    var settled = false;
    final closing = work.dispose();
    unawaited(closing.then<void>((_) => settled = true));
    await pumpUntil(tester, () => settled);
    await closing;
    navigation.dispose();
    await tester.binding.setSurfaceSize(null);
    await tester.runAsync(() => directory.delete(recursive: true));
  }
}
