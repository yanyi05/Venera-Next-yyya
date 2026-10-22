import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:rhttp/rhttp.dart';
import 'package:venera_next/foundation/operation_failure.dart';

/// One run owns its retry timers. Connectivity events shorten a wait, but never
/// reset the attempt budget or restart a paused/cancelled run.
class DownloadRetry {
  DownloadRetry({required this.isActive, required this.onWaitingChanged});

  final bool Function() isActive;
  final void Function() onWaitingChanged;
  static const delays = [
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 20),
    Duration(seconds: 30),
    Duration(seconds: 60),
  ];

  final _waits = <Completer<void>, Timer>{};
  bool _cancelled = false;

  bool get isWaiting => _waits.isNotEmpty;

  void wake() {
    for (final entry in _waits.entries.toList()) {
      entry.value.cancel();
      if (!entry.key.isCompleted) entry.key.complete();
    }
  }

  void cancel() {
    _cancelled = true;
    wake();
  }

  void _checkActive() {
    if (_cancelled || !isActive()) {
      throw OperationFailure.message('Canceled', kind: FailureKind.cancelled);
    }
  }

  Future<T> run<T>(
    Future<T> Function() action, {
    bool retryUnknown = false,
  }) async {
    for (var attempt = 0; ; attempt++) {
      _checkActive();
      try {
        return await action();
      } catch (error) {
        _checkActive();
        final kind = _classify(error);
        final Duration? delay;
        if (kind == _Failure.connection) {
          delay = attempt < delays.length
              ? downloadRetryAfter(error) ?? delays[attempt]
              : null;
        } else if (kind == _Failure.unknown && retryUnknown && attempt < 2) {
          // Legacy source scripts can return untyped messages. Keep their
          // short retries without treating arbitrary strings as a disconnect.
          delay = Duration(seconds: attempt + 1);
        } else {
          delay = null;
        }
        if (delay == null) rethrow;
        final done = Completer<void>();
        _waits[done] = Timer(delay, done.complete);
        onWaitingChanged();
        try {
          await done.future;
        } finally {
          _waits.remove(done)?.cancel();
          onWaitingChanged();
        }
      }
    }
  }
}

enum _Failure { connection, terminal, unknown }

_Failure _classify(Object error, [int depth = 0]) {
  if (depth > 8) return _Failure.terminal;
  if (error is FailureDetails) {
    if (error.kind != FailureKind.failed) return _Failure.terminal;
    final cause = error.cause;
    return cause == null ? _Failure.unknown : _classify(cause, depth + 1);
  }
  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return _Failure.connection;
      case DioExceptionType.connectionError:
        final cause = error.error;
        return cause != null && _classify(cause, depth + 1) == _Failure.terminal
            ? _Failure.terminal
            : _Failure.connection;
      case DioExceptionType.unknown:
        final cause = error.error;
        return cause == null ? _Failure.unknown : _classify(cause, depth + 1);
      case DioExceptionType.badCertificate:
      case DioExceptionType.transformTimeout:
      case DioExceptionType.badResponse:
        return const [429, 503].contains(error.response?.statusCode)
            ? _Failure.connection
            : _Failure.terminal;
      case DioExceptionType.cancel:
        return _Failure.terminal;
    }
  }
  if (error is SocketException ||
      error is TimeoutException ||
      error is RhttpConnectionException ||
      error is RhttpTimeoutException) {
    return _Failure.connection;
  }
  if (error is RhttpInterceptorException) {
    return _classify(error.error, depth + 1);
  }
  if (error is RhttpException ||
      error is FileSystemException ||
      error is TlsException ||
      error is Error) {
    return _Failure.terminal;
  }
  return _Failure.unknown;
}

/// A bounded Retry-After wait for throttling/unavailability; authentication and
/// challenge failures remain terminal and never enter this retry loop.
Duration? downloadRetryAfter(Object error, {DateTime? now}) {
  Object? current = error;
  for (var depth = 0; depth < 8; depth++) {
    if (current is FailureDetails) {
      current = current.cause;
      continue;
    }
    if (current is! DioException ||
        !const [429, 503].contains(current.response?.statusCode)) {
      return null;
    }
    final value = current.response?.headers.value('retry-after');
    if (value == null) return null;
    var seconds = int.tryParse(value);
    if (seconds == null) {
      try {
        seconds = HttpDate.parse(
          value,
        ).difference(now ?? DateTime.now().toUtc()).inSeconds;
      } catch (_) {
        return null;
      }
    }
    return Duration(seconds: seconds.clamp(1, 300));
  }
  return null;
}
