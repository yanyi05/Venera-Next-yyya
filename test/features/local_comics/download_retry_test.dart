import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rhttp/rhttp.dart' as rhttp;
import 'package:venera_next/features/local_comics/download_retry.dart';
import 'package:venera_next/foundation/operation_failure.dart';

void main() {
  test(
    'skip policy excludes authentication, TLS, cancellation and local storage',
    () {
      for (final status in [401, 403, 404, 410, 429, 500]) {
        final request = RequestOptions(path: '/page');
        expect(
          canSkipUnavailableDownloadImage(
            DioException.badResponse(
              statusCode: status,
              requestOptions: request,
              response: Response(requestOptions: request, statusCode: status),
            ),
          ),
          status == 404 || status == 410,
        );
      }
      for (final error in <Object>[
        const FileSystemException('disk full'),
        const HandshakeException('bad certificate'),
        OperationFailure.message('cancel', kind: FailureKind.cancelled),
        StateError('script defect'),
      ]) {
        expect(canSkipUnavailableDownloadImage(error), isFalse);
      }
      expect(
        canSkipUnavailableDownloadImage(const SocketException('offline')),
        isTrue,
      );
      expect(
        canSkipUnavailableDownloadImage(
          OperationFailure.message('bad image', kind: FailureKind.unsupported),
        ),
        isTrue,
      );
    },
  );

  testWidgets('connection backoff is bounded and follows increasing delays', (
    tester,
  ) async {
    var attempts = 0;
    final retry = DownloadRetry(isActive: () => true, onWaitingChanged: () {});
    const failure = SocketException('offline');
    final done = expectLater(
      retry.run<void>(() async {
        attempts++;
        throw failure;
      }),
      throwsA(same(failure)),
    );
    await tester.pump();
    for (var i = 0; i < DownloadRetry.delays.length; i++) {
      expect(attempts, i + 1);
      expect(retry.isWaiting, isTrue);
      await tester.pump(
        DownloadRetry.delays[i] - const Duration(milliseconds: 1),
      );
      expect(attempts, i + 1);
      await tester.pump(const Duration(milliseconds: 1));
    }
    await done;
    expect(attempts, 7);
    expect(retry.isWaiting, isFalse);
    retry.wake();
    await tester.pump(const Duration(minutes: 5));
    expect(attempts, 7);
  });

  testWidgets('network hints do not replenish the retry budget', (
    tester,
  ) async {
    var attempts = 0;
    final retry = DownloadRetry(isActive: () => true, onWaitingChanged: () {});
    final done = expectLater(
      retry.run<void>(() async {
        attempts++;
        throw const SocketException('offline');
      }),
      throwsA(isA<SocketException>()),
    );
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      retry.wake();
      await tester.pump();
    }
    await done;
    expect(attempts, 7);
    await tester.pump(const Duration(minutes: 5));
    expect(attempts, 7);
  });

  testWidgets('cancellation drains every concurrent wait and removes timers', (
    tester,
  ) async {
    var attempts = 0;
    var active = true;
    final retry = DownloadRetry(
      isActive: () => active,
      onWaitingChanged: () {},
    );
    final results = List.generate(
      4,
      (_) => expectLater(
        retry.run<void>(() async {
          attempts++;
          throw const SocketException('offline');
        }),
        throwsA(
          isA<OperationFailure>().having(
            (e) => e.kind,
            'kind',
            FailureKind.cancelled,
          ),
        ),
      ),
    );
    await tester.pump();
    active = false;
    retry.cancel();
    retry.wake();
    await tester.pump();
    await Future.wait(results);
    expect(retry.isWaiting, isFalse);
    expect(attempts, 4);
  });

  final request = RequestOptions(path: 'https://example.invalid/image');
  final native = rhttp.HttpRequest(url: request.path);
  for (final error in <Object>[
    const SocketException('offline'),
    TimeoutException('timeout'),
    rhttp.RhttpConnectionException(native, 'reset'),
    rhttp.RhttpTimeoutException(native),
    DioException(
      requestOptions: request,
      type: DioExceptionType.connectionTimeout,
    ),
    DioException(
      requestOptions: request,
      type: DioExceptionType.receiveTimeout,
    ),
    DioException(
      requestOptions: request,
      error: rhttp.RhttpConnectionException(native, 'reset'),
    ),
    OperationFailure(
      message: 'wrapped',
      cause: DioException(
        requestOptions: request,
        error: const SocketException('offline'),
      ),
    ),
  ]) {
    testWidgets('transient ${error.runtimeType} wakes and succeeds', (
      tester,
    ) async {
      var attempts = 0;
      final retry = DownloadRetry(
        isActive: () => true,
        onWaitingChanged: () {},
      );
      final result = retry.run(() async {
        if (attempts++ == 0) throw error;
        return 42;
      });
      await tester.pump();
      expect(retry.isWaiting, isTrue);
      retry.wake();
      await tester.pump();
      expect(await result, 42);
      expect(attempts, 2);
    });
  }

  for (final error in <Object>[
    const FileSystemException('no space'),
    DioException(
      requestOptions: request,
      type: DioExceptionType.transformTimeout,
    ),
    const HandshakeException('invalid certificate'),
    StateError('invalid source'),
    OperationFailure.message('unsupported', kind: FailureKind.unsupported),
    OperationFailure.message('cancelled', kind: FailureKind.cancelled),
    DioException(
      requestOptions: request,
      type: DioExceptionType.badCertificate,
    ),
    DioException(requestOptions: request, type: DioExceptionType.cancel),
    for (final code in [401, 403, 404, 429, 500])
      DioException(
        requestOptions: request,
        type: DioExceptionType.badResponse,
        response: Response(requestOptions: request, statusCode: code),
      ),
    rhttp.RhttpInvalidCertificateException(request: native, message: 'invalid'),
    rhttp.RhttpCancelException(native),
  ]) {
    test('terminal ${error.runtimeType}: $error is not retried', () async {
      var attempts = 0;
      final retry = DownloadRetry(
        isActive: () => true,
        onWaitingChanged: () {},
      );
      await expectLater(
        retry.run<void>(() async {
          attempts++;
          throw error;
        }, retryUnknown: true),
        throwsA(same(error)),
      );
      expect(attempts, 1);
      expect(retry.isWaiting, isFalse);
    });
  }
}
