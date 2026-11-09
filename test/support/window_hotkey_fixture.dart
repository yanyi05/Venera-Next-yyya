import 'dart:async';

import 'package:venera_next/foundation/window_hotkey.dart';

const firstHotkey = WindowHotkey.suggested;
const secondHotkey = WindowHotkey(
  modifiers: WindowHotkey.control | WindowHotkey.shift,
  keyCode: 0x4a,
);
const firstHotkeyConfig = WindowHotkeyConfiguration(
  enabled: true,
  hotkey: firstHotkey,
);
const secondHotkeyConfig = WindowHotkeyConfiguration(
  enabled: true,
  hotkey: secondHotkey,
);

class FakeWindowHotkeyBackend implements WindowHotkeyBackend {
  int opens = 0;
  int? owner;
  WindowHotkey? current;
  WindowHotkey? pending;
  bool suspended = false;
  WindowHotkey? conflict;
  bool failOpen = false;
  bool loseCommitResponse = false;
  bool failCommit = false;
  Completer<void>? openGate;
  final calls = <String>[];

  @override
  Future<int> open() async {
    calls.add('open');
    await openGate?.future;
    if (failOpen) throw const WindowHotkeyFailure('unavailable');
    current = pending = null;
    return owner = ++opens;
  }

  void _check(int owner) {
    if (owner != this.owner) throw const WindowHotkeyFailure('invalid_owner');
  }

  @override
  Future<void> stage(int owner, WindowHotkey? hotkey) async {
    _check(owner);
    calls.add('stage:${hotkey?.label}');
    if (hotkey != null && hotkey == conflict) {
      throw const WindowHotkeyFailure('hotkey_conflict');
    }
    pending = hotkey;
  }

  @override
  Future<void> commit(int owner) async {
    _check(owner);
    calls.add('commit');
    if (failCommit) throw const WindowHotkeyFailure('unavailable');
    current = pending;
    pending = null;
    if (loseCommitResponse) {
      loseCommitResponse = false;
      throw const WindowHotkeyFailure('transport_failed');
    }
  }

  @override
  Future<void> cancel(int owner) async {
    _check(owner);
    calls.add('cancel');
    pending = null;
  }

  @override
  Future<void> suspend(int owner, bool value) async {
    _check(owner);
    calls.add('suspend:$value');
    suspended = value;
  }

  @override
  Future<void> close(int owner) async {
    calls.add('close:$owner');
    if (owner != this.owner) return;
    current = pending = null;
    this.owner = null;
    suspended = true;
  }
}
