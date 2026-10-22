import 'package:flutter/foundation.dart';

class SmartDownloadTarget {
  SmartDownloadTarget({
    required this.source,
    required this.comic,
    required this.title,
    required this.chapter,
    required this.directory,
    required List<String> chapters,
  }) : chapters = List.unmodifiable(chapters);
  final String source, comic, title, chapter, directory;
  final List<String> chapters;
}

/// Readers publish identity only; the foreground runtime owns policy and work.
class SmartDownloadRequests extends ChangeNotifier {
  SmartDownloadRequests._();
  static final instance = SmartDownloadRequests._();
  SmartDownloadTarget? target;
  void publish(SmartDownloadTarget next) {
    final old = target;
    if (old?.directory == next.directory &&
        old?.source == next.source &&
        old?.comic == next.comic &&
        old?.chapter == next.chapter &&
        listEquals(old?.chapters, next.chapters)) {
      return;
    }
    target = next;
    notifyListeners();
  }
}
