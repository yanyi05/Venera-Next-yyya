import 'dart:async';
import 'dart:io';
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/app_runtime/smart_downloads.dart';
import 'package:venera_next/features/local_comics/local.dart';
import 'package:venera_next/features/local_comics/download_task.dart';
import 'package:venera_next/features/local_comics/smart_download_policy.dart';
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/foundation/appdata.dart';

void main() {
  testWidgets(
    'events pause/resume only automatic downloads; background and user pause are respected',
    (tester) async {
      final root = Directory.systemTemp.createTempSync('smart-runtime-');
      final checkpoint = appdata.captureImportCheckpoint();
      App.dataPath = root.path;
      final network = StreamController<List<ConnectivityResult>>.broadcast(
        sync: true,
      );
      final power = StreamController<BatteryState>.broadcast(sync: true);
      final task = _Task();
      final library = _Library(task);
      final runtime = SmartDownloadsRuntime(
        library: () => library,
        readNetwork: () async => [ConnectivityResult.wifi],
        watchNetwork: () => network.stream,
        readPower: () async => BatteryState.charging,
        watchPower: () => power.stream,
      );
      try {
        await tester.runAsync(
          () => appdata.updateSettings((draft) {
            draft['smartDownloads'] = const SmartDownloadPolicy(
              enabled: true,
            ).toJson();
          }, sync: false),
        );
        runtime.start();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        expect(task.resumes, 1);
        expect(AutomaticDownloadGate.allowed, isTrue);
        network.add([ConnectivityResult.mobile]);
        await tester.pump();
        expect(task.isPaused, isTrue);
        expect(AutomaticDownloadGate.allowed, isFalse);
        network.add([ConnectivityResult.wifi]);
        await tester.pump(const Duration(milliseconds: 250));
        expect(task.resumes, 2);
        power.add(BatteryState.discharging);
        await tester.pump();
        expect(task.isPaused, isTrue);
        await tester.runAsync(
          () => appdata.updateSettings((draft) {
            draft['smartDownloads'] = const SmartDownloadPolicy(
              enabled: true,
              power: SmartDownloadPower.anytime,
            ).toJson();
          }, sync: false),
        );
        await tester.pump(const Duration(milliseconds: 250));
        expect(task.resumes, 3);
        task.pause();
        network.add([ConnectivityResult.none]);
        network.add([ConnectivityResult.wifi]);
        await tester.pump(const Duration(milliseconds: 250));
        expect(task.resumes, 3);
        runtime.stop();
        expect(AutomaticDownloadGate.allowed, isFalse);
        network.add([ConnectivityResult.wifi]);
        await tester.pump(const Duration(seconds: 2));
        expect(task.resumes, 3);
      } finally {
        runtime.stop();
        await network.close();
        await power.close();
        await tester.runAsync(
          () => appdata.restoreImportCheckpoint(checkpoint, persist: false),
        );
        root.deleteSync(recursive: true);
      }
    },
  );
}

class _Library extends Fake implements LocalManager {
  _Library(this.task);
  final _Task task;
  final changed = ChangeNotifier();
  @override
  void addListener(VoidCallback listener) => changed.addListener(listener);
  @override
  void removeListener(VoidCallback listener) =>
      changed.removeListener(listener);
  @override
  List<DownloadTask> get downloadingTasks => [task];
  @override
  void resumeDownload(DownloadTask task) => task.resume();
  @override
  Future<void> pauseDownload(
    DownloadTask task, {
    bool automaticPolicy = false,
  }) async {
    if (automaticPolicy) {
      task.pauseForScheduling();
    } else {
      task.pause();
    }
  }
}

class _Task extends Fake implements DownloadTask {
  bool paused = true, userPaused = false;
  int resumes = 0;
  @override
  bool get isAutomatic => true;
  @override
  bool get canAutomaticallyResume => !userPaused;
  @override
  bool get isPaused => paused;
  @override
  void resume() {
    paused = false;
    resumes++;
  }

  @override
  void pause() {
    paused = true;
    userPaused = true;
  }

  @override
  void pauseForScheduling() {
    paused = true;
  }
}
