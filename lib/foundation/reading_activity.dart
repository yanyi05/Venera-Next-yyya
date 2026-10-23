import 'package:flutter/foundation.dart';
import 'dart:async';

/// A reader holds a lease until its last local progress write has finished.
/// Background services observe this without coupling the reader to sync UI.
class ReadingActivity extends ChangeNotifier {
  ReadingActivity._();
  static final instance = ReadingActivity._();
  final _maintenance = <Future<void>>{};
  bool get hasMaintenance => _maintenance.isNotEmpty;
  Future<T> runMaintenance<T>(Future<T> Function() action) async {
    if (isReading) throw StateError('Reading is active');
    final done = Completer<void>();
    _maintenance.add(done.future);
    try {
      return await action();
    } finally {
      _maintenance.remove(done.future);
      done.complete();
    }
  }

  Future<void> waitForMaintenance() async {
    while (_maintenance.isNotEmpty) {
      await Future.wait(_maintenance.toList());
    }
  }

  int _readers = 0;
  bool get isReading => _readers > 0;

  VoidCallback enter() {
    if (_readers++ == 0) notifyListeners();
    var released = false;
    return () {
      if (released) return;
      released = true;
      if (--_readers == 0) notifyListeners();
    };
  }
}

/// Admission gate for background work while reader images are loading.
/// A lease covers file/cache reads and image processing, including failures.
class ReaderImagePriority {
  static final instance = ReaderImagePriority();
  int _active = 0;
  bool get hasPendingImages => _active > 0;
  Completer<void>? _idle;

  VoidCallback enter() {
    if (_active++ == 0) _idle = Completer<void>();
    var released = false;
    return () {
      if (released) return;
      released = true;
      if (--_active == 0) {
        _idle!.complete();
        _idle = null;
      }
    };
  }

  /// False means the waiting download was stopped. No polling or timer.
  Future<bool> waitUntilIdle(Future<void> cancelled) async {
    final stopped = cancelled.then((_) => false);
    while (_active > 0) {
      if (!await Future.any([_idle!.future.then((_) => true), stopped])) {
        return false;
      }
    }
    return true;
  }
}
