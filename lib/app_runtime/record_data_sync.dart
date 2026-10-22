import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:venera_next/features/history/history_manager.dart';
import 'package:venera_next/features/history/image_favorites.dart';
import 'package:venera_next/features/favorites/favorites_manager.dart';
import 'package:venera_next/features/sync/app_data_archive.dart';
import 'package:venera_next/features/sync/app_data_snapshot.dart';
import 'package:venera_next/features/sync/app_data_transfer.dart';
import 'package:venera_next/features/sync/data_sync_commit.dart';
import 'package:venera_next/features/sync/data_sync_transfer.dart';
import 'package:venera_next/features/sync/record_sync_document.dart';
import 'package:venera_next/features/sync/record_sync_snapshot.dart';
import 'package:venera_next/features/sync/record_sync_store.dart';
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

/// Both directions converge records. No ETag, conditional PUT or DELETE is
/// required: an immutable, content-addressed batch can be retried after a crash.
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
    final store = RecordSyncStore('${_application.dataPath}/record_sync.db');
    late final RecordSyncDocument document;
    late final Directory root;
    try {
      document = store.load(scopeId);
      root = await Directory(_application.cachePath).createTemp('record-sync-');
    } catch (_) {
      store.close();
      rethrow;
    }
    var committed = false;
    Object? transferError;
    StackTrace? transferStack;
    webdav.Client? client;
    Future<void>? closing;
    Future<void> close() async {
      final owned = client;
      if (owned != null) await (closing ??= closeWebDavClient(owned));
    }

    try {
      // Persist a recoverable outbox before the first network request. Even if
      // killed earlier, next startup captures persisted DB edits before merging.
      await _reconcile(
        root,
        document,
        store,
        scopeId,
        excluded,
        scope,
        [],
        publish,
        () => committed = true,
      );
      scope.check();
      client = _createClient(endpoint);
      unawaited(
        scope.whenCancelled.then((_) => close()).catchError((Object _) {}),
      );
      Future<void> flushUploads() async {
        for (final upload in document.uploads.entries.toList()) {
          scope.check();
          await client!.write(
            upload.key,
            utf8.encode(upload.value),
            cancelToken: scope.cancelToken,
          );
          committed = true;
          scope.check();
          final sent = Map<String, dynamic>.from(
            jsonDecode(upload.value) as Map,
          );
          if (sent['checkpoint'] == true) {
            final verification = File('${root.path}/checkpoint.json');
            await client.read2File(
              upload.key,
              verification.path,
              cancelToken: scope.cancelToken,
            );
            if (sha256.convert(await verification.readAsBytes()).toString() !=
                sha256.convert(utf8.encode(upload.value)).toString()) {
              throw const FormatException('Checkpoint verification failed');
            }
          }
          document.acknowledge(sent);
          document.seen.add(upload.key);
          document.uploads.remove(upload.key);
          store.save(scopeId, document);
        }
      }

      // Repair a previously interrupted PUT before trying to read its filename.
      await flushUploads();
      final files = await client.readDir('/', scope.cancelToken);
      final batches =
          files
              .where(
                (f) =>
                    f.name?.startsWith(prefix) == true &&
                    f.name!.endsWith('.json'),
              )
              .toList()
            ..sort((a, b) => a.name!.compareTo(b.name!));
      final incoming = <(String, Map<String, dynamic>)>[];
      for (final file in batches) {
        final name = file.name!;
        if (document.seen.contains(name)) continue;
        final target = File('${root.path}/incoming.json');
        await client.read2File(
          name,
          target.path,
          cancelToken: scope.cancelToken,
        );
        final bytes = await target.readAsBytes();
        // Do not acknowledge a partial upload, a damaged file, or unknown format.
        if (name != '$prefix${sha256.convert(bytes)}.json') {
          throw const FormatException(
            'Incomplete or damaged record sync batch; retry later',
          );
        }
        incoming.add((
          name,
          Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)) as Map),
        ));
      }
      // One-time, add-only migration from the latest legacy backup. Absence of a
      // record in an old archive can never delete a newer record on this device.
      if (batches.isEmpty && !document.seen.contains('legacy-bootstrap')) {
        final legacy = files
            .where((f) => f.name?.endsWith('.venera') == true)
            .toList();
        int version(String? name) =>
            int.tryParse(name?.split('-').last.split('.').first ?? '') ?? -1;
        legacy.sort((a, b) => version(b.name).compareTo(version(a.name)));
        if (legacy.isNotEmpty) {
          final archive = File('${root.path}/legacy.venera');
          await client.read2File(
            legacy.first.name!,
            archive.path,
            cancelToken: scope.cancelToken,
          );
          final dir = await root.createTemp('legacy-');
          await AppDataArchive.extract(archive.path, dir.path);
          final seed = RecordSyncDocument(
            'legacy-${sha256.convert(await archive.readAsBytes())}',
          );
          seed.capture(
            RecordSyncSnapshot.read(dir.path, ''),
            seedTime: _seedTime,
          );
          incoming.add(('legacy-bootstrap', seed.packet));
        }
      }
      scope.check();
      if (_application.excludedFields != excluded) {
        throw StateError(
          'Sync field selection changed; retry with the new selection',
        );
      }
      final changed = await _reconcile(
        root,
        document,
        store,
        scopeId,
        excluded,
        scope,
        incoming,
        publish,
        () => committed = true,
      );
      final compact =
          batches.length >= compactAfter ||
          incoming.any((b) => b.$1 == 'legacy-bootstrap');
      if (document.outbox.isNotEmpty || compact) {
        // Detach the acknowledged generation. A later local edit cannot be
        // cleared by this request, even if it changes the same record.
        final packet =
            jsonDecode(
                  jsonEncode(
                    compact
                        ? {
                            'format': 1,
                            'records': document.records,
                            'checkpoint': true,
                          }
                        : document.packet,
                  ),
                )
                as Map<String, dynamic>;
        final payload = RecordSyncDocument.canonical(packet);
        final bytes = utf8.encode(payload);
        final name = '$prefix${sha256.convert(bytes)}.json';
        document.uploads[name] = payload;
        store.save(scopeId, document);
        await flushUploads();
        if (compact) {
          // The verified checkpoint contains all frontiers and tombstones from
          // these exact files. Concurrent files absent from this listing stay.
          for (final old in batches) {
            if (old.name == name) continue;
            try {
              await client.remove(old.name!, scope.cancelToken);
              document.seen.remove(old.name);
            } catch (_) {
              // DELETE is optional: providers without it can still synchronize.
              Log.warning(
                'Record sync',
                'Older sync batches could not be compacted.',
              );
              break;
            }
          }
          store.save(scopeId, document);
        }
      }
      await _application.recordSyncTime();
      return changed;
    } catch (error, stack) {
      transferError = error;
      transferStack = stack;
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
        transferError = failure;
        throw failure;
      }
      rethrow;
    } finally {
      final cleanup = <DataSyncDiagnostic>[];
      try {
        await close();
      } catch (error, stack) {
        cleanup.add((
          stage: 'close record sync client',
          error: error,
          stack: stack,
        ));
      }
      try {
        store.close();
      } catch (error, stack) {
        cleanup.add((
          stage: 'close record sync journal',
          error: error,
          stack: stack,
        ));
      }
      try {
        if (await root.exists()) await root.delete(recursive: true);
      } on FileSystemException {
        Log.warning(
          'Record sync',
          'Temporary sync files could not be removed.',
        );
      }
      if (cleanup.isNotEmpty) {
        final primary = transferError;
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
                stack: transferStack!,
              ),
            ...cleanup,
          ],
        );
      }
    }
  }

  static int _seedTime(String key, dynamic value) {
    final parts = jsonDecode(key) as List;
    if (parts[0] == 'row' && value is Map) {
      final time = value['time'];
      if (time is int) return time;
      if (time is String) {
        return DateTime.tryParse(time)?.millisecondsSinceEpoch ?? 0;
      }
    }
    return 0;
  }

  Future<bool> _reconcile(
    Directory root,
    RecordSyncDocument document,
    RecordSyncStore store,
    String scopeId,
    String excluded,
    RequestScope scope,
    List<(String, Map<String, dynamic>)> incoming,
    void Function(void Function())? publish,
    void Function() onApplied,
  ) => _application.exclusive(() async {
    scope.check();
    final staging = await root.createTemp('snapshot-');
    await _application.capture(staging);
    var actual = RecordSyncSnapshot.read(staging.path, excluded);
    var applied = false;
    Future<void> apply(Map<String, dynamic> target) async {
      if (RecordSyncDocument.equal(actual, target)) return;
      RecordSyncSnapshot.write(staging.path, target, excluded);
      await _application.apply(staging, scope, publish);
      onApplied();
      actual = target;
      applied = true;
    }

    if (document.pendingAfter != null) {
      await apply(document.recover(actual));
      document.baseline = Map.of(document.pendingAfter!);
      document.pendingBefore = null;
      document.pendingAfter = null;
      // Capture post-crash edits before merging any further remote versions.
      document.capture(actual);
      store.save(scopeId, document);
    }
    document.capture(
      actual,
      seedTime: document.records.isEmpty ? _seedTime : null,
    );
    for (final batch in incoming) {
      final packet = Map<String, dynamic>.from(batch.$2);
      final records = Map<String, dynamic>.from(packet['records'] as Map);
      records.removeWhere((key, value) {
        final parts = jsonDecode(key) as List;
        return parts[0] == 'setting' &&
            RecordSyncSnapshot.exclusions('').contains(parts[1]);
      });
      packet['records'] = records;
      document.merge(packet);
    }
    final target = document.projection;
    // Retain excluded remote fields in the causal document/checkpoint so this
    // device cannot erase another device's synchronized setting while compacting.
    target.removeWhere((key, value) {
      final parts = jsonDecode(key) as List;
      return parts[0] == 'setting' &&
          RecordSyncSnapshot.exclusions(excluded).contains(parts[1]);
    });
    document.pendingBefore = Map.of(actual);
    document.pendingAfter = Map.of(target);
    store.save(scopeId, document);
    await apply(target);
    document.baseline = Map.of(target);
    document.pendingBefore = null;
    document.pendingAfter = null;
    document.seen.addAll(incoming.map((b) => b.$1));
    store.save(scopeId, document);
    return applied;
  });
}

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
    await SourceTransactionJournal.checkReadyForTransfer(dataPath);
    await HistoryManager.cache?.waitForAsyncWrites();
    await appdata.saveData(false);
    await createAppDataSnapshot(
      dataPath,
      staging.path,
      settingsJson: jsonEncode(appdata.toJson()),
    );
  }

  @override
  Future<void> apply(
    Directory staging,
    RequestScope scope,
    void Function(void Function())? publish,
  ) async {
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
