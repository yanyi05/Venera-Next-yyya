import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/features/local_comics/local.dart';
import 'package:venera_next/foundation/window_placement_tracker.dart';
import 'package:venera_next/foundation/window_hotkey_controller.dart';
import 'package:venera_next/routing/app_links.dart';
import 'package:venera_next/routing/handle_text_share.dart';

import 'interactive_bindings.dart';
import 'windows_heartbeat.dart';
import 'android_downloads.dart';

/// Assemble UI event handlers at the interactive application boundary.
InteractiveBindings createPlatformInteractiveBindings({
  WindowPlacementTracker? placement,
  WindowHotkeyController? windowHotkey,
}) {
  final heartbeat = WindowsHeartbeat();
  final local = LocalManager.current;
  final downloads = App.isAndroid && local != null
      ? AndroidDownloads(manager: local)
      : null;
  return InteractiveBindings(
    android: App.isAndroid,
    windows: App.isWindows,
    links: createAppLinkSubscription,
    shares: createTextShareSubscription,
    heartbeat: heartbeat.send,
    closeHeartbeat: heartbeat.close,
    placement: placement,
    windowHotkey: windowHotkey,
    startDownloads: downloads?.start,
    closeDownloads: downloads?.close,
  );
}
