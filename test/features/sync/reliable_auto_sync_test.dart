import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/foundation/log.dart';
import 'package:venera_next/foundation/res.dart';
import 'package:venera_next/foundation/sync_preference_store.dart';
import '../../support/data_sync_fixture.dart';

void main() {
  late _Clock clock;
  late Map<String, dynamic> implicit;
  late SyncTestFixture f;
  setUp(() {
    Log.isMuted = true;
    clock = _Clock();
    implicit = {'webdavSyncMode': 'realtime'};
    f = SyncTestFixture(
      useV117WebDav: true,
      reliableAutomaticSync: true,
      preferences: SyncPreferenceStore(
        readSetting: (k) =>
            k == 'webdav' ? ['https://example.test', 'u', 'p'] : null,
        writeSetting: (_, _) {},
        implicitData: () => implicit,
      ),
      now: () => clock.now,
      createTimer: clock.create,
    );
  });
  tearDown(() {
    f.disposeController();
    Log.isMuted = false;
  });

  test(
    'reading holds sync until final local progress is saved and the lease is released',
    () async {
      var uploads = 0;
      var downloads = 0;
      f.transfer.onUpload = () async {
        uploads++;
        return const Res(true);
      };
      f.transfer.onDownload = () async {
        downloads++;
        return const Res(false);
      };
      final sync = f.controller
        ..setReadingActive(true)
        ..start();
      sync.onDataChanged();
      await clock.elapse(const Duration(minutes: 2));
      expect(uploads + downloads, 0);
      expect(sync.hasPendingChanges, isTrue);
      sync.setReadingActive(false);
      await clock.elapse(const Duration(seconds: 2));
      expect(uploads, 1);
    },
  );

  test(
    'continuous page changes upload within ten seconds, without one request per page',
    () async {
      var uploads = 0;
      f.transfer.onUpload = () async {
        uploads++;
        return const Res(true);
      };
      final sync = f.controller..start();
      await clock.elapse(Duration.zero);
      for (var second = 0; second < 10; second++) {
        for (var page = 0; page < 10; page++) {
          sync.onDataChanged();
        }
        await clock.elapse(const Duration(seconds: 1));
      }
      expect(uploads, 1);
      expect(sync.hasPendingChanges, isFalse);
    },
  );

  test(
    'failed automatic transfer retries while the app remains open',
    () async {
      var downloads = 0;
      f.transfer.onDownload = () async {
        downloads++;
        return downloads == 1 ? const Res.error('offline') : const Res(false);
      };
      f.controller.start();
      await clock.elapse(Duration.zero);
      expect(downloads, 1);
      await clock.elapse(const Duration(seconds: 9));
      expect(downloads, 1);
      await clock.elapse(const Duration(seconds: 1));
      expect(downloads, 2);
      expect(f.controller.lastError, isNull);
    },
  );

  test(
    'edits during upload remain pending and receive a second upload',
    () async {
      final gate = Completer<Res<bool>>();
      var uploads = 0;
      f.transfer.onUpload = () {
        uploads++;
        return uploads == 1 ? gate.future : Future.value(const Res(true));
      };
      final sync = f.controller..start();
      await clock.elapse(Duration.zero);
      sync.onDataChanged();
      await clock.elapse(const Duration(seconds: 10));
      expect(uploads, 1);
      sync.onDataChanged();
      gate.complete(const Res(true));
      await clock.elapse(Duration.zero);
      expect(sync.hasPendingChanges, isTrue);
      await clock.elapse(const Duration(seconds: 10));
      expect(uploads, 2);
      expect(sync.hasPendingChanges, isFalse);
    },
  );

  test('idle foreground polls and resume checks immediately', () async {
    var downloads = 0;
    f.transfer.onDownload = () async {
      downloads++;
      return const Res(false);
    };
    final sync = f.controller..start();
    await clock.elapse(Duration.zero);
    await clock.elapse(const Duration(seconds: 60));
    expect(downloads, 2);
    sync.checkForAutomaticSync(startup: true);
    await clock.elapse(Duration.zero);
    expect(downloads, 3);
    sync.stop();
    await clock.elapse(const Duration(hours: 1));
    expect(downloads, 3);
  });

  test(
    'manual mode persists dirty state without automatically contacting server',
    () async {
      implicit['webdavSyncMode'] = 'manual';
      var calls = 0;
      f.transfer.onUpload = () async {
        calls++;
        return const Res(true);
      };
      f.transfer.onDownload = () async {
        calls++;
        return const Res(false);
      };
      final sync = f.controller..start();
      sync.onDataChanged();
      await sync.onBackground();
      await clock.elapse(const Duration(hours: 1));
      expect(sync.hasPendingChanges, isTrue);
      expect(calls, 0);
    },
  );
}

class _Clock {
  DateTime now = DateTime(2026);
  final timers = <_Timer>[];
  Timer create(Duration delay, void Function() callback) {
    final t = _Timer(now.add(delay), callback);
    timers.add(t);
    return t;
  }

  Future<void> elapse(Duration delay) async {
    now = now.add(delay);
    for (final t in timers.toList()) {
      if (t.isActive && !t.due.isAfter(now)) t.fire();
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
  void cancel() {
    isActive = false;
  }

  void fire() {
    isActive = false;
    tick++;
    callback();
  }
}
