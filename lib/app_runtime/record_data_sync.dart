import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:crypto/crypto.dart';
import 'package:venera_next/features/history/history_manager.dart';
import 'package:venera_next/features/history/image_favorites.dart';
import 'package:venera_next/features/favorites/favorites_manager.dart';
import 'package:venera_next/features/sync/app_data_archive.dart';
import 'package:venera_next/features/sync/app_data_snapshot.dart';
import 'package:venera_next/features/sync/app_data_transfer.dart';
import 'package:venera_next/features/sync/data_sync_commit.dart';
import 'package:venera_next/features/sync/data_sync_transfer.dart';
import 'package:venera_next/features/sync/record_sync_snapshot.dart';
import 'package:venera_next/features/sync/record_sync_application.dart';
import 'package:venera_next/features/comic_source/source_transaction_journal.dart';
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/foundation/app_data_sync_fields.dart';
import 'package:venera_next/foundation/log.dart';
import 'package:venera_next/foundation/app_data_operations.dart';
import 'package:venera_next/network/request_scope.dart';
import 'package:venera_next/network/webdav.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;

import 'package:venera_next/features/sync/record_sync_worker.dart';
import 'package:venera_next/foundation/reading_activity.dart';

/// UI isolate orchestration only: network requests and guarded application commits.
/// Full documents, SQLite scans, diffs, hashing and serialization stay in a worker.
class RecordDataSyncTransfer implements MergingDataSyncTransfer {
  RecordDataSyncTransfer({
    webdav.Client Function(WebDavEndpoint)? createClient,
    RecordSyncApplication? application,
    this.compactAfter = 64,
  }) : _createClient =
           createClient ?? ((e) => e.createClient(logRequests: true)),
       _application = application ?? _ApplicationRecordSyncData();
  final webdav.Client Function(WebDavEndpoint) _createClient;
  final RecordSyncApplication _application;
  final int compactAfter;
  static const prefix = 'venera-records-v1-';

  @override
  Future<void> uploadMerged(
    WebDavEndpoint connection, {
    required RequestScope scope,
    required void Function(void Function()) publishImported,
  }) async {
    await _synchronize(connection, scope, publishImported);
  }

  @override
  Future<void> upload(
    WebDavEndpoint connection, {
    required bool excludeFields,
    required RequestScope scope,
    String? syncOperationId,
  }) async {
    await _synchronize(connection, scope);
  }

  @override
  Future<bool> download(
    WebDavEndpoint connection, {
    required RequestScope scope,
    bool force = false,
    void Function(void Function())? publishImported,
    String? syncOperationId,
  }) => _synchronize(connection, scope, publishImported);

