import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/features/comic_widgets/comic_widgets.dart';
import 'package:venera_next/features/favorites/favorite_models.dart';
import 'package:venera_next/features/favorites/favorites_manager.dart';
import 'package:venera_next/features/favorites/favorites_scope.dart';
import 'package:venera_next/features/favorites/local_favorites_page.dart';
import 'package:venera_next/features/history/history.dart';
import 'package:venera_next/features/history/history_scope.dart';
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/foundation/application_preferences.dart';
import 'package:venera_next/foundation/comic_type.dart';
import 'package:venera_next/foundation/opencc.dart';

FavoriteItem _comic(String id, String title) => FavoriteItem(
  id: id,
  name: title,
  author: '',
  type: const ComicType(17),
  tags: const [],
  coverPath: '',
);

Finder _tile(String id) => find.byWidgetPredicate(
  (widget) => widget is ComicTile && widget.comic.id == id,
);

class _Fixture {
  final manager = LocalFavoritesManager.independent();
  final history = HistoryManager.create();
  final navigator = GlobalKey<NavigatorState>();

  Widget host({String folder = 'B'}) => FavoritesScope(
    manager: manager,
    child: HistoryScope(
      manager: history,
      child: MaterialApp(
        navigatorKey: navigator,
        home: Scaffold(
          body: LocalFavoritesPage(
            folder: folder,
            showFolders: () {},
            onFolderSelected: (_, _) {},
            updateFolderList: () {},
          ),
        ),
      ),
    ),
  );
}

Future<_Fixture> _prepare(WidgetTester tester, int count) async {
  final root = Directory('build').absolute.createTempSync('favorite-refresh-');
  final buildRoot = Directory('build').resolveSymbolicLinksSync();
  final previousPath = App.dataPath;
  final previousCachePath = App.cachePath;
  final settings = Map<String, dynamic>.from(
    appdata.toJson()['settings'] as Map,
  );
  final implicit = appdata.implicitData;
  final fixture = _Fixture();
  App.dataPath = root.path;
  App.cachePath = root.path;
  appdata.settings['language'] = 'en-US';
  appdata.settings[FavoritePreferences.newFavoriteAddTo.key] = 'start';
  appdata.settings['blockedWords'] = <String>[];
  appdata.settings[KeywordPreferences.comics.key] = <String>[];
  appdata.settings['showFavoriteStatusOnTile'] = false;
  appdata.settings['showHistoryStatusOnTile'] = false;
  appdata.settings['showUpdateStatusOnTile'] = false;
  appdata.implicitData = {'local_favorites_read_filter': 'All'};
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('window_manager'),
    (_) async => false,
  );
  configureComicWidgets(
    addStateListener: (listener) {
      fixture.manager.addListener(listener);
      fixture.history.addListener(listener);
    },
    removeStateListener: (listener) {
      fixture.manager.removeListener(listener);
      fixture.history.removeListener(listener);
    },
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await fixture.manager.closeAndWait();
      fixture.history.close();
    });
    configureComicWidgets();
    settings.forEach((key, value) => appdata.settings[key] = value);
    appdata.implicitData = implicit;
    App.dataPath = previousPath;
    App.cachePath = previousCachePath;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      null,
    );
    expect(
      root.resolveSymbolicLinksSync(),
      startsWith('$buildRoot${Platform.pathSeparator}'),
    );
    root.deleteSync(recursive: true);
  });
  await tester.runAsync(() async {
    await OpenCC.init();
    await fixture.manager.init();
    await fixture.history.init();
    await fixture.manager.createFolder('A');
    await fixture.manager.createFolder('B');
    if (count > 0) {
      await fixture.manager.addComics(
        'B',
        List.generate(count, (i) => _comic('seed-$i', 'Existing $i')),
      );
    }
  });
  return fixture;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  for (
    var i = 0;
    i < 1000 &&
        find
            .byType(CircularProgressIndicator, skipOffstage: false)
            .evaluate()
            .isNotEmpty;
    i++
  ) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  expect(
    find.byType(CircularProgressIndicator, skipOffstage: false),
    findsNothing,
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  App.dataPath = Directory.systemTemp.path;
  App.cachePath = Directory.systemTemp.path;

  testWidgets(
    'reading-status exclusions are explained without bypassing the filter',
    (tester) async {
      final fixture = await _prepare(tester, 1);
      appdata.implicitData['local_favorites_read_filter'] = 'Completed';
      await tester.pumpWidget(fixture.host());
      await _settle(tester);
      expect(_tile('seed-0'), findsNothing);
      expect(
        find.text('Hidden by reading-status filter: 1 comics'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      expect(_tile('seed-0'), findsOneWidget);
      expect(
        find.text('Hidden by reading-status filter: 1 comics'),
        findsNothing,
      );
    },
  );

  for (final count in [0, 499, 500]) {
    for (final query in ['', 'New']) {
      for (final covered in [false, true]) {
        testWidgets(
          'search follows additions and deletions: count=$count query=$query covered=$covered',
          (tester) async {
            final fixture = await _prepare(tester, count);
            await tester.pumpWidget(fixture.host());
            await _settle(tester);
            await tester.tap(find.byTooltip('Search'));
            await tester.pumpAndSettle();
            if (query.isNotEmpty) {
              await tester.enterText(find.byType(TextField), query);
            }
            await tester.pumpAndSettle();
            if (covered) {
              unawaited(
                fixture.navigator.currentState!.push<void>(
                  MaterialPageRoute(
                    builder: (_) => const Scaffold(body: Text('Details')),
                  ),
                ),
              );
              await tester.pumpAndSettle();
            }
            await tester.runAsync(
              () => fixture.manager.addComic(
                'B',
                _comic('new', 'New matching comic'),
              ),
            );
            await _settle(tester);
            if (covered) {
              fixture.navigator.currentState!.pop();
              await tester.pumpAndSettle();
            }
            expect(_tile('new'), findsOneWidget);
            expect(
              tester
                  .widget<EditableText>(find.byType(EditableText))
                  .controller
                  .text,
              query,
            );
            await tester.runAsync(
              () => fixture.manager.deleteComicWithId(
                'B',
                'new',
                const ComicType(17),
              ),
            );
            await _settle(tester);
            expect(_tile('new'), findsNothing);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  testWidgets('switching folders replaces the active search results', (
    tester,
  ) async {
    final fixture = await _prepare(tester, 500);
    await tester.runAsync(() async {
      await fixture.manager.addComic('B', _comic('from-b', 'New comic B'));
      await fixture.manager.addComic('A', _comic('from-a', 'New comic A'));
    });
    await tester.pumpWidget(fixture.host());
    await _settle(tester);
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'New');
    await tester.pumpAndSettle();
    expect(_tile('from-b'), findsOneWidget);
    await tester.pumpWidget(fixture.host(folder: 'A'));
    await _settle(tester);
    expect(_tile('from-a'), findsOneWidget);
    expect(_tile('from-b'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
