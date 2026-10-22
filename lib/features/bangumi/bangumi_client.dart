import 'package:dio/dio.dart';

typedef BangumiJson = Map<String, dynamic>;

class BangumiFailure implements Exception {
  const BangumiFailure(this.message, [this.status]);
  final String message;
  final int? status;
  @override
  String toString() => message;
}

class BangumiClient {
  BangumiClient({this.token = '', Dio? http})
    : http =
          http ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 15)));
  final String token;
  final Dio http;
  static const origin = 'https://api.bgm.tv/v0';

  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Object? data,
    Map<String, dynamic>? query,
  }) async {
    try {
      final response = await http.request<dynamic>(
        '$origin$path',
        data: data,
        queryParameters: query,
        options: Options(
          method: method,
          headers: {
            'User-Agent':
                'yanyi05/Venera-Next-yyya/1.0 (https://github.com/yanyi05/Venera-Next-yyya)',
            if (token.isNotEmpty) 'Authorization': 'Bearer $token',
          },
          followRedirects: false,
          sendTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 20),
        ),
      );
      return response.data;
    } on DioException catch (error) {
      final code = error.response?.statusCode;
      throw BangumiFailure(switch (code) {
        401 => 'Bangumi 登录已过期，请重新连接账号',
        403 => 'Bangumi 拒绝访问，请检查账号权限',
        404 => 'Bangumi 条目或收藏不存在',
        429 => 'Bangumi 请求过于频繁，请稍后重试',
        _ =>
          code == null ? 'Bangumi 连接失败，请检查网络后重试' : 'Bangumi 请求失败（HTTP $code）',
      }, code);
    }
  }

  Future<BangumiJson> me() async =>
      Map<String, dynamic>.from(await request('/me'));
  Future<BangumiJson> subject(int id) async =>
      Map<String, dynamic>.from(await request('/subjects/$id'));
  Future<BangumiJson> search(String keyword, {int offset = 0}) async =>
      Map<String, dynamic>.from(
        await request(
          '/search/subjects',
          method: 'POST',
          query: {'limit': 20, 'offset': offset},
          data: {
            'keyword': keyword,
            'sort': 'match',
            'filter': {
              'type': [1],
            },
          },
        ),
      );
  Future<BangumiJson> library(String user, int type, {int offset = 0}) async =>
      Map<String, dynamic>.from(
        await request(
          '/users/${Uri.encodeComponent(user)}/collections',
          query: {
            'subject_type': 1,
            'type': type,
            'limit': 50,
            'offset': offset,
          },
        ),
      );
  Future<BangumiJson?> collection(String user, int id) async {
    try {
      return Map<String, dynamic>.from(
        await request('/users/${Uri.encodeComponent(user)}/collections/$id'),
      );
    } on BangumiFailure catch (error) {
      if (error.status == 404) return null;
      rethrow;
    }
  }

  Future<void> saveCollection(int id, BangumiJson values) async {
    await request('/users/-/collections/$id', method: 'POST', data: values);
  }

  Future<List<BangumiJson>> relations(int id) async =>
      (await request('/subjects/$id/subjects') as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
  void close() => http.close(force: true);
}

String bangumiTitle(BangumiJson item) =>
    (item['name_cn'] as String?)?.trim().isNotEmpty == true
    ? item['name_cn'] as String
    : (item['name'] ?? '未命名作品').toString();

const bangumiStates = {1: '想读', 3: '在读', 2: '读完', 4: '搁置', 5: '放弃'};

/// Merge only progress, preserving remotely edited status, rating and comments.
BangumiJson mergeBangumiProgress(BangumiJson? remote, BangumiJson pending) {
  int maxValue(String key) {
    final a = (remote?[key] as num?)?.toInt() ?? 0;
    final b = (pending[key] as num?)?.toInt() ?? 0;
    return a > b ? a : b;
  }

  return {
    if (remote == null) 'type': 3,
    if (pending.containsKey('ep_status')) 'ep_status': maxValue('ep_status'),
    if (pending.containsKey('vol_status')) 'vol_status': maxValue('vol_status'),
  };
}
