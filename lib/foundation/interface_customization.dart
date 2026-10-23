/// Small immutable, device-local presentation preferences. No IO or timers.
class InterfaceCustomization {
  static const storageKey = 'interfaceCustomization';
  static const homeDefaults = [
    'sync',
    'history',
    'later',
    'local',
    'updates',
    'sources',
    'images',
  ];
  static const toolbarDefaults = [
    'collect',
    'fullscreen',
    'rotate',
    'brightness',
    'automatic',
    'chapters',
    'mask',
    'crop',
    'reload',
    'verify',
    'save',
    'share',
  ];
  static const navigationDefaults = [
    'home',
    'favorites',
    'explore',
    'categories',
  ];

  InterfaceCustomization.read(Object? value) {
    final map = value is Map ? value : const {};
    homeOrder = normalizeOrder(map['homeOrder'], homeDefaults);
    toolbarOrder = normalizeOrder(map['toolbarOrder'], toolbarDefaults);
    navigationOrder = normalizeOrder(
      map['navigationOrder'],
      navigationDefaults,
    );
    hiddenHome = _hidden(map['hiddenHome'], homeDefaults);
    hiddenToolbar = _hidden(map['hiddenToolbar'], toolbarDefaults);
  }
  late final List<String> homeOrder, toolbarOrder, navigationOrder;
  late final Set<String> hiddenHome, hiddenToolbar;

  static List<String> normalizeOrder(Object? raw, List<String> defaults) =>
      List.unmodifiable({
        if (raw is List)
          for (final id in raw)
            if (id is String && defaults.contains(id)) id,
        ...defaults,
      });
  static Set<String> _hidden(Object? raw, List<String> defaults) =>
      Set.unmodifiable(
        raw is List
            ? raw.whereType<String>().where(defaults.contains)
            : <String>[],
      );
  Map<String, Object> toJson() => {
    'homeOrder': homeOrder,
    'toolbarOrder': toolbarOrder,
    'navigationOrder': navigationOrder,
    'hiddenHome': hiddenHome.toList(),
    'hiddenToolbar': hiddenToolbar.toList(),
  };
}
