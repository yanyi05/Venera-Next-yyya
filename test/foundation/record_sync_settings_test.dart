import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/foundation/appdata.dart';

void main() {
  test(
    'record settings persist explicit deletions while retaining excluded local values',
    () async {
      final root = Directory.systemTemp.createTempSync('record-settings-');
      final checkpoint = appdata.captureImportCheckpoint();
      App.dataPath = root.path;
      try {
        await appdata.updateSettings((s) {
          s['record-test-delete'] = 'old';
          s['record-test-local'] = 'local';
        }, sync: false);
        final intended =
            Map<String, dynamic>.from(appdata.toJson()['settings'] as Map)
              ..remove('record-test-delete')
              ..['record-test-local'] = 'remote'
              ..['record-test-new'] = 'new';
        await appdata.applyRecordSyncSettings(
          intended,
          localFields: {'record-test-local'},
        );
        final persisted =
            (jsonDecode(File('${root.path}/appdata.json').readAsStringSync())
                    as Map)['settings']
                as Map;
        expect(persisted.containsKey('record-test-delete'), isFalse);
        expect(persisted['record-test-local'], 'local');
        expect(persisted['record-test-new'], 'new');
        expect(
          (appdata.toJson()['settings'] as Map).containsKey(
            'record-test-delete',
          ),
          isFalse,
        );
      } finally {
        await appdata.restoreImportCheckpoint(checkpoint, persist: false);
        root.deleteSync(recursive: true);
      }
    },
  );
}
