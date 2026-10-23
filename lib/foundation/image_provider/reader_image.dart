import 'package:venera_next/foundation/reading_activity.dart';
import 'package:venera_next/foundation/operation_failure.dart';
import 'package:venera_next/foundation/global_preference_store.dart';
import 'package:venera_next/foundation/application_preferences.dart';
import 'dart:async' show Future, StreamController;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:venera_next/foundation/file_system.dart';
import 'reader_image_processing.dart';
import 'package:venera_next/network/images.dart';
import 'package:venera_next/network/image_stream.dart';
import 'base_image_provider.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/foundation/image_band_transform.dart';
import 'package:venera_next/foundation/reader_image_address.dart';
import 'package:venera_next/foundation/reader_image_crops.dart';
import 'package:venera_next/foundation/cache_manager.dart';

class ReaderImageProvider extends BaseImageProvider<ReaderImageProvider> {
  /// Image provider for normal image.
  ReaderImageProvider(
    this.imageKey,
    this.sourceKey,
    this.cid,
    this.eid,
    this.page, {
    this.enableResize = false,
    this.decodePixelLimit = BaseImageProvider.maxImagePixel,
    this.reloadRevision = 0,
  }) : cropRevision = ReaderImageBannerCrops.revision(
         ReaderImageAddress(
           imageKey: imageKey,
           sourceKey: sourceKey,
           comicId: cid,
           chapterId: eid,
         ),
       );

  @override
  final int decodePixelLimit;
  final int cropRevision;
  final String imageKey;

  final String? sourceKey;

  final String cid;

  final String eid;

  final int page;
  final int reloadRevision;

  @override
  final bool enableResize;

  @protected
  File createLocalFile(String path) => File(path);

  @override
  bool get retryFileSystemErrors => !imageKey.startsWith('file://');

  Future<Uint8List?> _readOriginal(ReaderImageAddress address) async {
    final file =
        await CacheManager().findUnmodifiedCache(address.cacheKey) ??
        await CacheManager().findCache('${address.cacheKey}@original');
    return file?.readAsBytes();
  }

  @override
  Future<Uint8List> load(chunkEvents, checkStop) async {
    final release = ReadingActivity.instance.isReading
        ? ReaderImagePriority.instance.enter()
        : null;
    try {
      return await _loadForReader(chunkEvents, checkStop);
    } finally {
      release?.call();
    }
  }

  Future<Uint8List> _loadForReader(
    StreamController<ImageChunkEvent> chunkEvents,
    void Function() checkStop,
  ) async {
    checkStop();
    final address = ReaderImageAddress(
      imageKey: imageKey,
      sourceKey: sourceKey,
      comicId: cid,
      chapterId: eid,
    );
    final manualBands = ReaderImageBannerCrops.readBands(address);
    Uint8List? imageBytes;
    if (imageKey.startsWith('file://')) {
      final file = createLocalFile(imageKey.substring(7));
      final exists = await file.exists();
      checkStop();
      if (exists) {
        imageBytes = await readFileBytesChecked(
          file,
          requireNonEmpty: true,
          checkStop: checkStop,
          cancelSignal: BaseImageProvider.cancelSignalOf(checkStop),
          canRetry: () => BaseImageProvider.canRetryAfterFailure(checkStop),
        );
      } else {
        throw FileSystemException('File not found', file.path);
      }
    } else {
      if (manualBands != null) {
        imageBytes = await _readOriginal(address);
        checkStop();
      }
      imageBytes ??= await readImageStream(
        ImageDownloader.loadComicImage(imageKey, sourceKey, cid, eid),
        cancelSignal: BaseImageProvider.cancelSignalOf(checkStop),
        checkStop: checkStop,
        onProgress: (event) => chunkEvents.add(
          ImageChunkEvent(
            cumulativeBytesLoaded: event.currentBytes,
            expectedTotalBytes: event.totalBytes,
          ),
        ),
      );
    }
    if (manualBands != null && !imageKey.startsWith('file://')) {
      imageBytes = await _readOriginal(address);
      checkStop();
    }
    if (imageBytes == null) {
      throw OperationFailure.message(
        manualBands == null
            ? "Error: Empty response body."
            : "Original image unavailable. Reload image from source.",
      );
    }
    checkStop();
    if (manualBands != null && manualBands.isNotEmpty) {
      imageBytes = await cachedCropImageBannerBands(imageBytes, manualBands);
      checkStop();
    }
    if (manualBands == null &&
        GlobalPreferenceStore(
          appdata.settings,
        ).read(ImageProcessingPreferences.enabled)) {
      var script = GlobalPreferenceStore(
        appdata.settings,
      ).read(ImageProcessingPreferences.script);
      if (script.contains('function processImage')) {
        imageBytes = await processReaderImageBytes(
          imageBytes,
          script: script,
          comicId: cid,
          episodeId: eid,
          page: page,
          sourceKey: sourceKey,
          checkStop: checkStop,
          cancelSignal: BaseImageProvider.cancelSignalOf(checkStop),
        );
      }
    }
    return imageBytes;
  }

  @override
  Future<ReaderImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture(this);
  }

  @override
  String get key =>
      "$imageKey@$sourceKey@$cid@$eid@$enableResize@$decodePixelLimit@$reloadRevision@$cropRevision";
}
