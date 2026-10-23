import 'dart:async';
import 'package:venera_next/foundation/reading_activity.dart';
import 'package:venera_next/features/sync/data_sync_controller.dart';
import 'webdav_library.dart';

/// The mounted application owns automatic sync scheduling, not transfer data.
class BackgroundSync {
  BackgroundSync({
    required this.startDataSync,
    required this.stopDataSync,
    required this.checkLibrary,
    this.readingActivity,
  });

  factory BackgroundSync.platform(DataSyncController sync) {
    return BackgroundSync(
      readingActivity: ReadingActivity.instance,
      startDataSync: sync.start,
      stopDataSync: sync.stop,
      checkLibrary: webDavLibrary.source.synchronizer.checkForAutomaticSync,
    );
  }

  final void Function() startDataSync;
  final void Function() stopDataSync;
  final void Function() checkLibrary;
  final ReadingActivity? readingActivity;
  Timer? _libraryTimer;
  Timer? _afterReading;
  void _checkLibraryIfIdle() {
    if (readingActivity?.isReading != true) checkLibrary();
  }

  void _readingChanged() {
    _afterReading?.cancel();
    _afterReading = null;
    if (_running && readingActivity?.isReading != true) {
      final generation = _generation;
      _afterReading = Timer(const Duration(seconds: 2), () {
        _afterReading = null;
        if (_running && _generation == generation) _checkLibraryIfIdle();
      });
    }
  }

  bool _running = false;
  int _generation = 0;

  void start() {
    if (_running) return;
    _running = true;
    final generation = ++_generation;
    readingActivity?.addListener(_readingChanged);
    try {
      startDataSync();
      _checkLibraryIfIdle();
      if (!_running || generation != _generation) return;
      _libraryTimer = Timer.periodic(const Duration(minutes: 15), (_) {
        if (_running && generation == _generation) _checkLibraryIfIdle();
      });
    } catch (_) {
      stop();
      rethrow;
    }
  }

  void stop() {
    if (!_running) return;
    _running = false;
    readingActivity?.removeListener(_readingChanged);
    _afterReading?.cancel();
    _afterReading = null;
    _generation++;
    _libraryTimer?.cancel();
    _libraryTimer = null;
    stopDataSync();
  }
}
