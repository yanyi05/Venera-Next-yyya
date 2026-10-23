import 'package:venera_next/foundation/reading_energy.dart';
import 'package:venera_next/foundation/reading_activity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/features/local_comics/images_download_task.dart';
import 'package:venera_next/features/local_comics/download_task_storage.dart';
import 'package:venera_next/features/local_comics/smart_download_policy.dart';
import 'package:venera_next/features/comic_source/source.dart';
import '../../support/comic_source_fixture.dart';

class _Storage extends Fake implements DownloadTaskStorage {}

void main() {
  test(
    'automatic download rechecks heat after yielding to a reader image',
    () async {
      final releaseImage = ReaderImagePriority.instance.enter();
      final policy = ReadingEnergyPolicy.instance;
      AutomaticDownloadGate.allowed = true;
      final task = ImagesDownloadTask(
        storage: _Storage(),
        source: ComicSourceFixture(key: 'thermal-race'),
        comicId: 'comic',
        automatic: true,
      );
      try {
        task.resume();
        var finished = false;
        final running = task.debugResumeFuture!.then((_) => finished = true);
        await pumpEventQueue();
        policy.update(2, false);
        releaseImage();
        await pumpEventQueue();
        expect(finished, false);
        expect(task.isError, false);
        task.pauseForScheduling();
        await running;
      } finally {
        releaseImage();
        task.dispose();
        policy.update(0, false);
        AutomaticDownloadGate.allowed = false;
      }
    },
  );

  test(
    'thermal wait is cancellable without marking automatic work user-paused',
    () async {
      final policy = ReadingEnergyPolicy.instance;
      policy.update(2, false);
      AutomaticDownloadGate.allowed = true;
      final task = ImagesDownloadTask(
        storage: _Storage(),
        source: ComicSourceFixture(key: 'thermal-task'),
        comicId: 'comic',
        automatic: true,
      );
      try {
        task.resume();
        var finished = false;
        final running = task.debugResumeFuture!.then((_) => finished = true);
        await pumpEventQueue();
        expect(finished, false);
        expect(task.isError, false);
        task.pauseForScheduling();
        await running;
        expect(task.canAutomaticallyResume, true);
        expect(task.isError, false);
      } finally {
        task.dispose();
        policy.update(0, false);
        AutomaticDownloadGate.allowed = false;
      }
    },
  );

  test(
    'paused task drains while reader priority blocks its metadata request',
    () async {
      final release = ReaderImagePriority.instance.enter();
      final task = ImagesDownloadTask(
        storage: _Storage(),
        source: ComicSourceFixture(key: 'priority-task'),
        comicId: 'comic',
      );
      try {
        task.resume();
        var finished = false;
        final running = task.debugResumeFuture!.then((_) => finished = true);
        await pumpEventQueue();
        expect(finished, isFalse);
        expect(task.isError, isFalse);
        task.pause();
        await running;
        expect(task.isPaused, isTrue);
        expect(task.isError, isFalse);
      } finally {
        task.dispose();
        release();
      }
    },
  );

  test('automatic provenance and manual pause survive task serialization', () {
    final source = ComicSourceFixture(key: 'smart-task');
    configureComicSourceRegistry(
      all: () => [source],
      find: (key) => key == source.key ? source : null,
      fromIntKey: (_) => source,
      isEmpty: () => false,
    );
    final storage = _Storage();
    final task = ImagesDownloadTask(
      storage: storage,
      source: source,
      comicId: 'comic',
      chapters: ['exact-id'],
      automatic: true,
    );
    AutomaticDownloadGate.allowed = false;
    task.resume();
    expect(task.debugResumeFuture, isNull);
    expect(task.canAutomaticallyResume, isTrue);
    task.pauseForScheduling();
    expect(task.canAutomaticallyResume, isTrue);
    task.pause();
    expect(task.canAutomaticallyResume, isFalse);
    final restored = ImagesDownloadTask.fromJson(storage, task.toJson())!;
    expect(restored.isAutomatic, isTrue);
    expect(restored.canAutomaticallyResume, isFalse);
    expect(restored.chapters, ['exact-id']);
    restored.prepareManualResume();
    expect(restored.canAutomaticallyResume, isTrue);
    restored.resume();
    expect(restored.debugResumeFuture, isNull);
    task.dispose();
    restored.dispose();
  });
}
