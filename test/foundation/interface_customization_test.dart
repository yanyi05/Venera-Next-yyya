import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/foundation/interface_customization.dart';
import 'package:venera_next/foundation/app_data_sync_fields.dart';

void main() {
  test('old and malformed settings keep every default destination', () {
    for (final raw in [
      null,
      false,
      'bad',
      {'navigationOrder': 1},
    ]) {
      final value = InterfaceCustomization.read(raw);
      expect(value.navigationOrder, InterfaceCustomization.navigationDefaults);
      expect(value.hiddenToolbar, isEmpty);
    }
  });
  test(
    'orders retain known unique entries and append missing capabilities',
    () {
      final value = InterfaceCustomization.read({
        'toolbarOrder': ['share', 'share', 'unknown', 1, 'save'],
        'hiddenToolbar': ['crop', 'unknown', false],
        'navigationOrder': ['explore', 'home'],
      });
      expect(value.toolbarOrder.take(2), ['share', 'save']);
      expect(
        value.toolbarOrder.toSet(),
        InterfaceCustomization.toolbarDefaults.toSet(),
      );
      expect(value.hiddenToolbar, {'crop'});
      expect(value.navigationOrder, [
        'explore',
        'home',
        'favorites',
        'categories',
      ]);
      expect(() => value.toolbarOrder.add('x'), throwsUnsupportedError);
      expect(
        InterfaceCustomization.read(value.toJson()).toJson(),
        value.toJson(),
      );
      expect(appDataLocalFields, contains(InterfaceCustomization.storageKey));
    },
  );
}
