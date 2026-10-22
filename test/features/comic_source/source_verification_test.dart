import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/components/loading.dart';
import 'package:venera_next/features/comic_source/comic_source_page.dart';
import 'package:venera_next/features/comic_source/source.dart';
import 'package:venera_next/foundation/appdata.dart';
import '../../support/comic_source_fixture.dart';

void main() {
  final sources = <ComicSource>[];
  ComicSource source(String key) => ComicSourceFixture(
    key: key,
    account: AccountConfig(
      null,
      'https://$key.test/',
      null,
      () {},
      (_, _) => true,
      null,
      null,
      null,
    ),
  );

  setUp(() {
    appdata.settings['language'] = 'en';
    sources.clear();
    configureComicSourceRegistry(
      all: () => sources,
      find: (key) => sources.where((source) => source.key == key).firstOrNull,
      fromIntKey: (_) => null,
      isEmpty: () => sources.isEmpty,
    );
  });

  for (final message in [
    '需要通过网站验证: please login',
    'CloudflareException: https://site.test/',
  ]) {
    testWidgets('source action survives error classification: $message', (
      tester,
    ) async {
      var pressed = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: NetworkError(
            message: message,
            retry: () {},
            withAppbar: false,
            action: TextButton(
              onPressed: () => pressed++,
              child: const Text('Website verification'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Website verification'));
      expect(pressed, 1);
    });
  }

  testWidgets(
    'mixed-source verification asks before opening and cancellation does not reload',
    (tester) async {
      sources.addAll([source('one'), source('two')]);
      var returned = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SourceVerificationButton(onReturned: () => returned++),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Website verification'));
      await tester.pumpAndSettle();
      expect(find.text('Choose source to verify'), findsOneWidget);
      expect(find.byType(SimpleDialogOption), findsNWidgets(2));
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(returned, 0);
    },
  );

  testWidgets('local or unsupported source has no verification action', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SourceVerificationButton(sourceKey: 'local')),
      ),
    );
    expect(find.byType(IconButton), findsNothing);
  });
}
