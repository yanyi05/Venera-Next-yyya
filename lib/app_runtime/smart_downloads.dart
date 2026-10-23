import 'dart:async';
import 'package:venera_next/foundation/reading_activity.dart';
import 'dart:convert';
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/foundation/log.dart';
import 'package:venera_next/foundation/comic_type.dart';
import 'package:venera_next/foundation/smart_download_request.dart';
import 'package:venera_next/features/comic_source/comic_source_api.dart';
import 'package:venera_next/features/local_comics/local.dart';
import 'package:venera_next/features/local_comics/images_download_task.dart';
import 'package:venera_next/features/local_comics/smart_download_policy.dart';

/// No polling: queue/reader/settings changes and native network/power events
/// drive low-priority downloads. Unknown conditions reject automatic requests.
class SmartDownloadsRuntime {
  SmartDownloadsRuntime({
    LocalManager? Function()? library,
    Future<List<ConnectivityResult>> Function()? readNetwork,
    Stream<List<ConnectivityResult>> Function()? watchNetwork,
    Future<BatteryState> Function()? readPower,
    Stream<BatteryState> Function()? watchPower,
  }) : _findLibrary = library ?? (() => LocalManager.current),
       _readNetwork = readNetwork ?? (() => Connectivity().checkConnectivity()),
       _watchNetwork =
           watchNetwork ?? (() => Connectivity().onConnectivityChanged),
       _readPower = readPower ?? (() => Battery().batteryState),
       _watchPower = watchPower ?? (() => Battery().onBatteryStateChanged);
  static final instance = SmartDownloadsRuntime();
  final LocalManager? Function() _findLibrary;
  final Future<List<ConnectivityResult>> Function() _readNetwork;
  final Stream<List<ConnectivityResult>> Function() _watchNetwork;
  final Future<BatteryState> Function() _readPower;
  final Stream<BatteryState> Function() _watchPower;
  bool _running = false, _evaluating = false, _again = false;
  int _epoch = 0, _networkRevision = 0, _powerRevision = 0;
  String? _directory;
  LocalManager? _library;
  Timer? _scheduled;
  Timer? _cleanupTimer;
  bool _cleaning = false;
  int _cleanupRetryAfter = 0;

  void _readingChanged() {
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    if (!ReadingActivity.instance.isReading) _scheduleCleanup();
  }

  void _scheduleCleanup() {
    if (!_running ||
        _cleaning ||
        _cleanupTimer != null ||
        !_policy.cleanupEnabled ||
        ReadingActivity.instance.isReading ||
        _directory != App.dataPath) {
      return;
    }
    final library = _library;
    if (library == null ||
        !identical(library, _findLibrary()) ||
        library.downloadingTasks.isNotEmpty) {
      return;
    }
    try {
      final entries = library.automaticCleanupCandidates();
      if (entries.isEmpty) return;
      final delay = Duration(hours: _policy.retentionHours).inMilliseconds;
      var next = entries
          .map((e) => e.readAt + delay)
          .reduce((a, b) => a < b ? a : b);
      if (next < _cleanupRetryAfter) next = _cleanupRetryAfter;
      final remaining = next - DateTime.now().millisecondsSinceEpoch;
      _cleanupTimer = Timer(
        Duration(milliseconds: remaining < 2000 ? 2000 : remaining),
        () {
          _cleanupTimer = null;
          unawaited(_cleanupOne());
        },
      );
    } catch (error, stack) {
      _report(error, stack);
    }
  }

  Future<void> _cleanupOne() async {
    if (_cleaning ||
        !_running ||
        !_policy.cleanupEnabled ||
        ReadingActivity.instance.isReading) {
      return;
    }
    final library = _library;
    if (library == null ||
        !identical(library, _findLibrary()) ||
        _directory != App.dataPath) {
      return;
    }
    _cleaning = true;
    try {
      final cutoff = DateTime.now()
          .subtract(Duration(hours: _policy.retentionHours))
          .millisecondsSinceEpoch;
      final entries = library.automaticCleanupCandidates().where(
        (e) => e.readAt <= cutoff,
      );
      if (entries.isEmpty) return;
      final entry = entries.first;
      await ReadingActivity.instance.runMaintenance(
        () => library.cleanAutomaticChapter(
          entry,
          () =>
              _running &&
              _policy.cleanupEnabled &&
              _directory == App.dataPath &&
              identical(library, _findLibrary()) &&
              entry.readAt <=
                  DateTime.now()
                      .subtract(Duration(hours: _policy.retentionHours))
                      .millisecondsSinceEpoch,
        ),
      );
      _cleanupRetryAfter = 0;
    } catch (error, stack) {
      _cleanupRetryAfter = DateTime.now()
          .add(const Duration(minutes: 1))
          .millisecondsSinceEpoch;
      _report(error, stack);
    } finally {
      _cleaning = false;
      _scheduleCleanup();
    }
  }

