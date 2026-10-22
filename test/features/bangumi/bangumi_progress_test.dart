import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/features/bangumi/bangumi_service.dart';
import 'package:venera_next/features/bangumi/bangumi_client.dart';
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/foundation/reading_activity.dart';

class _Api extends BangumiClient {
  bool fail = false;
  final writes = <BangumiJson>[];
  @override
  Future<BangumiJson?> collection(String user, int id) async => {
    'ep_status': 20,
    'type': 4,
    'rate': 9,
  };
  @override
  Future<void> saveCollection(int id, BangumiJson value) async {
    if (fail) throw const BangumiFailure('offline');
    writes.add(value);
  }

  @override
  void close() {}
}

void main() {
  test(
    'mapped progress is durable, deferred while reading and retained after a failed upload',
    () async {
      final root = Directory.systemTemp.createTempSync('bangumi-progress-');
      final checkpoint = appdata.captureImportCheckpoint();
      App.dataPath = root.path;
      final api = _Api();
      final service = BangumiService(createClient: (_) => api);
      final release = ReadingActivity.instance.enter();
      try {
        await File('${root.path}/bangumi-session.json').writeAsString(
          jsonEncode({'id': 1, 'username': 'reader', 'token': 'local-only'}),
        );
        await service.bind('source', 'comic', {'id': 123, 'name': '漫画'});
        await service.setChapter('source', 'comic', 'real-id', {
          'ep_status': 12,
          'vol_status': 3,
        });
        await service.completed('source', 'comic', {'unmapped-id'});
        expect(
          BangumiService.map(appdata.settings['bangumiPendingProgress']),
          isEmpty,
        );
        await service.completed('source', 'comic', {'real-id'});
        expect(
          File('${root.path}/appdata.json').readAsStringSync(),
          contains('1:123'),
        );
        await service.drain();
        expect(api.writes, isEmpty);
        release();
        api.fail = true;
        await service.drain();
        expect(
          BangumiService.map(appdata.settings['bangumiPendingProgress']),
          isNotEmpty,
        );
        api.fail = false;
        await service.drain();
        expect(api.writes.single, {'ep_status': 20, 'vol_status': 3});
        await service.completed('source', 'comic', {'real-id'});
        await service.saveCollection(123, {'ep_status': 5, 'vol_status': 0});
        await service.drain();
        expect(api.writes.length, 2);
        expect(api.writes.last, {'ep_status': 5, 'vol_status': 0});
        expect(
          BangumiService.map(appdata.settings['bangumiPendingProgress']),
          isEmpty,
        );
      } finally {
        release();
        service.dispose();
        await appdata.restoreImportCheckpoint(checkpoint, persist: false);
        root.deleteSync(recursive: true);
      }
    },
  );
}
