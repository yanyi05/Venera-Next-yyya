import 'package:flutter/material.dart';
import 'package:venera_next/foundation/interface_customization.dart';
import 'package:venera_next/features/discovery/discovery.dart';
import 'package:venera_next/features/favorites/favorites.dart';
import 'package:venera_next/features/search/search.dart';
import 'package:venera_next/features/settings/settings.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/foundation/application_preferences.dart';
import 'package:venera_next/foundation/global_preference_store.dart';
import 'package:venera_next/foundation/translations.dart';

import '../components/navigation_bar.dart';
import 'package:venera_next/routing/app_navigation.dart';
import '../foundation/context.dart';
import 'home_page.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  late final NaviObserver _observer;

  GlobalKey<NavigatorState>? _navigatorKey;

  void to(Widget Function() widget, {bool preventDuplicate = false}) async {
    if (preventDuplicate) {
      var page = widget();
      if ("/${page.runtimeType}" == _observer.routes.last.toString()) return;
    }
    _navigatorKey!.currentContext!.to(widget);
  }

  @override
  void initState() {
    _observer = NaviObserver();
    _navigatorKey = GlobalKey();
    appNavigation.mainNavigatorKey = _navigatorKey;
    index = int.parse(
      GlobalPreferenceStore(
        appdata.settings,
      ).read(DiscoveryPreferences.initialPage),
    );
    super.initState();
  }

  final _pages = [
    const HomePage(),
    const FavoritesPage(key: PageStorageKey('favorites')),
    const ExplorePage(key: PageStorageKey('explore')),
    const CategoriesPage(key: PageStorageKey('categories')),
  ];

  var index = 0;
  late final _navigationOrder = InterfaceCustomization.read(
    appdata.settings[InterfaceCustomization.storageKey],
  ).navigationOrder;
  int _pageId(int position) => InterfaceCustomization.navigationDefaults
      .indexOf(_navigationOrder[position]);

  @override
  Widget build(BuildContext context) {
    final entries = <PaneItemEntry>[
      PaneItemEntry(
        logicalIndex: 0,
        label: 'Home'.tl,
        icon: Icons.home_outlined,
        activeIcon: Icons.home,
      ),
      PaneItemEntry(
        logicalIndex: 1,
        label: 'Favorites'.tl,
        icon: Icons.local_activity_outlined,
        activeIcon: Icons.local_activity,
      ),
      PaneItemEntry(
        logicalIndex: 2,
        label: 'Explore'.tl,
        icon: Icons.explore_outlined,
        activeIcon: Icons.explore,
      ),
      PaneItemEntry(
        logicalIndex: 3,
        label: 'Categories'.tl,
        icon: Icons.category_outlined,
        activeIcon: Icons.category,
      ),
    ];
    return NaviPane(
      initialPage: _navigationOrder.indexOf(
        InterfaceCustomization.navigationDefaults[index],
      ),
      observer: _observer,
      navigatorKey: _navigatorKey!,
      paneItems: [
        for (final id in _navigationOrder)
          entries[InterfaceCustomization.navigationDefaults.indexOf(id)],
      ],
      onPageChanged: (i) {
        setState(() {
          index = _pageId(i);
        });
      },
      paneActions: [
        if (index != 0)
          PaneActionEntry(
            icon: Icons.search,
            label: "Search".tl,
            onTap: () {
              to(() => const SearchPage(), preventDuplicate: true);
            },
          ),
        PaneActionEntry(
          icon: Icons.settings,
          label: "Settings".tl,
          onTap: () {
            to(() => const SettingsPage(), preventDuplicate: true);
          },
        ),
      ],
      pageBuilder: (index) {
        return _pages[_pageId(index)];
      },
    );
  }
}
