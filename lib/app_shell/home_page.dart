import 'package:venera_next/foundation/interface_customization.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/features/favorites/favorites_scope.dart';
import 'package:venera_next/features/history/history_scope.dart';
import 'package:flutter/material.dart';
import 'package:venera_next/components/scroll.dart';
import 'package:venera_next/features/comic_source/comic_source.dart';
import 'package:venera_next/foundation/consts.dart';
import 'package:venera_next/foundation/context.dart';
import 'package:venera_next/features/history/history.dart';
import 'package:venera_next/features/favorites/favorites.dart';
import 'package:venera_next/features/local_comics/local_comics.dart';
import 'package:venera_next/features/follow_updates/follow_updates.dart';
import 'package:venera_next/features/image_favorites/image_favorites.dart';
import 'package:venera_next/features/search/search.dart';
import 'package:venera_next/features/sync/sync.dart';
import 'package:venera_next/foundation/widget_utils.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late InterfaceCustomization _options;
  Object? _rawOptions;
  @override
  void initState() {
    super.initState();
    _rawOptions = appdata.settings[InterfaceCustomization.storageKey];
    _options = InterfaceCustomization.read(_rawOptions);
    appdata.settings.addListener(_refreshCustomization);
  }

  void _refreshCustomization() {
    final raw = appdata.settings[InterfaceCustomization.storageKey];
    if (identical(raw, _rawOptions)) return;
    _rawOptions = raw;
    final next = InterfaceCustomization.read(raw);
    if (next.toJson().toString() != _options.toJson().toString()) {
      setState(() => _options = next);
    }
  }

  @override
  void dispose() {
    appdata.settings.removeListener(_refreshCustomization);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget section(String id) => switch (id) {
      'sync' => const SyncStatusSummary(),
      'history' => HistorySummary(
        manager: HistoryScope.read(context),
        favoriteChanges: FavoritesScope.read(context),
      ),
      'later' => const ReadLaterSummary(),
      'local' => const LocalComicsSummary(),
      'updates' => const FollowUpdatesWidget(),
      'sources' => ComicSourceSummary(manager: ComicSourceManager.current),
      'images' => const ImageFavoritesSummary(),
      _ => const SliverToBoxAdapter(),
    };
    var widget = SmoothCustomScrollView(
      slivers: [
        SliverPadding(padding: EdgeInsets.only(top: context.padding.top)),
        const SearchEntry(),
        for (final id in _options.homeOrder)
          if (!_options.hiddenHome.contains(id))
            KeyedSubtree(key: ValueKey(id), child: section(id)),
        SliverPadding(padding: EdgeInsets.only(top: context.padding.bottom)),
      ],
    );
    return context.width > changePoint ? widget.paddingHorizontal(8) : widget;
  }
}
