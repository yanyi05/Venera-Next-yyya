import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';

/// System pressure pauses speculative work without releasing visible images.
class ReaderResourceBudget extends ChangeNotifier {
  ReaderResourceBudget({required this.mobile});
  final bool mobile;
  bool _foreground = true;
  Timer? _pressure;
  bool get constrained => !_foreground || _pressure != null;
  int? get cacheBytes => constrained
      ? 32 << 20
      : mobile
      ? 128 << 20
      : null;
  int preloadCount(int configured) =>
      constrained ? 0 : configured.clamp(0, mobile ? 6 : 32);
  void setForeground(bool value) {
    if (_foreground == value) return;
    _foreground = value;
    notifyListeners();
  }

  void memoryPressure() {
    _pressure?.cancel();
    _pressure = Timer(const Duration(minutes: 1), () {
      _pressure = null;
      notifyListeners();
    });
    notifyListeners();
  }

  @override
  void dispose() {
    _pressure?.cancel();
    super.dispose();
  }
}

/// Prefer the direction being read; reduce speculation after a rapid jump.
class ReaderPreloadPlan {
  int? _previous;
  DateTime? _time;
  DateTime? _rapidUntil;
  int _direction = 1;
  Iterable<int> pages(
    int current,
    int count,
    int maximum, {
    DateTime? now,
  }) sync* {
    now ??= DateTime.now();
    final previous = _previous;
    if (previous != null && current != previous) {
      _direction = (current - previous).sign;
    }
    final rapid =
        previous != null &&
        (current - previous).abs() >= 3 &&
        _time != null &&
        now.difference(_time!).inMilliseconds < 250;
    if (rapid) {
      _rapidUntil = now.add(const Duration(milliseconds: 500));
    }
    _previous = current;
    _time = now;
    if (count <= 0) return;
    final limit = _rapidUntil != null && now.isBefore(_rapidUntil!)
        ? math.min(count, 1)
        : count;
    for (var step = 1; step <= limit; step++) {
      final page = current + step * _direction;
      if (page > 0 && page <= maximum) yield page;
    }
    final behind = current - _direction;
    if (behind > 0 && behind <= maximum) yield behind;
  }
}
