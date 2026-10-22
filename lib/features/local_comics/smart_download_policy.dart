enum SmartDownloadNetwork { wifi, wifiAndMobile }

enum SmartDownloadPower { charging, anytime }

enum SmartDownloadTransport { wifi, mobile, other }

class SmartDownloadPolicy {
  const SmartDownloadPolicy({
    this.enabled = false,
    this.ahead = 3,
    this.network = SmartDownloadNetwork.wifi,
    this.power = SmartDownloadPower.charging,
  });
  final bool enabled;
  final int ahead;
  final SmartDownloadNetwork network;
  final SmartDownloadPower power;

  factory SmartDownloadPolicy.fromJson(dynamic value) {
    final data = value is Map ? value : const {};
    return SmartDownloadPolicy(
      enabled: data['enabled'] == true,
      ahead: (data['ahead'] is num ? (data['ahead'] as num).toInt() : 3).clamp(
        1,
        10,
      ),
      network: data['network'] == 'wifiAndMobile'
          ? SmartDownloadNetwork.wifiAndMobile
          : SmartDownloadNetwork.wifi,
      power: data['power'] == 'anytime'
          ? SmartDownloadPower.anytime
          : SmartDownloadPower.charging,
    );
  }
  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'ahead': ahead,
    'network': network.name,
    'power': power.name,
  };

  bool allows({
    required bool foreground,
    required Set<SmartDownloadTransport> transports,
    required bool? charging,
  }) {
    if (!enabled || !foreground) return false;
    if (power == SmartDownloadPower.charging && charging != true) return false;
    if (network == SmartDownloadNetwork.wifi) {
      return transports.contains(SmartDownloadTransport.wifi) &&
          !transports.contains(SmartDownloadTransport.mobile);
    }
    return transports.contains(SmartDownloadTransport.wifi) ||
        transports.contains(SmartDownloadTransport.mobile);
  }

  List<String> plan({
    required List<String> chapters,
    required String current,
    required Set<String> downloaded,
  }) {
    final index = chapters.indexOf(current);
    if (!enabled || index < 0) return [];
    return chapters
        .skip(index + 1)
        .take(ahead.clamp(1, 10))
        .where((id) => !downloaded.contains(id))
        .toSet()
        .toList();
  }
}

/// Fail closed until the foreground runtime has checked device conditions.
/// Manual transfers never consult this gate.
abstract final class AutomaticDownloadGate {
  static bool allowed = false;
}
