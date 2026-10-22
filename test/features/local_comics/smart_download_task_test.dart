import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/features/local_comics/images_download_task.dart';
import 'package:venera_next/features/local_comics/download_task_storage.dart';
import 'package:venera_next/features/local_comics/smart_download_policy.dart';
import 'package:venera_next/features/comic_source/source.dart';
import '../../support/comic_source_fixture.dart';

class _Storage extends Fake implements DownloadTaskStorage {}

void main() {
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
