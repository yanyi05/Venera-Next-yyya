import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/features/local_comics/download_policy.dart';
import 'package:venera_next/features/local_comics/download_retry.dart';

void main() {
  test(
    'reading uses one slot and restores the configured budget afterward',
    () {
      expect(readingDownloadConcurrency(6, reading: true), 1);
      expect(readingDownloadConcurrency(6, reading: false), 6);
      expect(readingDownloadConcurrency(0, reading: false), 1);
    },
  );
  DioException response(int status, String value) {
    final options = RequestOptions(path: '/');
    return DioException(
      requestOptions: options,
      type: DioExceptionType.badResponse,
      response: Response(
        requestOptions: options,
        statusCode: status,
        headers: Headers.fromMap({
          'retry-after': [value],
        }),
      ),
    );
  }

  test('server Retry-After honors seconds, dates and bounded waits', () {
    final now = DateTime.utc(2026, 10, 22);
    expect(
      downloadRetryAfter(response(429, '45')),
      const Duration(seconds: 45),
    );
    expect(
      downloadRetryAfter(
        response(503, HttpDate.format(now.add(const Duration(seconds: 90)))),
        now: now,
      ),
      const Duration(seconds: 90),
    );
    expect(
      downloadRetryAfter(response(429, '99999')),
      const Duration(minutes: 5),
    );
    expect(downloadRetryAfter(response(403, '60')), isNull);
  });
  for (final code in [429, 503]) {
    testWidgets('HTTP $code waits Retry-After then succeeds', (tester) async {
      var attempts = 0;
      final retry = DownloadRetry(
        isActive: () => true,
        onWaitingChanged: () {},
      );
      final done = retry.run(() async {
        if (attempts++ == 0) throw response(code, '45');
        return 42;
      });
      await tester.pump();
      await tester.pump(const Duration(seconds: 44));
      expect(attempts, 1);
      await tester.pump(const Duration(seconds: 1));
      expect(await done, 42);
      expect(attempts, 2);
    });
  }
}