  StreamSubscription<List<ConnectivityResult>>? _networkSubscription;
  StreamSubscription<BatteryState>? _powerSubscription;
  final _attempted = <String>{};
  ImagesDownloadTask? _lastAutomatic;
  Set<SmartDownloadTransport> _transports = {};
  bool? _charging;
  SmartDownloadPolicy get _policy =>
      SmartDownloadPolicy.fromJson(appdata.settings['smartDownloads']);

  void start() {
    if (_running) {
      unawaited(_refresh());
      return;
    }
    _running = true;
    if (_directory != App.dataPath) {
      _lastAutomatic = null;
      _attempted.clear();
    }
    _directory = App.dataPath;
    _library = _findLibrary();
    _library?.addListener(_schedule);
    ReadingActivity.instance.addListener(_readingChanged);
    appdata.settings.addListener(_settingsChanged);
    SmartDownloadRequests.instance.addListener(_schedule);
    _settingsChanged();
  }

  void stop() {
    _running = false;
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    ReadingActivity.instance.removeListener(_readingChanged);
    _scheduled?.cancel();
    _scheduled = null;
    _library?.removeListener(_schedule);
    appdata.settings.removeListener(_settingsChanged);
    SmartDownloadRequests.instance.removeListener(_schedule);
    _closeEnvironment();
    _setGate(false);
  }

  void _report(Object error, StackTrace stack) =>
      Log.error('Smart downloads', error, stack);
  void _closeEnvironment() {
    _epoch++;
    final network = _networkSubscription, power = _powerSubscription;
    _networkSubscription = null;
    _powerSubscription = null;
    if (network != null) unawaited(network.cancel().catchError(_report));
    if (power != null) unawaited(power.cancel().catchError(_report));
    _transports = {};
    _charging = null;
  }

  void _settingsChanged() {
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    _scheduleCleanup();
    try {
      _applySettings();
    } catch (error, stack) {
      _closeEnvironment();
      _setGate(false);
      _report(error, stack);
    }
  }

  void _applySettings() {
    if (!_running) return;
    if (!_policy.enabled) {
      _closeEnvironment();
      _setGate(false);
      return;
    }
    if (_networkSubscription == null) {
      final epoch = _epoch;
      _networkSubscription = _watchNetwork().listen(
        (values) {
          if (!_running || epoch != _epoch) return;
          _networkRevision++;
          _transports = _convert(values);
          _updateGate();
          _schedule();
        },
        onError: (Object error, StackTrace stack) {
          if (epoch != _epoch) return;
          _transports = {};
          _updateGate();
          _report(error, stack);
        },
      );
      _powerSubscription = _watchPower().listen(
        (state) {
          if (!_running || epoch != _epoch) return;
          _powerRevision++;
          _charging = _isCharging(state);
          _updateGate();
          _schedule();
        },
        onError: (Object error, StackTrace stack) {
          if (epoch != _epoch) return;
          _charging = null;
          _updateGate();
          _report(error, stack);
        },
      );
      unawaited(_refresh());
    }
    _updateGate();
    _schedule();
  }

