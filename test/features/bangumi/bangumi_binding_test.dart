import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/features/bangumi/bangumi_service.dart';
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/foundation/appdata.dart';

void main() {
  test(
    'bindings persist exact source chapter IDs and rebinding clears obsolete mappings',
    () async {
      final root = Directory.systemTemp.createTempSync('bangumi-binding-');
      final checkpoint = appdata.captureImportCheckpoint();
      App.dataPath = root.path;
      final service = BangumiService.instance;
      try {
        await service.bind('source', 'comic', {'id': 123, 'name': '漫画'});
        await service.setChapter('source', 'comic', 'chapter-extra-1', {
          'ep_status': 12,
        });
        expect(service.binding('source', 'comic')!['chapters'], {
          'chapter-extra-1': {'ep_status': 12},
        });
        expect(service.binding('another-source', 'comic'), isNull);
        await service.bind('source', 'comic', {'id': 456, 'name': '另一个作品'});
        expect(service.binding('source', 'comic')!['chapters'], isEmpty);
        expect(
          File('${root.path}/appdata.json').readAsStringSync(),
          contains('456'),
        );
        await service.unbind('source', 'comic');
        expect(service.binding('source', 'comic'), isNull);
      } finally {
        await appdata.restoreImportCheckpoint(checkpoint, persist: false);
        root.deleteSync(recursive: true);
      }
    },
  );
}
