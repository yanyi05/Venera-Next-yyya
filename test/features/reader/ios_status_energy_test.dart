import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/features/reader/status_polling.dart';

void main() {
  testWidgets(
    'iOS status wakes at minute boundaries and stops while inactive',
    (tester) async {
      var now = DateTime(2026, 10, 22, 10, 0, 20);
      var calls = 0;
      final polling = ReaderStatusPolling(
        alignToMinute: true,
        now: () => now,
        onChanged: () {},
        readBattery: () async {
          calls++;
          return const ReaderBatterySnapshot(80, charging: false);
        },
      );
      polling.setActive(true);
      await tester.pump();
      expect(calls, 1);
      now = DateTime(2026, 10, 22, 10, 0, 59);
      await tester.pump(const Duration(seconds: 39));
      expect(calls, 1);
      now = DateTime(2026, 10, 22, 10, 1);
      await tester.pump(const Duration(seconds: 1));
      expect(calls, 2);
      expect(polling.time, '10:01');
      polling.setActive(false);
      await tester.pump(const Duration(minutes: 3));
      expect(calls, 2);
      polling.setActive(true);
      await tester.pump();
      expect(calls, 3);
      await polling.closeAndWait();
      await tester.pump(const Duration(minutes: 3));
      expect(calls, 3);
    },
  );
}
