import 'package:venera_next/foundation/app_sync_preferences.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/features/comic_source/comic_source_api.dart';
import 'package:venera_next/features/favorites/favorites_manager.dart';
import 'package:venera_next/features/sync/data_sync_controller.dart';
import 'package:venera_next/features/sync/data_sync_transfer.dart';
import 'package:venera_next/features/sync/data_sync_recovery.dart';
import 'data_sync_transfer.dart';
import 'data_sync_content.dart';
import 'package:venera_next/features/sync/data_sync_ownership.dart';
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/features/history/history_manager.dart';
import 'package:venera_next/features/history/image_favorites.dart';
import 'record_data_sync.dart';
import 'package:venera_next/foundation/reading_activity.dart';

/// Construction is inert. The application owns start/stop/dispose.
DataSyncController createApplicationDataSync({
  DataSyncTransfer Function()? transfer,
  DataSyncImportRecovery? importRecovery,
  DataSyncUploadRecovery? uploadRecovery,
  bool useV117WebDav = true,
}) {
  // 保留基本 WebDAV 兼容性，默认使用记录合并及持久补传，不要求 ETag。
  // 旧 RC 恢复协议只在显式选择该分支时启用。
  final recovery = useV117WebDav
      ? null
      : importRecovery ?? createDataSyncImportRecovery();
  final defaultTransfer = !useV117WebDav && transfer == null
      ? createDataSyncTransfer(importRecovery: recovery)
      : null;
  late final DataSyncController controller;
  controller = DataSyncController(
    useV117WebDav: useV117WebDav,
    reliableAutomaticSync: useV117WebDav,
    automaticIdleInterval: App.isIOS
        ? const Duration(minutes: 5)
        : const Duration(seconds: 60),
    coalesceAutomaticChecks: App.isIOS,
    preferences: createAppSyncPreferences(appdata),
    transfer:
        transfer ??
        () => useV117WebDav ? RecordDataSyncTransfer() : defaultTransfer!,
    importRecovery: recovery,
    uploadRecovery: useV117WebDav ? null : uploadRecovery ?? defaultTransfer,
    content: useV117WebDav ? null : ApplicationDataSyncContent(),
    ownership: SqliteDataSyncOwnership(() => App.dataPath),
    saveSettings: () => appdata.saveData(false),
    persistImplicit: appdata.writeImplicitData,
    observeChanges: (changed) =>
        _observeApplicationChanges(changed, controller.setReadingActive),
  );
  return controller;
}

void Function() _observeApplicationChanges(
  void Function() changed,
  void Function(bool) setReadingActive,
) {
  final favorites = LocalFavoritesManager();
  final sources = ComicSourceManager();
  final history = HistoryManager();
  final images = ImageFavoriteManager();
  final reading = ReadingActivity.instance;
  void readingChanged() => setReadingActive(reading.isReading);
  favorites.addListener(changed);
  try {
    sources.addListener(changed);
    history.addListener(changed);
    images.addListener(changed);
    appdata.registerSyncDataRequestHandler(changed);
    reading.addListener(readingChanged);
    readingChanged();
  } catch (_) {
    favorites.removeListener(changed);
    sources.removeListener(changed);
    history.removeListener(changed);
    images.removeListener(changed);
    reading.removeListener(readingChanged);
    rethrow;
  }
  return () {
    appdata.registerSyncDataRequestHandler(null);
    favorites.removeListener(changed);
    sources.removeListener(changed);
    history.removeListener(changed);
    images.removeListener(changed);
    reading.removeListener(readingChanged);
  };
}