  Future<bool> _synchronize(
    WebDavEndpoint endpoint,
    RequestScope scope, [
    void Function(void Function())? publish,
  ]) async {
    scope.check();
    final excluded = _application.excludedFields;
    final scopeId = sha256
        .convert(
          utf8.encode(
            jsonEncode([
              endpoint.url.replaceFirst(RegExp(r'/+$'), ''),
              endpoint.user,
              excluded,
            ]),
          ),
        )
        .toString();
    final root = await Directory(
      _application.cachePath,
    ).createTemp('record-sync-');
    RecordSyncWorker? worker;
    webdav.Client? client;
    Future<void>? closing;
    Future<void> closeClient() async {
      if (client case final owned?) {
        await (closing ??= closeWebDavClient(owned));
      }
    }

    var committed = false;
    Object? primaryError;
    StackTrace? primaryStack;
    try {
      worker = await RecordSyncWorker.open(
        '${_application.dataPath}/record_sync.db',
        scopeId,
        root.path,
      );
      scope.check();
      await _reconcile(
        root,
        worker,
        excluded,
        scope,
        [],
        publish,
        () => committed = true,
      );
      scope.check();
      client = _createClient(endpoint);
      unawaited(
        scope.whenCancelled
            .then((_) => closeClient())
            .catchError((Object _) {}),
      );
      Future<void> flushUploads() async {
        final uploads = await worker!.call('uploads') as List;
        for (final upload in uploads) {
          scope.check();
          await client!.write(
            upload['name'] as String,
            await File(upload['path'] as String).readAsBytes(),
            cancelToken: scope.cancelToken,
          );
          committed = true;
          scope.check();
          final verification = '${root.path}/checkpoint.json';
          if (upload['checkpoint'] == true) {
            await client.read2File(
              upload['name'] as String,
              verification,
              cancelToken: scope.cancelToken,
            );
          }
          await worker.call('ack', {
            'name': upload['name'],
            'verification': verification,
          });
        }
      }

      await flushUploads();
      scope.check();
      final files = await client.readDir('/', scope.cancelToken);
      final pattern = RegExp(r'^venera-records-v1-[0-9a-f]{64}\.json$');
      final batches = files
          .where((f) => pattern.hasMatch(f.name ?? ''))
          .toList();
      final seen = (await worker.call('seen') as List).cast<String>().toSet();
      final incoming = <List<String>>[];
      for (final entry in batches) {
        if (seen.contains(entry.name)) continue;
        scope.check();
        final path = '${root.path}/incoming/${entry.name!}';
        await Directory('${root.path}/incoming').create(recursive: true);
        await client.read2File(
          entry.name!,
          path,
          cancelToken: scope.cancelToken,
        );
        incoming.add([entry.name!, path]);
      }
      var migratedLegacy = false;
      if (batches.isEmpty && !seen.contains('legacy-bootstrap')) {
        final legacy = files
            .where((f) => f.name?.endsWith('.venera') == true)
            .toList();
        int version(String? name) =>
            int.tryParse(name?.split('-').last.split('.').first ?? '') ?? -1;
        legacy.sort((a, b) => version(b.name).compareTo(version(a.name)));
        if (legacy.isNotEmpty) {
          final archive = '${root.path}/legacy.venera';
          await client.read2File(
            legacy.first.name!,
            archive,
            cancelToken: scope.cancelToken,
          );
          final stage = await root.createTemp('legacy-');
          await AppDataArchive.extract(archive, stage.path);
          scope.check();
          await worker.call('legacy', {
            'archive': archive,
            'stage': stage.path,
          });
          migratedLegacy = true;
        }
      }
      scope.check();
      if (excluded != _application.excludedFields) {
        throw StateError('Sync field selection changed; retry');
      }
      // The initial capture is sufficient when the directory contains no unseen
      // batches. Local edits made during the request keep their generation dirty.
      var changed = false;
      if (incoming.isNotEmpty || migratedLegacy) {
        changed = await _reconcile(
          root,
          worker,
          excluded,
          scope,
          incoming,
          publish,
          () => committed = true,
        );
      }
      scope.check();
      final compact = batches.length >= compactAfter || migratedLegacy;
      final uploaded =
          await worker.call('prepareUpload', {'compact': compact}) as String?;
      await flushUploads();
      if (compact && uploaded != null) {
        final removed = <String>[];
        for (final old in batches) {
          if (old.name == uploaded) continue;
          scope.check();
          try {
            await client.remove(old.name!, scope.cancelToken);
            removed.add(old.name!);
          } catch (_) {
            Log.warning('Record sync', 'Older batches could not be compacted.');
            break;
          }
        }
        await worker.call('forget', {'names': removed});
      }
      await _application.recordSyncTime();
      return changed;
    } catch (error, stack) {
      primaryError = error;
      primaryStack = stack;
      if (committed && error is! DataSyncFailure) {
        final failure = DataSyncFailure(
          commitState: DataSyncCommitState.applied,
          failures: [
            (
              stage: 'finish record synchronization',
              error: error,
              stack: stack,
            ),
          ],
        );
        primaryError = failure;
        throw failure;
      }
      rethrow;
    } finally {
      final cleanup = <DataSyncDiagnostic>[];
      try {
        await closeClient();
      } catch (error, stack) {
        cleanup.add((
          stage: 'close record sync client',
          error: error,
          stack: stack,
        ));
      }
      try {
        await worker?.close();
      } catch (error, stack) {
        cleanup.add((
          stage: 'close record sync worker',
          error: error,
          stack: stack,
        ));
      }
      try {
        await root.delete(recursive: true);
      } on FileSystemException {
        Log.warning(
          'Record sync',
          'Temporary sync files could not be removed.',
        );
      }
      if (cleanup.isNotEmpty) {
        final primary = primaryError;
        throw DataSyncFailure(
          commitState: primary is DataSyncFailure
              ? primary.commitState
              : committed
              ? DataSyncCommitState.applied
              : DataSyncCommitState.notApplied,
          failures: [
            if (primary is DataSyncFailure)
              ...primary.failures
            else if (primary != null)
              (
                stage: 'record synchronization',
                error: primary,
                stack: primaryStack!,
              ),
            ...cleanup,
          ],
        );
      }
    }
  }

