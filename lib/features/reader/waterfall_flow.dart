import 'dart:collection';
import 'image_position.dart';

class WaterfallImageRef {
  final ReaderImagePosition position;
  final String imageKey;
  final bool isFirstInSegment;

  const WaterfallImageRef({
    required this.position,
    required this.imageKey,
    this.isFirstInSegment = false,
  });
}

class WaterfallChapterSegment {
  final int chapter;
  final String eid;
  final List<String> images;
  final Set<int> cached = {};

  WaterfallChapterSegment({
    required this.chapter,
    required this.eid,
    required this.images,
  });
}

/// Read access for view adapters; chapter insertion/reset belongs to the owner.
abstract interface class WaterfallFlowView {
  List<WaterfallChapterSegment> get segments;
  bool get isEmpty;
  int get imageCount;
  int? get firstChapter;
  int? get lastChapter;
  WaterfallChapterSegment? segmentOfChapter(int chapter);
  WaterfallImageRef? imageRefAt(int index);
  int? imageIndexOf(ReaderImagePosition position);
}

class WaterfallChapterFlow implements WaterfallFlowView {
  WaterfallChapterFlow({List<WaterfallChapterSegment>? segments}) {
    if (segments != null) {
      _segments.addAll(segments);
      _reindex();
    }
  }

  final _segments = <WaterfallChapterSegment>[];
  final _offsets = <int, int>{};
  final _byChapter = <int, WaterfallChapterSegment>{};
  int _imageCount = 0;
  void _reindex() {
    _offsets.clear();
    _byChapter.clear();
    _imageCount = 0;
    for (final segment in _segments) {
      _offsets[segment.chapter] = _imageCount;
      _byChapter[segment.chapter] = segment;
      _imageCount += segment.images.length;
    }
  }

  /// Trim only distant metadata. The view supplies every visible chapter and
  /// restores the same image/offset after the leading indices change.
  int trimAround(int first, int last, {int neighbours = 2}) {
    var removedBefore = 0;
    _segments.removeWhere((segment) {
      if (segment.chapter < first - neighbours) {
        removedBefore += segment.images.length;
        return true;
      }
      return segment.chapter > last + neighbours;
    });
    _reindex();
    return removedBefore;
  }

  @override
  List<WaterfallChapterSegment> get segments => UnmodifiableListView(_segments);

  @override
  bool get isEmpty => _segments.isEmpty;

  @override
  int get imageCount => _imageCount;

  @override
  int? get firstChapter => _segments.firstOrNull?.chapter;

  @override
  int? get lastChapter => _segments.lastOrNull?.chapter;

  @override
  WaterfallChapterSegment? segmentOfChapter(int chapter) => _byChapter[chapter];

  @override
  WaterfallImageRef? imageRefAt(int index) {
    if (index <= 0) return null;
    var low = 0, high = _segments.length - 1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      final segment = _segments[mid];
      final offset = _offsets[segment.chapter]!;
      if (index <= offset) {
        high = mid - 1;
        continue;
      }
      final remaining = index - offset;
      if (remaining > segment.images.length) {
        low = mid + 1;
        continue;
      }
      return WaterfallImageRef(
        position: ReaderImagePosition(
          chapter: segment.chapter,
          imageNumber: remaining,
          chapterId: segment.eid,
        ),
        imageKey: segment.images[remaining - 1],
        isFirstInSegment: remaining == 1,
      );
    }
    return null;
  }

  @override
  int? imageIndexOf(ReaderImagePosition position) {
    if (position.imageNumber <= 0) return null;
    final segment = _byChapter[position.chapter];
    if (segment == null ||
        segment.eid != position.chapterId ||
        position.imageNumber > segment.images.length) {
      return null;
    }
    return _offsets[position.chapter]! + position.imageNumber;
  }

  bool shouldLoadAfter({
    required int current,
    required int threshold,
    required int maxChapter,
  }) {
    if (_segments.isEmpty) return false;
    if (imageCount - current >= threshold) return false;
    return _segments.last.chapter < maxChapter;
  }

  bool shouldLoadBefore({required int current, required int threshold}) {
    if (_segments.isEmpty) return false;
    if (current > threshold) return false;
    return _segments.first.chapter > 1;
  }

  void addAfter(WaterfallChapterSegment segment) {
    if (_segments.any((item) => item.chapter == segment.chapter)) return;
    _segments.add(segment);
    _segments.sort((a, b) => a.chapter.compareTo(b.chapter));
    _reindex();
  }

  int addBefore(WaterfallChapterSegment segment) {
    if (_segments.any((item) => item.chapter == segment.chapter)) return 0;
    _segments.add(segment);
    _segments.sort((a, b) => a.chapter.compareTo(b.chapter));
    _reindex();
    return segment.images.length;
  }

  void reset(WaterfallChapterSegment segment) {
    _segments
      ..clear()
      ..add(segment);
    _reindex();
  }
}
