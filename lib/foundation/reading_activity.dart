import 'package:flutter/foundation.dart';

/// A reader holds a lease until its last local progress write has finished.
/// Background services observe this without coupling the reader to sync UI.
class ReadingActivity extends ChangeNotifier {
  ReadingActivity._();
  static final instance = ReadingActivity._();
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
