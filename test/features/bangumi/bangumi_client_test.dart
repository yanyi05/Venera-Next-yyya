import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/features/bangumi/bangumi_client.dart';

class _Http implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  int status = 200;
  Object result = <String, dynamic>{};
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(result),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('search restricts subject type and puts token only in header', () async {
    final adapter = _Http();
    final dio = Dio()..httpClientAdapter = adapter;
    final api = BangumiClient(token: 'private-token', http: dio);
    await api.search('作品', offset: 20);
    final request = adapter.requests.single;
    expect(request.uri.path, '/v0/search/subjects');
    expect(request.method, 'POST');
    expect(request.queryParameters, {'limit': 20, 'offset': 20});
    expect(request.data['filter']['type'], [1]);
    expect(request.headers['Authorization'], 'Bearer private-token');
    expect(request.uri.toString(), isNot(contains('private-token')));
    api.close();
  });
  test('collection updates only explicitly edited fields', () async {
    final adapter = _Http()..status = 204;
    final api = BangumiClient(http: Dio()..httpClientAdapter = adapter);
    await api.saveCollection(123, {'ep_status': 12});
    expect(adapter.requests.single.uri.path, '/v0/users/-/collections/123');
    expect(adapter.requests.single.method, 'POST');
    expect(adapter.requests.single.data, {'ep_status': 12});
    api.close();
  });
  test('authentication failures never expose the credential', () async {
    final adapter = _Http()..status = 401;
    final api = BangumiClient(
      token: 'private-token',
      http: Dio()..httpClientAdapter = adapter,
    );
    await expectLater(
      api.me(),
      throwsA(
        isA<BangumiFailure>().having(
          (e) => e.toString(),
          'safe message',
          isNot(contains('private-token')),
        ),
      ),
    );
    api.close();
  });
  test('progress never lowers remote values or overwrites ratings/status', () {
    expect(
      mergeBangumiProgress(
        {'type': 4, 'rate': 9, 'ep_status': 40, 'vol_status': 3},
        {'ep_status': 30, 'vol_status': 4},
      ),
      {'ep_status': 40, 'vol_status': 4},
    );
    expect(mergeBangumiProgress(null, {'ep_status': 12}), {
      'type': 3,
      'ep_status': 12,
    });
  });
}
