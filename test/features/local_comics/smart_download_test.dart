import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/features/local_comics/smart_download_policy.dart';
import 'package:venera_next/features/local_comics/download_queue.dart';
import 'package:venera_next/features/local_comics/download_task.dart';
import 'package:venera_next/features/local_comics/local_comic_model.dart';
import 'package:venera_next/foundation/comic_type.dart';

void main() {
  test('default is off; unknown network/power fail closed', () {
    expect(SmartDownloadPolicy.fromJson(null).enabled, isFalse);
    final policy = SmartDownloadPolicy.fromJson({
      'enabled': true,
      'ahead': 'invalid',
    });
    expect(policy.ahead, 3);
    expect(
      policy.allows(foreground: true, transports: {}, charging: true),
      isFalse,
    );
    expect(
      policy.allows(
        foreground: true,
        transports: {SmartDownloadTransport.wifi},
        charging: null,
      ),
      isFalse,
    );
  });
  for (final network in SmartDownloadNetwork.values) {
    for (final power in SmartDownloadPower.values) {
      test('network and power are independent: $network / $power', () {
        final policy = SmartDownloadPolicy(
          enabled: true,
          network: network,
          power: power,
        );
        expect(
          policy.allows(
            foreground: true,
            transports: {SmartDownloadTransport.wifi},
            charging: true,
          ),
          isTrue,
        );
        expect(
          policy.allows(
            foreground: true,
            transports: {SmartDownloadTransport.mobile},
            charging: true,
          ),
          network == SmartDownloadNetwork.wifiAndMobile,
        );
        expect(
          policy.allows(
            foreground: true,
            transports: {SmartDownloadTransport.wifi},
            charging: false,
          ),
          power == SmartDownloadPower.anytime,
        );
        expect(
          policy.allows(
            foreground: false,
            transports: {SmartDownloadTransport.wifi},
            charging: true,
          ),
          isFalse,
        );
      });
    }
  }
  test('only the upcoming window is downloaded, by source ID', () {
    const policy = SmartDownloadPolicy(enabled: true, ahead: 3);
    expect(
      policy.plan(
        chapters: ['a', 'b', 'extra', 'c', 'd', 'e'],
        current: 'b',
        downloaded: {'c'},
      ),
      ['extra', 'd'],
    );
    expect(
      policy.plan(chapters: ['a', 'b'], current: 'missing', downloaded: {}),
      isEmpty,
    );
    expect(
      policy.plan(chapters: ['a', 'b'], current: 'b', downloaded: {}),
      isEmpty,
    );
  });
  test(
    'a manual download preempts automatic work after draining cleanup',
    () async {
      final events = <String>[];
      final queue = DownloadQueue(
        commitComic: (_) {},
        notifyChanged: () {},
        requestSave: () {},
        reportError: (_, _) {},
      );
      final cleanup = Completer<void>();
      final auto = _Task('auto', events, automatic: true)
        ..cleanup = cleanup.future;
      final manual = _Task('manual', events);
      queue.add(auto);
      queue.add(manual);
      expect(queue.tasks.first, manual);
      expect(auto.manualPaused, isFalse);
      expect(events, isNot(contains('resume:manual')));
      cleanup.complete();
      await pumpEventQueue();
      expect(events.last, 'resume:manual');
    },
  );
  test(
    'adding automatic work never resumes a manually paused download',
    () async {
      final events = <String>[];
      final queue = DownloadQueue(
        commitComic: (_) {},
        notifyChanged: () {},
        requestSave: () {},
        reportError: (_, _) {},
      );
      final manual = _Task('manual', events);
      queue.add(manual);
      await queue.pause(manual);
      events.clear();
      queue.add(_Task('auto', events, automatic: true));
      expect(events, isEmpty);
      expect(manual.isPaused, isTrue);
    },
  );
  test(
    'adding automatic work preserves an already pending manual start',
    () async {
      final events = <String>[];
      final queue = DownloadQueue(
        commitComic: (_) {},
        notifyChanged: () {},
        requestSave: () {},
        reportError: (_, _) {},
      );
      final gate = Completer<void>();
      final first = _Task('first', events)..cleanup = gate.future;
      final next = _Task('next', events);
      queue.add(first);
      queue.add(next);
      final moving = queue.moveToFirst(next);
      queue.add(_Task('auto', events, automatic: true));
      events.clear();
      gate.complete();
      await moving;
      await pumpEventQueue();
      expect(queue.tasks.first, next);
      expect(events, ['resume:next']);
    },
  );
}

class _Task extends DownloadTask {
  _Task(this.id, this.events, {this.automatic = false});
  @override
  final String id;
  final List<String> events;
  final bool automatic;
  bool paused = true, manualPaused = false;
  Future<void> cleanup = Future.value();
  @override
  bool get isAutomatic => automatic;
  @override
  bool get canAutomaticallyResume => automatic && !manualPaused;
  @override
  Future<void> get pendingCleanup => cleanup;
  @override
  void pause() {
    paused = true;
    manualPaused = true;
    events.add('pause:$id');
  }

  @override
  void pauseForScheduling() {
    final old = manualPaused;
    pause();
    manualPaused = old;
  }

  @override
  void prepareManualResume() {
    manualPaused = false;
  }

  @override
  void resume() {
    paused = false;
    events.add('resume:$id');
  }

  @override
  bool get isPaused => paused;
  @override
  bool get isError => false;
  @override
  ComicType get comicType => const ComicType(1);
  @override
  String get title => id;
  @override
  String? get cover => null;
  @override
  String get message => '';
  @override
  int get speed => 0;
  @override
  double get progress => 0;
  @override
  void cancel() {}
  @override
  Map<String, dynamic> toJson() => {};
  @override
  LocalComic toLocalComic() => throw UnimplementedError();
}
