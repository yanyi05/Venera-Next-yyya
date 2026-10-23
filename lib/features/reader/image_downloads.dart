import 'dart:async';

import 'package:venera_next/foundation/log.dart';
import 'package:venera_next/network/image_http_client.dart';
import 'package:venera_next/network/image_loading_config.dart';
import 'package:venera_next/network/image_stream.dart';
import 'package:venera_next/network/images.dart';
import 'package:venera_next/network/request_scope.dart';

import 'package:venera_next/foundation/image_work.dart';

/// A view owns its subscriptions; the reading session owns their actual finish.
class ReaderImageDownloads {
  ReaderImageDownloads({
    required ImageWork work,
    this.maxConcurrent = 2,
    Stream<ImageDownloadProgress> Function(String, String?, String, String)?
    loader,
  }) : assert(maxConcurrent > 0),
       _work = work,
       _loader = loader ?? ImageDownloader.loadComicImage;

  final int maxConcurrent;
  int _running = 0;
  final ImageWork _work;
  final Stream<ImageDownloadProgress> Function(String, String?, String, String)
  _loader;
  final _pending =
      <
        (String, String?, String, String),
        ({ImageWorkTask task, RequestScope scope, Completer<void> ready})
      >{};
  Future<void>? _disposal;

  void preload(String imageKey, String? sourceKey, String cid, String eid) {
    if (_disposal != null || imageKey.startsWith('file://')) return;
    final key = (imageKey, sourceKey, cid, eid);
    if (_pending.containsKey(key)) return;
    final scope = RequestScope();
    final task = _work.start(onCancel: scope.cancel);
    if (task == null) {
      scope.dispose();
      return;
    }
    final download = (task: task, scope: scope, ready: Completer<void>());
    _pending[key] = download;
    _admitPending();
    unawaited(_download(key, download));
  }

  void _admitPending() {
    if (_disposal != null) return;
    for (final download in _pending.values) {
      if (_running >= maxConcurrent) break;
      if (download.ready.isCompleted || download.scope.isCancelled) continue;
      _running++;
      download.ready.complete();
    }
  }

  Future<void> _download(
    (String, String?, String, String) key,
    ({ImageWorkTask task, RequestScope scope, Completer<void> ready}) download,
  ) async {
    try {
      if (!download.ready.isCompleted) {
        await Future.any([download.ready.future, download.scope.whenCancelled]);
      }
      download.task.check();
      final stream = _loader(key.$1, key.$2, key.$3, key.$4);
      download.task.check();
      await readImageStream(
        stream,
        cancelSignal: download.scope.whenCancelled,
        checkStop: download.scope.check,
      );
    } on RequestCancelled {
      // Only this view's subscription is released on cancellation.
    } on ImageWorkTaskCancelled {
      // Admission can be cancelled reentrantly by an injected loader.
    } catch (error, stack) {
      if (download.task.isCancelled ||
          error is ImageStreamCleanupFailure ||
          error is ImageHttpCleanupFailure ||
          error is ImageLoadingConfigFailure ||
          error is ImageLoadingConfigCleanupFailure) {
        download.task.recordFailure(error, stack);
      } else {
        Log.error('Reader preload', error, stack);
      }
    } finally {
      download.scope.dispose();
      _pending.remove(key);
      if (download.ready.isCompleted) _running--;
      download.task.finish();
      _admitPending();
    }
  }

  Future<void> dispose() {
    if (_disposal != null) return _disposal!;
    final pending = _pending.values.toList();
    final completion = Completer<void>();
    _disposal = completion.future;
    for (final download in pending) {
      download.task.cancel();
    }
    completion.complete(
      Future.wait(pending.map((e) => e.task.done)).then((_) {}),
    );
    return completion.future;
  }
}
