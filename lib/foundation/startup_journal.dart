import 'dart:convert';
import 'dart:io';

/// Independent of settings/database recovery; contains no account or source data.
class StartupJournal {
  StartupJournal(String directory)
    : file = File('$directory/startup-state.json');
  final File file;
  static StartupJournal? current;
  bool safeMode = false;
  String? previousPhase;
  String phase = 'environment';

  void read() {
    if (!file.existsSync()) return;
    try {
      final value = jsonDecode(file.readAsStringSync());
      if (value is Map) {
        safeMode = value['safeMode'] == true;
        previousPhase = value['phase'] is String
            ? value['phase'] as String
            : null;
      }
    } catch (_) {
      // A damaged diagnostic file must never prevent application recovery.
    }
  }

  void record(String value) {
    phase = value;
    _save();
  }

  void setSafeMode(bool enabled) {
    final previous = safeMode;
    safeMode = enabled;
    try {
      _save();
    } catch (_) {
      safeMode = previous;
      rethrow;
    }
  }

  void _save() {
    file.parent.createSync(recursive: true);
    final temporary = File('${file.path}.tmp');
    temporary.writeAsStringSync(
      jsonEncode({
        'phase': phase,
        'safeMode': safeMode,
        'time': DateTime.now().toUtc().toIso8601String(),
      }),
      flush: true,
    );
    temporary.renameSync(file.path);
  }
}