  static Set<SmartDownloadTransport> _convert(
    List<ConnectivityResult> values,
  ) => {
    if (values.contains(ConnectivityResult.wifi)) SmartDownloadTransport.wifi,
    if (values.contains(ConnectivityResult.mobile))
      SmartDownloadTransport.mobile,
  };
  static bool? _isCharging(BatteryState state) => switch (state) {
    BatteryState.charging || BatteryState.full => true,
    BatteryState.discharging => false,
    _ => null,
  };
  Future<void> _refresh() async {
    if (!_running || !_policy.enabled) return;
    final epoch = _epoch, net = _networkRevision, power = _powerRevision;
    await Future.wait<void>([
      () async {
        try {
          final values = await _readNetwork();
          if (_running && epoch == _epoch && net == _networkRevision) {
            _transports = _convert(values);
          }
        } catch (error, stack) {
          if (epoch == _epoch && net == _networkRevision) _transports = {};
          _report(error, stack);
        }
      }(),
      () async {
        try {
          final state = await _readPower();
          if (_running && epoch == _epoch && power == _powerRevision) {
            _charging = _isCharging(state);
          }
        } catch (error, stack) {
          if (epoch == _epoch && power == _powerRevision) _charging = null;
          _report(error, stack);
        }
      }(),
    ]);
    if (!_running || epoch != _epoch) return;
    _updateGate();
    _schedule();
  }

  void _updateGate() => _setGate(
    _policy.allows(
      foreground:
          _running &&
          _directory == App.dataPath &&
          _library != null &&
          identical(_library, _findLibrary()),
      transports: _transports,
      charging: _charging,
    ),
  );
  void _setGate(bool allowed) {
    AutomaticDownloadGate.allowed = allowed;
    final library = _library;
    final first = library?.downloadingTasks.firstOrNull;
    if (!allowed && first?.isAutomatic == true && !first!.isPaused) {
      unawaited(
        library!
            .pauseDownload(first, automaticPolicy: true)
            .catchError(_report),
      );
    }
  }

  void _schedule() {
    if (!_running || _scheduled != null) return;
    _scheduled = Timer(const Duration(milliseconds: 250), () {
      _scheduled = null;
      unawaited(_evaluate());
    });
  }

  static String _signature(
    String source,
    String comic,
    List<String> chapters,
  ) => jsonEncode([source, comic, chapters]);
  Future<void> _evaluate() async {
    if (_evaluating) {
      _again = true;
      return;
    }
    _evaluating = true;
    _scheduleCleanup();
    try {
      if (!_running || _directory != App.dataPath) return;
      final library = _library;
      if (library == null || !identical(library, _findLibrary())) return;
      _updateGate();
      for (final task
          in library.downloadingTasks.whereType<ImagesDownloadTask>()) {
        if (task.automatic) {
          _attempted.add(
            _signature(task.source.key, task.comicId, task.chapters ?? []),
          );
        }
      }
      if (!AutomaticDownloadGate.allowed) return;
      final first = library.downloadingTasks.firstOrNull;
      if (first?.canAutomaticallyResume == true && first!.isPaused) {
        library.resumeDownload(first);
      }
      if (library.downloadingTasks.any((task) => task.isAutomatic)) return;
      final target = SmartDownloadRequests.instance.target;
      if (target == null ||
          target.directory != _directory ||
          target.source == 'local') {
        return;
      }
      final source = ComicSource.find(target.source);
      if (source == null ||
          source.loadComicInfo == null ||
          source.loadComicPages == null) {
        return;
      }
      final type = ComicType(source.key.hashCode);
      if (library.isDownloading(target.comic, type)) return;
      final downloaded =
          library.find(target.comic, type)?.downloadedChapters.toSet() ??
          <String>{};
      final chapters = _policy.plan(
        chapters: target.chapters,
        current: target.chapter,
        downloaded: downloaded,
      );
      if (chapters.isEmpty) return;
      // Commit one chapter at a time so it becomes immediately readable offline.
      final selected = [chapters.first];
      final signature = _signature(source.key, target.comic, selected);
      if (!_attempted.add(signature)) return;
      final previous = _lastAutomatic;
      final task = ImagesDownloadTask(
        storage: library,
        source: source,
        comicId: target.comic,
        comicTitle: target.title,
        comic:
            previous?.comicId == target.comic &&
                identical(previous?.source, source)
            ? previous?.comic
            : null,
        chapters: selected,
        automatic: true,
      );
      _lastAutomatic = task;
      library.addTask(task);
    } catch (error, stack) {
      _report(error, stack);
    } finally {
      _evaluating = false;
      if (_again) {
        _again = false;
        _schedule();
      }
    }
  }
}
