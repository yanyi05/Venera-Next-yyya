import 'package:venera_next/foundation/image_provider/base_image_provider.dart';
import 'dart:async';

import 'package:flutter/painting.dart';
import 'package:venera_next/foundation/image_work.dart';

/// Wait for a decoded frame, releasing our subscription on success, error or exit.
Future<void> waitForRefreshedImage(
  ImageProvider provider,
  ImageConfiguration configuration,
  ImageWork work,
) async {
  final completion = Completer<void>();
  final task = work.start(
    onCancel: () {
      if (!completion.isCompleted) {
        completion.completeError(const ImageWorkTaskCancelled());
      }
    },
  );
  if (task == null) throw const ImageWorkTaskCancelled();
  ImageStream? stream;
  ImageStreamListener? listener;
  try {
    task.check();
    stream = provider.resolve(configuration);
    listener = ImageStreamListener(
      (info, _) {
        info.dispose();
        if (!completion.isCompleted) completion.complete();
      },
      onError: (Object error, StackTrace? stack) {
        if (!completion.isCompleted) completion.completeError(error, stack);
      },
    );
    stream.addListener(listener);
    await completion.future;
    task.check();
  } finally {
    try {
      if (task.isCancelled && stream != null) {
        final key = await provider.obtainKey(configuration);
        final cache = PaintingBinding.instance.imageCache;
        if (cache.statusForKey(key).pending) {
          final pending = cache.putIfAbsent(
            key,
            () => throw StateError('Refresh stream disappeared'),
          );
          if (identical(pending, stream.completer)) {
            cache.evict(key, includeLive: false);
          }
        }
      }
      if (listener != null) stream?.removeListener(listener);
      if (stream != null) await BaseImageProvider.waitForReleasedStream(stream);
    } catch (error, stack) {
      task.recordFailure(error, stack);
      rethrow;
    } finally {
      task.finish();
    }
  }
}
