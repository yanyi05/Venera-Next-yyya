import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/foundation/res.dart';
import 'package:venera_next/foundation/sync_preference_store.dart';
import '../../support/data_sync_fixture.dart';

void main() {
  late _Clock clock;
  late SyncTestFixture fixture;
  var downloads = 0, uploads = 0;
  setUp(() {
    clock = _Clock();
    downloads = 0;
    uploads = 0;
    final implicit = <String, dynamic>{'webdavSyncMode': 'realtime'};
    fixture = SyncTestFixture(
      useV117WebDav: true,
      reliableAutomaticSync: true,
      automaticIdleInterval: const Duration(minutes: 5),
      coalesceAutomaticChecks: true,
      now: () => clock.now,
      createTimer: clock.create,
      preferences: SyncPreferenceStore(
        readSetting: (key) =>
            key == 'webdav' ? ['https://example.test', 'u', 'p'] : null,
        writeSetting: (_, _) {},
        implicitData: () => implicit,
      ),
    );
    fixture.transfer.onDownload = () async {
      downloads++;
      return const Res(false);
    };
    fixture.transfer.onUpload = () async {
      uploads++;
      return const Res(true);
    };
  });
  tearDown(() => fixture.disposeController());
  test(
    'frequent clean resume events share the same five-minute deadline',
    () async {
      fixture.controller.start();
      await clock.elapse(Duration.zero);
      expect(downloads, 1);
      for (var i = 0; i < 4; i++) {
        await clock.elapse(const Duration(minutes: 1));
        fixture.controller.checkForAutomaticSync(startup: true);
        await clock.elapse(Duration.zero);
        expect(downloads, 1);
      }
      await clock.elapse(const Duration(minutes: 1));
      expect(downloads, 2);
    },
  );
  test('local changes bypass clean idle polling delay', () async {
    fixture.controller.start();
    await clock.elapse(Duration.zero);
    await clock.elapse(const Duration(seconds: 30));
    fixture.controller.onDataChanged();
    await clock.elapse(const Duration(seconds: 10));
    expect(uploads, 1);
  });
  test(
    'background stop preserves dirty changes and catches up on restart',
    () async {
      fixture.controller.start();
      await clock.elapse(Duration.zero);
      fixture.controller.stop();
      fixture.controller.onDataChanged();
      await fixture.controller.onBackground();
      await clock.elapse(const Duration(hours: 1));
      expect(downloads, 1);
      expect(uploads, 0);
      fixture.controller.start();
      await clock.elapse(Duration.zero);
      expect(uploads, 1);
    },
  );
}

class _Clock {
  DateTime now = DateTime(2026);
  final timers = <_Timer>[];
  Timer create(Duration delay, void Function() callback) {
    final timer = _Timer(now.add(delay), callback);
    timers.add(timer);
    return timer;
  }

  Future<void> elapse(Duration delay) async {
    now = now.add(delay);
    for (final timer in timers.toList()) {
      if (timer.isActive && !timer.due.isAfter(now)) timer.fire();
    }
    await pumpEventQueue();
  }
}

class _Timer implements Timer {
  _Timer(this.due, this.callback);
  final DateTime due;
  final void Function() callback;
  @override
  bool isActive = true;
  @override
  int tick = 0;
  @override
  void cancel() => isActive = false;
  void fire() {
    isActive = false;
    tick++;
    callback();
  }
}
