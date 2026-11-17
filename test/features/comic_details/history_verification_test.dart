import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/features/comic_details/comic_page.dart';
import 'package:venera_next/features/comic_source/comic_source_api.dart';
import 'package:venera_next/features/comic_source/comic_source_page.dart';
import 'package:venera_next/features/favorites/favorites_manager.dart';
import 'package:venera_next/features/history/history_manager.dart';
import 'package:venera_next/features/local_comics/local.dart';
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/foundation/res.dart';

class _Source extends Fake implements ComicSource {
  int calls = 0;
  @override
  String get key => 'history-source';
  @override
  AccountConfig get account => AccountConfig(
    null,
    'https://example.test/',
    null,
    () {},
    null,
    null,
    null,
    null,
  );
  @override
  LoadComicFunc get loadComicInfo => (id) async {
    calls++;
    return const Res.error('Website session expired');
  };
}

void main() {
  testWidgets('history comic details failure offers verification and retries', (
    tester,
  ) async {
    final root = Directory.systemTemp.createTempSync('details-verification-');
    final oldLanguage = appdata.settings['language'];
    App.dataPath = root.path;
    App.cachePath = root.path;
    appdata.settings['language'] = 'en-US';
    final source = _Source();
    final manager = ComicSourceManager();
    configureComicSourceRegistry(
      all: () => [source],
      find: (key) => key == source.key ? source : null,
      fromIntKey: (_) => source,
      isEmpty: () => false,
    );
    LocalManager.current?.dispose();
    LocalManager(initializeSources: () async {});
    await tester.runAsync(() async {
      Directory('${root.path}/comics').createSync();
      File('${root.path}/local_path').writeAsStringSync('${root.path}/comics');
      await HistoryManager().init();
      await LocalFavoritesManager().init();
      await LocalManager().init();
    });
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      LocalManager.current?.dispose();
      LocalFavoritesManager().close();
      HistoryManager().close();
      HistoryManager().dispose();
      await manager.closeAndWait();
      configureComicSourceRegistry(
        all: () => [],
        find: (_) => null,
        fromIntKey: (_) => null,
        isEmpty: () => true,
      );
      appdata.settings['language'] = oldLanguage;
      root.deleteSync(recursive: true);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: ComicPage(id: 'saved-book', sourceKey: source.key),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Website session expired'), findsOneWidget);
    final button = tester.widget<SourceVerificationButton>(
      find.byType(SourceVerificationButton),
    );
    expect(button.sourceKey, source.key);
    expect(button.label, isTrue);
    final before = source.calls;
    button.onReturned!();
    await tester.pumpAndSettle();
    expect(source.calls, greaterThan(before));
    expect(tester.takeException(), isNull);
  });
}
