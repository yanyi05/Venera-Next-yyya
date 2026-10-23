import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/components/navigation_bar.dart';
import 'package:venera_next/features/discovery/explore_page.dart';
import 'package:venera_next/features/comic_source/comic_source.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/foundation/res.dart';

class _Source extends Fake implements ComicSource {
  _Source(this.explorePages);
  @override
  String get key => 'demo';
  @override
  final List<ExplorePageData> explorePages;
  @override
  String get name => 'Demo';
  @override
  AccountConfig? get account => null;
  @override
  Map<String, Map<String, String>>? get translations => null;
}

class _Changes extends ChangeNotifier {
  bool get retained => hasListeners;
}

void main() {
  late ComicSourceManager manager;
  late List<ComicSource> registry;
  late Object? previous;
  setUp(() {
    previous = appdata.settings['explore_pages'];
    appdata.settings['explore_pages'] = ['Demo'];
    manager = ComicSourceManager();
    registry = [];
    configureComicSourceRegistry(
      all: () => registry,
      find: (key) => registry.where((source) => source.key == key).firstOrNull,
      fromIntKey: (_) => registry.firstOrNull,
      isEmpty: () => registry.isEmpty,
    );
  });
  tearDown(() async {
    appdata.settings['explore_pages'] = previous;
    await manager.closeAndWait();
    configureComicSourceRegistry(
      all: () => [],
      find: (_) => null,
      fromIntKey: (_) => null,
      isEmpty: () => true,
    );
  });
  ExplorePageData page(
    Future<Res<List<ExplorePagePart>>> Function() load, {
    Listenable? changes,
    Future<void> Function()? onRefresh,
  }) => ExplorePageData(
    'Demo',
    ExplorePageType.singlePageWithMultiPart,
    null,
    null,
    load,
    null,
    changeListenable: changes,
    onRefresh: onRefresh,
  );
  Future<void> mount(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: NaviPane(
        paneItems: [
          PaneItemEntry(
            label: 'Explore',
            logicalIndex: 2,
            icon: Icons.explore,
            activeIcon: Icons.explore,
          ),
        ],
        paneActions: const [],
        observer: NaviObserver(),
        navigatorKey: GlobalKey<NavigatorState>(),
        pageBuilder: (_) => const ExplorePage(),
      ),
    ),
  );

  testWidgets(
    'source replacement with unchanged tab title discards closed callbacks and old errors',
    (tester) async {
      var oldCalls = 0, newCalls = 0;
      final changes = _Changes();
      registry = [
        _Source([
          page(() async {
            oldCalls++;
            return const Res.error('old callback scope is closed');
          }, changes: changes),
        ]),
      ];
      await mount(tester);
      await tester.pumpAndSettle();
      expect(find.text('old callback scope is closed'), findsOneWidget);
      expect(oldCalls, greaterThan(0));
      final retiredCalls = oldCalls;
      expect(changes.retained, isTrue);
      registry = [
        _Source([
          page(() async {
            newCalls++;
            return const Res([]);
          }),
        ]),
      ];
      manager.notifyListeners();
      await tester.pumpAndSettle();
      expect(newCalls, greaterThan(0));
      expect(oldCalls, retiredCalls);
      expect(changes.retained, isFalse);
      expect(find.text('old callback scope is closed'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      changes.dispose();
    },
  );

  testWidgets('pending old provider results never replace the new provider', (
    tester,
  ) async {
    final oldResult = Completer<Res<List<ExplorePagePart>>>();
    var oldCalls = 0, newCalls = 0;
    registry = [
      _Source([
        page(() {
          oldCalls++;
          return oldResult.future;
        }),
      ]),
    ];
    await mount(tester);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    final pendingCalls = oldCalls;
    for (var i = 0; i < 3; i++) {
      manager.notifyListeners();
      await tester.pump();
    }
    expect(oldCalls, pendingCalls);
    registry = [
      _Source([
        page(() async {
          newCalls++;
          return const Res([]);
        }),
      ]),
    ];
    manager.notifyListeners();
    await tester.pumpAndSettle();
    oldResult.complete(const Res.error('late stale failure'));
    await tester.pumpAndSettle();
    expect(newCalls, greaterThan(0));
    expect(find.text('late stale failure'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'source removal handles empty discovery and refresh without indexing a removed tab',
    (tester) async {
      registry = [
        _Source([page(() async => const Res([]))]),
      ];
      await mount(tester);
      await tester.pumpAndSettle();
      registry = [];
      manager.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.byType(TabBarView), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
