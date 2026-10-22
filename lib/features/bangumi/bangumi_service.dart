import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/foundation/reading_activity.dart';
import 'bangumi_client.dart';

class BangumiService {
  BangumiService({BangumiClient Function(String)? createClient})
    : _createClient = createClient ?? ((token) => BangumiClient(token: token)) {
    ReadingActivity.instance.addListener(_activityChanged);
  }
  final BangumiClient Function(String) _createClient;
  static final instance = BangumiService();
  Timer? _retry;
  bool _draining = false;
  bool _drainRequested = false;
  bool _active = true;
  void start() {
    _active = true;
    unawaited(drain());
  }

  void stop() {
    _active = false;
    _retry?.cancel();
  }

  void dispose() {
    stop();
    ReadingActivity.instance.removeListener(_activityChanged);
  }

  String? lastError;
  Future<void> _mutationTail = Future.value();
  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = _mutationTail.then((_) => operation());
    _mutationTail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  /// Explicit edits take precedence over previously queued automatic progress.
  Future<void> saveCollection(
    int id,
    BangumiJson values,
  ) => _serialize(() async {
    final directory = App.dataPath;
    final auth = await session();
    if (auth['token'] == null) throw const BangumiFailure('请先连接 Bangumi 账号');
    final recordKey = '${auth['id']}:$id';
    final previous = map(appdata.settings['bangumiPendingProgress'])[recordKey];
    final api = _createClient(auth['token']);
    try {
      await api.saveCollection(id, values);
      if (directory != App.dataPath) return;
      await appdata.updateSettings((draft) {
        final pending = map(draft['bangumiPendingProgress']);
        if (jsonEncode(pending[recordKey]) == jsonEncode(previous)) {
          final queued = map(previous);
          for (final field in ['ep_status', 'vol_status']) {
            if (values.containsKey(field)) queued.remove(field);
          }
          if (!queued.containsKey('ep_status') &&
              !queued.containsKey('vol_status')) {
            pending.remove(recordKey);
          } else {
            pending[recordKey] = queued;
          }
        }
        draft['bangumiPendingProgress'] = pending;
      }, sync: false);
    } finally {
      api.close();
    }
  });
  static String key(String source, String comic) => jsonEncode([source, comic]);
  static BangumiJson map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : {};
  BangumiJson get bindings => map(appdata.settings['bangumiBindings']);
  BangumiJson? binding(String source, String comic) {
    final value = bindings[key(source, comic)];
    return value is Map ? map(value) : null;
  }

  File get _sessionFile => File(p.join(App.dataPath, 'bangumi-session.json'));
  Future<BangumiJson> session() async {
    final file = _sessionFile;
    try {
      if (!await file.exists()) return {};
      return map(jsonDecode(await file.readAsString()));
    } on FileSystemException {
      lastError = '本机账号信息无法读取，请重新连接 Bangumi';
      return {};
    } on FormatException {
      lastError = '本机账号信息已损坏，请重新连接 Bangumi';
      return {};
    }
  }

  Future<BangumiClient> client() async {
    final auth = await session();
    return _createClient(auth['token'] as String? ?? '');
  }

  Future<void> connect(String token) async {
    final path = _sessionFile.path;
    final api = _createClient(token.trim());
    try {
      final me = await api.me();
      if (App.dataPath != p.dirname(path)) throw StateError('数据目录已改变，请重新连接');
      final file = File(path);
      final temp = File('$path.tmp');
      await temp.writeAsString(
        jsonEncode({
          'token': token.trim(),
          'username': me['username'],
          'id': me['id'],
          'nickname': me['nickname'],
        }),
        flush: true,
      );
      await temp.rename(file.path);
      lastError = null;
      _active = true;
      _schedule();
    } finally {
      api.close();
    }
  }

  Future<void> disconnect() async {
    _retry?.cancel();
    final file = _sessionFile;
    if (await file.exists()) await file.delete();
  }

