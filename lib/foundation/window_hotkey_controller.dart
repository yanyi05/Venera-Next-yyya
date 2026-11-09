import 'dart:async';

import 'package:flutter/foundation.dart';

import 'window_hotkey.dart';

/// The old registration stays reserved until the new preference is durable.
class WindowHotkeyController extends ChangeNotifier {
  WindowHotkeyController({
    required this.backend,
    required this.load,
    required this.persist,
    this.ready,
    this.onError,
  });

  final WindowHotkeyBackend backend;
  final WindowHotkeyConfiguration Function() load;
  final Future<void> Function(
    WindowHotkeyConfiguration next,
    WindowHotkeyConfiguration previous,
  )
  persist;
  final Future<void>? ready;
  final void Function(Object error, StackTrace stack)? onError;
  WindowHotkeyConfiguration configuration = const WindowHotkeyConfiguration();
  WindowHotkeyFailure? error;
  bool initialized = false;
  bool registered = false;
  bool busy = false;
  bool _closed = false;
  int? _owner;
  Future<void>? _starting;
  Future<void>? _closing;
  Future<void> _queue = Future.value();
  final _holds = <Object>{};

  bool get isClosed => _closed;

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<int> _open() async {
    final owner = await backend.open();
    if (owner <= 0) throw const WindowHotkeyFailure('invalid_owner');
    _owner = owner;
    await backend.suspend(owner, _closed || _holds.isNotEmpty);
    return owner;
  }

  // Interrupt dispatch now, even while the mutation queue is persisting a save.
  Future<void>? _suspendNow() {
    final owner = _owner;
    if (owner == null) return null;
    final result = Future<void>.sync(() => backend.suspend(owner, true));
    unawaited(result.then<void>((_) {}, onError: (Object _, StackTrace _) {}));
    return result;
  }

  Future<void> start() => _starting ??= _enqueue(() async {
    if (_closed) return;
    try {
      await ready;
      if (_closed) return;
      configuration = load();
      final owner = await _open();
      if (!_closed && configuration.enabled) {
        await backend.stage(owner, configuration.hotkey);
        await backend.commit(owner);
        registered = true;
      }
    } catch (failure, stack) {
      final owner = _owner;
      if (owner != null) {
        try {
          await backend.close(owner);
          _owner = null;
        } catch (cleanup, cleanupStack) {
          onError?.call(cleanup, cleanupStack);
        }
      }
      error = failure is WindowHotkeyFailure
          ? failure
          : WindowHotkeyFailure('hotkey_registration_failed', failure);
      onError?.call(failure, stack);
    } finally {
      initialized = true;
      notifyListeners();
    }
  });

  Future<void> configure(WindowHotkeyConfiguration next) {
    if (_closed) return Future.error(StateError('Hotkey controller is closed'));
    if ((next.enabled && next.hotkey == null) ||
        (next.hotkey != null && !next.hotkey!.isValid)) {
      return Future.error(const WindowHotkeyFailure('invalid_hotkey'));
    }
    final starting = start();
    return _enqueue(() async {
      await starting;
      busy = true;
      error = null;
      notifyListeners();
      final previous = configuration;
      var persisted = false;
      var staged = false;
      var committing = false;
      int? owner;
      try {
        owner = _owner ?? await _open();
        // Disabling must not let an in-flight key hide its own recovery UI.
        await backend.suspend(owner, true);
        await backend.stage(owner, next.enabled ? next.hotkey : null);
        staged = true;
        await persist(next, previous);
        persisted = true;
        committing = true;
        await backend.commit(owner);
        await backend.suspend(owner, _closed || _holds.isNotEmpty);
        configuration = next;
        registered = next.enabled;
      } catch (failure, stack) {
        try {
          if (staged && owner != null) await backend.cancel(owner);
          // A lost commit response may already have replaced the registration.
          if (committing && owner != null) {
            try {
              await backend.stage(
                owner,
                previous.enabled ? previous.hotkey : null,
              );
              await backend.commit(owner);
              await backend.suspend(owner, _closed || _holds.isNotEmpty);
              registered = previous.enabled;
            } catch (_) {
              registered = false;
              await backend.close(owner);
              _owner = null;
              rethrow;
            }
          }
          final activeOwner = _owner;
          if (activeOwner != null) {
            await backend.suspend(activeOwner, _closed || _holds.isNotEmpty);
          }
        } catch (rollback, rollbackStack) {
          error = WindowHotkeyFailure('hotkey_save_failed', rollback);
          onError?.call(rollback, rollbackStack);
        }
        try {
          if (persisted) await persist(previous, next);
        } catch (rollback, rollbackStack) {
          error = WindowHotkeyFailure('hotkey_save_failed', rollback);
          onError?.call(rollback, rollbackStack);
        }
        error ??= failure is WindowHotkeyFailure
            ? failure
            : WindowHotkeyFailure('hotkey_registration_failed', failure);
        onError?.call(failure, stack);
        throw error!;
      } finally {
        busy = false;
        notifyListeners();
      }
    });
  }

  /// Recording and reversible exit preparation can overlap independently.
  Future<void Function()> hold() {
    if (_closed) return Future.error(StateError('Hotkey controller is closed'));
    final token = Object();
    _holds.add(token);
    final suspension = _suspendNow();
    final starting = start();
    return _enqueue(() async {
      await starting;
      final owner = _owner;
      try {
        await suspension;
        if (owner != null) await backend.suspend(owner, true);
      } catch (_) {
        _holds.remove(token);
        rethrow;
      }
      var released = false;
      return () {
        if (released) return;
        released = true;
        _holds.remove(token);
        if (_closed) return;
        unawaited(
          _enqueue(() async {
            final owner = _owner;
            if (!_closed && owner != null) {
              await backend.suspend(owner, _holds.isNotEmpty);
            }
          }).catchError((Object failure, StackTrace stack) {
            error = WindowHotkeyFailure('hotkey_registration_failed', failure);
            onError?.call(failure, stack);
            notifyListeners();
          }),
        );
      };
    });
  }

  Future<void> close() {
    if (_closing != null) return _closing!;
    _closed = true;
    final suspension = _suspendNow();
    return _closing ??= _enqueue(() async {
      try {
        await suspension;
      } finally {
        final owner = _owner;
        _owner = null;
        registered = false;
        if (owner != null) await backend.close(owner);
      }
    });
  }
}

/// Mount replacement waits for accepted saves and native unregister to drain.
class WindowHotkeyHost {
  WindowHotkeyHost(this.create);
  final WindowHotkeyController Function(Future<void> ready) create;
  WindowHotkeyController? _current;
  Future<void> _handoff = Future.value();

  WindowHotkeyController attach() {
    final previous = _current;
    if (previous != null) {
      _handoff = Future.wait<void>([_handoff, previous.close()]);
      unawaited(
        _handoff.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      );
    }
    return _current = create(_handoff);
  }
}