  Future<bool> _reconcile(
    Directory root,
    RecordSyncWorker worker,
    String excluded,
    RequestScope scope,
    List<List<String>> incoming,
    void Function(void Function())? publish,
    void Function() onApplied,
  ) => _application.exclusive(() async {
    scope.check();
    final staging = await root.createTemp('snapshot-');
    await _application.capture(staging);
    scope.check();
    var changed = false;
    final recovery =
        await worker.call('recover', {
              'stage': staging.path,
              'excluded': excluded,
            })
            as bool?;
    if (recovery != null) {
      if (recovery) {
        scope.check();
        await _application.apply(staging, scope, publish);
        onApplied();
        changed = true;
      }
      await worker.call('recovered');
    }
    scope.check();
    final apply =
        await worker.call('plan', {
              'stage': staging.path,
              'excluded': excluded,
              'incoming': incoming,
            })
            as bool;
    if (apply) {
      scope.check();
      await _application.apply(staging, scope, publish);
      onApplied();
      changed = true;
    }
    await worker.call('applied');
    return changed;
  });
}

// Only send plain paths and settings values to the snapshot isolate, never an
// application manager, SQLite connection or the exclusive-operation capability.
Future<void> _captureRecordSnapshot(
  String dataPath,
  String staging,
  Map<String, dynamic> settings,
) => Isolate.run(() async {
  await createAppDataSnapshot(
    dataPath,
    staging,
    settingsJson: jsonEncode(settings),
  );
});

class _ApplicationRecordSyncData implements RecordSyncApplication {
  @override
  String get dataPath => App.dataPath;
  @override
  String get cachePath => App.cachePath;
  @override
  String get excludedFields => [
    appdata.settings['disableSyncFields'] as String? ?? '',
    if (appdata.settings['backupWebdavSyncEnabled'] != true)
      ...appDataOptionalArchiveFields,
  ].join(',');
  @override
  Future<T> exclusive<T>(Future<T> Function() action) =>
      AppDataOperations.instance.run(action);
  @override
  Future<void> capture(Directory staging) async {
    void checkReading() {
      if (ReadingActivity.instance.isReading) throw const RequestCancelled();
    }

    checkReading();
    await SourceTransactionJournal.checkReadyForTransfer(dataPath);
    checkReading();
    await HistoryManager.cache?.waitForAsyncWrites();
    checkReading();
    await appdata.saveData(false);
    checkReading();
    await _captureRecordSnapshot(dataPath, staging.path, appdata.toJson());
  }

  @override
  Future<void> apply(
    Directory staging,
    RequestScope scope,
    void Function(void Function())? publish,
  ) async {
    if (ReadingActivity.instance.isReading) throw const RequestCancelled();
    scope.check();
    final localExclusions = RecordSyncSnapshot.exclusions(excludedFields);
    final intendedSettings =
        (jsonDecode(File('${staging.path}/appdata.json').readAsStringSync())
                as Map)['settings']
            as Map;
    final archive = File('${staging.path}/merged.venera');
    if (archive.existsSync()) archive.deleteSync();
    await AppDataArchive.create(
      dataPath: staging.path,
      cachePath: cachePath,
      destinationPath: archive.path,
      settingsJson: File('${staging.path}/appdata.json').readAsStringSync(),
    );
    scope.check();
    final result = await importSyncAppData(
      archive,
      checkActive: scope.check,
      force: true,
      publishImported: publish,
    );
    if (result != DataSyncCommitState.applied) {
      throw StateError('Merged records were not applied');
    }
    try {
      // The legacy importer intentionally merges missing settings. A record
      // tombstone is explicit, so finish those removals inside the durable plan.
      await appdata.applyRecordSyncSettings(
        Map<String, dynamic>.from(intendedSettings),
        localFields: localExclusions,
      );
      void notify() {
        HistoryManager().notifyChanges();
        LocalFavoritesManager().notifyChanges();
        ImageFavoriteManager().notifyChanges();
      }

      if (publish == null) {
        notify();
      } else {
        publish(notify);
      }
    } catch (error, stack) {
      if (error is DataSyncFailure) rethrow;
      throw DataSyncFailure(
        commitState: DataSyncCommitState.applied,
        failures: [
          (
            stage: 'finish merged settings and notifications',
            error: error,
            stack: stack,
          ),
        ],
      );
    }
  }

  @override
  Future<void> recordSyncTime() => appdata.updateSettings((s) {
    s['lastSyncTime'] = DateTime.now().millisecondsSinceEpoch;
  }, sync: false);
}