  Future<void> bind(String source, String comic, BangumiJson subject) =>
      appdata.updateSettings((draft) {
        final values = map(draft['bangumiBindings']);
        values[key(source, comic)] = {
          'subjectId': subject['id'],
          'title': bangumiTitle(subject),
          'chapters': <String, dynamic>{},
          'score': map(subject['rating'])['score'],
          'votes': map(subject['rating'])['total'],
          'rank': map(subject['rating'])['rank'],
        };
        draft['bangumiBindings'] = values;
      });
  Future<void> unbind(String source, String comic) =>
      appdata.updateSettings((draft) {
        final values = map(draft['bangumiBindings'])
          ..remove(key(source, comic));
        draft['bangumiBindings'] = values;
      });
  Future<void> setChapter(
    String source,
    String comic,
    String chapter,
    BangumiJson? progress,
  ) => appdata.updateSettings((draft) {
    final values = map(draft['bangumiBindings']);
    final binding = map(values[key(source, comic)]);
    if (binding.isEmpty) throw StateError('请先关联 Bangumi 作品');
    final chapters = map(binding['chapters']);
    if (progress == null) {
      chapters.remove(chapter);
    } else {
      chapters[chapter] = progress;
    }
    binding['chapters'] = chapters;
    values[key(source, comic)] = binding;
    draft['bangumiBindings'] = values;
  });

  /// Called once after the reader closes. A chapter is submitted only after its
  /// last image was reached and the user explicitly mapped its source ID.
  Future<void> completed(
    String source,
    String comic,
    Set<String> chapters,
  ) async {
    final directory = App.dataPath;
    final target = binding(source, comic);
    if (target == null || chapters.isEmpty) return;
    final mapping = map(target['chapters']);
    final progress = <String, dynamic>{};
    for (final chapter in chapters) {
      final entry = map(mapping[chapter]);
      for (final field in ['ep_status', 'vol_status']) {
        if (entry[field] is int && entry[field] > (progress[field] ?? -1)) {
          progress[field] = entry[field];
        }
      }
    }
    if (progress.isEmpty) return;
    final auth = await session();
    if (directory != App.dataPath) return;
    final user = auth['id']?.toString();
    if (user == null) return;
    final recordKey = '$user:${target['subjectId']}';
    await appdata.updateSettings((draft) {
      if (directory != App.dataPath) return;
      final pending = map(draft['bangumiPendingProgress']);
      final old = map(pending[recordKey]);
      pending[recordKey] = {
        'user': user,
        'subjectId': target['subjectId'],
        ...(mergeBangumiProgress(old, progress)..remove('type')),
      };
      draft['bangumiPendingProgress'] = pending;
    }, sync: false);
    _schedule();
  }

  void _activityChanged() {
    if (ReadingActivity.instance.isReading) {
      _retry?.cancel();
    } else {
      _schedule();
    }
  }

  void _schedule([Duration delay = const Duration(seconds: 3)]) {
    _retry?.cancel();
    if (_active && !ReadingActivity.instance.isReading) {
      _retry = Timer(delay, () => unawaited(drain()));
    }
  }

  Future<void> drain() async {
    if (_draining) {
      _drainRequested = true;
      return;
    }
    if (!_active || ReadingActivity.instance.isReading) return;
    _draining = true;
    final directory = App.dataPath;
    BangumiClient? api;
    try {
      final auth = await session();
      if (auth['token'] == null) return;
      final user = auth['id'].toString();
      api = _createClient(auth['token']);
      final client = api;
      final pending = map(appdata.settings['bangumiPendingProgress']);
      for (final entry in pending.entries) {
        if (!_active ||
            ReadingActivity.instance.isReading ||
            directory != App.dataPath) {
          return;
        }
        final value = map(entry.value);
        if (value['user'] != user) continue;
        final id = value['subjectId'] as int;
        await _serialize(() async {
          if (!_active || directory != App.dataPath ||
              ReadingActivity.instance.isReading ||
              jsonEncode(
                    map(appdata.settings['bangumiPendingProgress'])[entry.key],
                  ) !=
                  jsonEncode(entry.value)) {
            return;
          }
          final remote = await client.collection(
            auth['username'].toString(),
            id,
          );
          if (!_active ||
              ReadingActivity.instance.isReading ||
              directory != App.dataPath) {
            return;
          }
          final current = await session();
          if (current['token'] != auth['token']) return;
          await client.saveCollection(id, mergeBangumiProgress(remote, value));
          await appdata.updateSettings((draft) {
            if (directory != App.dataPath) return;
            final next = map(draft['bangumiPendingProgress']);
            if (jsonEncode(next[entry.key]) == jsonEncode(entry.value)) {
              next.remove(entry.key);
            }
            draft['bangumiPendingProgress'] = next;
          }, sync: false);
        });
      }
      lastError = null;
    } catch (error) {
      lastError = error.toString();
      _schedule(const Duration(seconds: 60));
    } finally {
      api?.close();
      _draining = false;
      if (_drainRequested) {
        _drainRequested = false;
        _schedule();
      }
    }
  }
}
