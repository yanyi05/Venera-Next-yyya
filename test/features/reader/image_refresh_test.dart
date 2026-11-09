import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/foundation/image_work.dart';
import 'package:venera_next/features/reader/image_refresh.dart';

class _Stream extends ImageStreamCompleter {
  int listeners = 0;
  @override
  void addListener(ImageStreamListener listener) {
    listeners++;
    super.addListener(listener);
  }

  @override
  void removeListener(ImageStreamListener listener) {
    listeners--;
    super.removeListener(listener);
  }

  void success(ui.Image image) => setImage(ImageInfo(image: image));
  void fail() => reportError(
    context: ErrorDescription('refresh'),
    exception: StateError('network failed'),
    silent: true,
  );
}

class _Provider extends ImageProvider<_Provider> {
  _Provider(this.stream);
  final _Stream stream;
  @override
  Future<_Provider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);
  @override
  void resolveStreamForKey(
    ImageConfiguration configuration,
    ImageStream stream,
    _Provider key,
    ImageErrorListener handleError,
  ) => stream.setCompleter(this.stream);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('refresh waits for a decoded frame and releases its listener', () async {
    final work = ImageWork(), stream = _Stream();
    var done = false;
    final pending = waitForRefreshedImage(
      _Provider(stream),
      ImageConfiguration.empty,
      work,
    ).then((_) => done = true);
    await pumpEventQueue();
    expect(done, isFalse);
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder);
    final picture = recorder.endRecording();
    final image = await picture.toImage(1, 1);
    picture.dispose();
    stream.success(image);
    await pending;
    expect(done, isTrue);
    expect(stream.listeners, 0);
    await work.dispose();
  });
  test(
    'network errors and reader exit do not report success or retain listener',
    () async {
      final work = ImageWork(), stream = _Stream();
      final pending = waitForRefreshedImage(
        _Provider(stream),
        ImageConfiguration.empty,
        work,
      );
      final failed = expectLater(pending, throwsStateError);
      stream.fail();
      await failed;
      expect(stream.listeners, 0);
      final next = _Stream();
      final cancelled = waitForRefreshedImage(
        _Provider(next),
        ImageConfiguration.empty,
        work,
      );
      final stopped = expectLater(
        cancelled,
        throwsA(isA<ImageWorkTaskCancelled>()),
      );
      await work.dispose();
      await stopped;
      expect(next.listeners, 0);
    },
  );
}
