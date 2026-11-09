import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/features/reader/resource_budget.dart';

void main() {
  testWidgets('memory pressure stops speculation and recovers after cooldown', (
    tester,
  ) async {
    final budget = ReaderResourceBudget(mobile: true);
    addTearDown(budget.dispose);
    expect(budget.cacheBytes, 128 << 20);
    expect(budget.preloadCount(99), 6);
    budget.memoryPressure();
    expect(budget.cacheBytes, 32 << 20);
    expect(budget.preloadCount(6), 0);
    await tester.pump(const Duration(minutes: 1));
    expect(budget.preloadCount(6), 6);
    budget.setForeground(false);
    expect(budget.preloadCount(6), 0);
    budget.setForeground(true);
    expect(budget.cacheBytes, 128 << 20);
  });
  test('preload follows direction, bounds and reduced rapid-jump budget', () {
    final plan = ReaderPreloadPlan(), time = DateTime(2026);
    expect(plan.pages(5, 3, 20, now: time).toList(), [6, 7, 8, 4]);
    expect(
      plan.pages(4, 3, 20, now: time.add(const Duration(seconds: 1))).toList(),
      [3, 2, 1, 5],
    );
    expect(
      plan
          .pages(15, 3, 20, now: time.add(const Duration(milliseconds: 1100)))
          .toList(),
      [16, 14],
    );
    expect(plan.pages(1, 0, 20, now: time).toList(), isEmpty);
  });
}
