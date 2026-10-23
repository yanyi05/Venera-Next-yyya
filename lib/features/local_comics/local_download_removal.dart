import 'package:flutter/foundation.dart' show listEquals;
import 'local_comic_model.dart';

/// A frozen confirmation target, never widened after the confirmation dialog.
class LocalDownloadRemoval {
  LocalDownloadRemoval(
    this.comic, {
    List<String>? chapters,
    required Map<String, bool?> protection,
  }) : downloaded = List.unmodifiable(comic.downloadedChapters),
       chapters = chapters == null ? null : List.unmodifiable(chapters.toSet()),
       protection = Map.unmodifiable(protection) {
    if (this.chapters != null &&
        (this.chapters!.isEmpty ||
            this.chapters!.any((id) => !downloaded.contains(id)))) {
      throw ArgumentError('Select existing downloaded chapters');
    }
    if (selectedChapters.any((id) => !this.protection.containsKey(id))) {
      throw ArgumentError('Capture protection for every selected chapter');
    }
  }
  final LocalComic comic;
  final List<String> downloaded;

  /// null means the complete registered download, including its cover.
  final List<String>? chapters;
  final Map<String, bool?> protection;
  (String, int) get key => (comic.id, comic.comicType.value);
  Iterable<String> get selectedChapters => chapters ?? downloaded;
  int get protectedCount =>
      selectedChapters.where((id) => protection[id] == true).length;

  bool matches(LocalComic? current) =>
      current != null &&
      current.id == comic.id &&
      current.comicType == comic.comicType &&
      current.directory == comic.directory &&
      current.cover == comic.cover &&
      current.title == comic.title &&
      current.createdAt == comic.createdAt &&
      listEquals(current.downloadedChapters, downloaded);
}
