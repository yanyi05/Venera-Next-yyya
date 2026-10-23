import 'package:venera_next/foundation/reading_energy.dart';
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
    ReadingEnergyPolicy? energyPolicy,
    Stream<ImageDownloadProgress> Function(String, String?, String, String)?
    loader,
  }) : assert(maxConcurrent > 0),
       _work = work,
       _loader = loader ?? ImageDownloader.loadComicImage,
       _energy = energyPolicy ?? ReadingEnergyPolicy.instance {
    _energy.addListener(_admitPending);
  }

  final ReadingEnergyPolicy _energy;
  Set<(String, String?, String, String)> _window = {};
  final _windowCompleted = <(String, String?, String, String)>{};

  /// Cancel only obsolete queued work. Already-started/shared transfers finish.
  void preloadWindow(Iterable<(String, String?, String, String)> images) {
    if (_disposal != null) return;
    _window = images.where((key) => !key.$1.startsWith('file://')).toSet();
    _windowCompleted.retainAll(_window);
    for (final entry in _pending.entries) {
      if (!_window.contains(entry.key) && !entry.value.ready.isCompleted) {
        entry.value.task.cancel();
      }
    }
    for (final key in _window) {
      if (!_windowCompleted.contains(key)) {
        preload(key.$1, key.$2, key.$3, key.$4);
      }
    }
  }

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
    final limit = _energy.prefetchConcurrency < maxConcurrent
        ? _energy.prefetchConcurrency
        : maxConcurrent;
    for (final download in _pending.values) {
      if (_running >= limit) break;
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
      final bytes = await readImageStream(
        stream,
        cancelSignal: download.scope.whenCancelled,
        checkStop: download.scope.check,
      );
      if (bytes != null && _window.contains(key)) _windowCompleted.add(key);
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
      if (download.task.isCancelled &&
          _window.contains(key) &&
          _disposal == null) {
        scheduleMicrotask(() {
          if (_disposal == null && _window.contains(key)) {
            preload(key.$1, key.$2, key.$3, key.$4);
          }
        });
      }
    }
  }

  Future<void> dispose() {
    if (_disposal != null) return _disposal!;
    _energy.removeListener(_admitPending);
    _window.clear();
    _windowCompleted.clear();
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
