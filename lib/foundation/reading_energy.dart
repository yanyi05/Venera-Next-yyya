import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// iOS reports a thermal category, not a temperature measurement.
class ReadingEnergyPolicy extends ChangeNotifier {
  static final instance = ReadingEnergyPolicy();
  int _thermal = 0;
  bool _lowPower = false;
  Completer<void>? _ready;
  int get thermal => _thermal;
  bool get lowPower => _lowPower;
  bool get deferAutomaticDownloads => _thermal >= 2 || _lowPower;
  int get prefetchConcurrency =>
      _thermal >= 2 ? 0 : (_thermal == 1 || _lowPower ? 1 : 2);

  void update(int thermal, bool lowPower) {
    if (thermal < 0 || thermal > 3) return;
    if (_thermal == thermal && _lowPower == lowPower) return;
    final deferred = deferAutomaticDownloads;
    _thermal = thermal;
    _lowPower = lowPower;
    if (deferAutomaticDownloads && !deferred) _ready = Completer<void>();
    if (!deferAutomaticDownloads && deferred) {
      _ready?.complete();
      _ready = null;
    }
    notifyListeners();
  }

  Future<bool> waitForAutomaticDownloads(Future<void> cancelled) async {
    final stopped = cancelled.then((_) => false);
    while (deferAutomaticDownloads) {
      if (!await Future.any([_ready!.future.then((_) => true), stopped])) {
        return false;
      }
    }
    return true;
  }
}

/// Shared across reader routes. Only system events wake this monitor.
class ReadingEnergyMonitor {
  ReadingEnergyMonitor({
    required this.watch,
    required this.policy,
    required this.onError,
  });
  static final platform = ReadingEnergyMonitor(
    watch: () =>
        const EventChannel('venera/reader_energy').receiveBroadcastStream(),
    policy: ReadingEnergyPolicy.instance,
    onError: (_, _) {},
  );
  final Stream<Object?> Function() watch;
  final ReadingEnergyPolicy policy;
  final void Function(Object, StackTrace) onError;
  StreamSubscription<Object?>? _subscription;
  int _leases = 0;
  int _generation = 0;

  Future<void> Function() acquire() {
    if (_leases++ == 0) {
      final generation = ++_generation;
      try {
        _subscription = watch().listen(
          (value) {
            if (generation != _generation || _leases == 0 || value is! Map) {
              return;
            }
            final thermal = value['thermal'];
            final lowPower = value['lowPower'];
            if (thermal is int && lowPower is bool) {
              policy.update(thermal, lowPower);
            }
          },
          onError: (Object error, StackTrace stack) {
            if (generation != _generation) return;
            policy.update(0, false);
            onError(error, stack);
          },
          onDone: () {
            if (generation == _generation) policy.update(0, false);
          },
        );
      } catch (error, stack) {
        onError(error, stack);
      }
    }
    Future<void>? closing;
    return () => closing ??= _release();
  }

  Future<void> _release() async {
    if (--_leases != 0) return;
    ++_generation;
    final subscription = _subscription;
    _subscription = null;
    policy.update(0, false);
    try {
      await subscription?.cancel();
    } catch (error, stack) {
      onError(error, stack);
    }
  }
}
