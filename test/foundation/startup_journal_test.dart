import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/foundation/startup_journal.dart';

void main() {
  test(
    'phase and safe mode survive restart without touching application data',
    () {
      final root = Directory.systemTemp.createTempSync('venera-startup-');
      addTearDown(() => root.deleteSync(recursive: true));
      final existing = File('${root.path}/settings.json')
        ..writeAsStringSync('keep');
      final journal = StartupJournal(root.path)..read();
      journal.record('sources');
      journal.setSafeMode(true);
      final reopened = StartupJournal(root.path)..read();
      expect(reopened.previousPhase, 'sources');
      expect(reopened.safeMode, isTrue);
      reopened.record('ready');
      expect((StartupJournal(root.path)..read()).safeMode, isTrue);
      reopened.setSafeMode(false);
      expect((StartupJournal(root.path)..read()).safeMode, isFalse);
      expect(existing.readAsStringSync(), 'keep');
    },
  );
  test('damaged journal does not stop reading defaults', () {
    final root = Directory.systemTemp.createTempSync('venera-startup-');
    addTearDown(() => root.deleteSync(recursive: true));
    File('${root.path}/startup-state.json').writeAsStringSync('{bad');
    final journal = StartupJournal(root.path)..read();
    expect(journal.safeMode, isFalse);
    journal.record('ready');
    expect((StartupJournal(root.path)..read()).previousPhase, 'ready');
  });
  test(
    'failed recovery preference write does not change the active preference',
    () {
      final root = Directory.systemTemp.createTempSync('venera-startup-');
      addTearDown(() => root.deleteSync(recursive: true));
      final blocker = File('${root.path}/file')..writeAsStringSync('keep');
      final journal = StartupJournal(blocker.path);
      expect(
        () => journal.setSafeMode(true),
        throwsA(isA<FileSystemException>()),
      );
      expect(journal.safeMode, isFalse);
      expect(blocker.readAsStringSync(), 'keep');
    },
  );
}
