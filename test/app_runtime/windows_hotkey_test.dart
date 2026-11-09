import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/app_runtime/windows_hotkey.dart';
import 'package:venera_next/features/sync/data_sync_content_fingerprint.dart';
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/foundation/window_hotkey.dart';

import '../support/window_hotkey_fixture.dart';

const _channel = MethodChannel('venera/window_hotkey');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  App.dataPath = Directory.systemTemp.path;

  test('dedicated native channel uses owner-scoped Win32 arguments', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          calls.add(call);
          if (call.method == 'open') return 42;
          if (call.method == 'stage') {
            throw PlatformException(code: 'hotkey_conflict', details: 1409);
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, null),
    );
    final backend = WindowsHotkeyBackend();
    expect(await backend.open(), 42);
    await expectLater(
      backend.stage(42, firstHotkey),
      throwsA(
        isA<WindowHotkeyFailure>().having(
          (e) => e.code,
          'code',
          'hotkey_conflict',
        ),
      ),
    );
    await backend.suspend(42, true);
    await backend.cancel(42);
    await backend.close(42);
    expect(calls[1].arguments, {'owner': 42, 'modifiers': 3, 'keyCode': 72});
    expect(calls[2].arguments, {'owner': 42, 'value': true});
    expect(calls.last.arguments, {'owner': 42});
  });

  test(
    'real persistence failure restores exact old settings and old registration; retry is local',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'window-hotkey-settings-',
      );
      final previousPath = App.dataPath;
      final before = appdata.captureImportCheckpoint();
      final native = FakeWindowHotkeyBackend();
      App.dataPath = root.path;
      appdata.settings[windowHotkeySettingKey] = firstHotkeyConfig.toJson();
      appdata.settings['language'] = 'en-US';
      appdata.settings['disableSyncFields'] = '';
      var syncs = 0;
      appdata.registerSyncDataRequestHandler(() => syncs++);
      _mockNative(native);
      final controller = createWindowsHotkeyHost().attach();
      addTearDown(() async {
        await controller.close();
        await appdata.restoreImportCheckpoint(before, persist: false);
        appdata.registerSyncDataRequestHandler(null);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_channel, null);
        App.dataPath = previousPath;
        root.deleteSync(recursive: true);
      });
      await controller.start();
      final blocked = Directory('${root.path}/appdata.json')..createSync();
      await expectLater(
        controller.configure(secondHotkeyConfig),
        throwsA(
          isA<WindowHotkeyFailure>().having(
            (e) => e.code,
            'code',
            'hotkey_save_failed',
          ),
        ),
      );
      expect(
        appdata.settings[windowHotkeySettingKey],
        firstHotkeyConfig.toJson(),
      );
      expect(appdata.settings['language'], 'en-US');
      expect(native.current, firstHotkey);
      expect(native.pending, isNull);
      blocked.deleteSync();
      await controller.configure(secondHotkeyConfig);
      final disk =
          jsonDecode(File('${root.path}/appdata.json').readAsStringSync())
              as Map;
      expect(
        (disk['settings'] as Map)[windowHotkeySettingKey],
        secondHotkeyConfig.toJson(),
      );
      expect(native.current, secondHotkey);
      expect(syncs, 0);
    },
  );

  test(
    'import cannot enable or override device hotkeys and changes do not dirty sync content',
    () async {
      final root = Directory.systemTemp.createTempSync('window-hotkey-import-');
      final previousPath = App.dataPath;
      final before = appdata.captureImportCheckpoint();
      App.dataPath = root.path;
      appdata.settings['disableSyncFields'] = '';
      addTearDown(() async {
        await appdata.restoreImportCheckpoint(before, persist: false);
        App.dataPath = previousPath;
        root.deleteSync(recursive: true);
      });
      for (final local in [null, firstHotkeyConfig.toJson()]) {
        appdata.settings[windowHotkeySettingKey] = local;
        final fingerprint = DataSyncContentFingerprint.settings(
          jsonEncode(appdata.toJson()),
          '',
        );
        await appdata.syncData({
          'settings': {windowHotkeySettingKey: secondHotkeyConfig.toJson()},
          'searchHistory': appdata.searchHistory,
        });
        expect(appdata.settings[windowHotkeySettingKey], local);
        appdata.settings[windowHotkeySettingKey] = secondHotkeyConfig.toJson();
        expect(
          DataSyncContentFingerprint.settings(jsonEncode(appdata.toJson()), ''),
          fingerprint,
        );
      }
    },
  );
}

void _mockNative(FakeWindowHotkeyBackend native) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (call) async {
        if (call.method == 'open') return native.open();
        final args = call.arguments as Map;
        final owner = args['owner'] as int;
        switch (call.method) {
          case 'stage':
            await native.stage(owner, WindowHotkey.fromJson(args));
          case 'commit':
            await native.commit(owner);
          case 'cancel':
            await native.cancel(owner);
          case 'suspend':
            await native.suspend(owner, args['value'] as bool);
          case 'close':
            await native.close(owner);
        }
        return null;
      });
}
