import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/features/reader/bottom_actions.dart';
import 'package:venera_next/features/reader/image_favorite_controller.dart';
import 'package:venera_next/features/reader/platform_effects_controller.dart';

void main() {
  testWidgets(
    'custom order respects capabilities, hiding and active stop control',
    (tester) async {
      var running = false;
      final calls = <String>[];
      Future<void> mount() => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Wrap(
                children: buildReaderBottomActions(
                  context,
                  actionOrder: const [
                    'share',
                    'fullscreen',
                    'automatic',
                    'save',
                  ],
                  hiddenActions: const {'collect', 'brightness', 'automatic'},
                  imageFavoriteStatus: ReaderImageFavoriteStatus.uncollected,
                  onCollect: () {},
                  orientation: ReaderOrientation.system,
                  brightnessEnabled: false,
                  onBrightness: () {},
                  automaticReading: ReaderAutomaticReadingAction(
                    tooltip: 'automatic',
                    active: running,
                    playing: running,
                    onPressed: () => calls.add('stop'),
                  ),
                  onSave: () => calls.add('save'),
                  onShare: () => calls.add('share'),
                ),
              ),
            ),
          ),
        ),
      );
      await mount();
      expect(find.byIcon(Icons.fullscreen), findsNothing);
      expect(find.byIcon(Icons.favorite_border), findsNothing);
      expect(find.byIcon(Icons.play_circle_outline), findsNothing);
      expect(
        tester.getTopLeft(find.byIcon(Icons.share)).dx,
        lessThan(tester.getTopLeft(find.byIcon(Icons.download)).dx),
      );
      await tester.tap(find.byIcon(Icons.share));
      expect(calls, ['share']);
      running = true;
      await mount();
      await tester.tap(find.byIcon(Icons.pause_circle_outline));
      expect(calls, ['share', 'stop']);
      expect(tester.takeException(), isNull);
    },
  );
}
