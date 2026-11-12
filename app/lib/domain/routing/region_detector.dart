import 'dart:io';

import 'package:speedll_subscription/speedll_subscription.dart';

/// Detects the device region using locale and timezone. The default is Iran to
/// preserve existing behavior for upgrades from versions without a region field.
class RegionDetector {
  const RegionDetector._();

  static RoutingRegion detect({String? locale, String? timeZone}) {
    final normalizedLocale = (locale ?? Platform.localeName)
        .trim()
        .toLowerCase()
        .replaceAll('-', '_');
    final parts = normalizedLocale.split('_');
    final language = parts.first;
    final country = parts.length > 1 ? parts[1] : '';

    if (const <String>{'ir'}.contains(country)) return RoutingRegion.iran;
    if (const <String>{'cn', 'hk', 'mo'}.contains(country)) {
      return RoutingRegion.china;
    }
    if (const <String>{'ru'}.contains(country)) return RoutingRegion.russia;

    final tz = (timeZone ?? DateTime.now().timeZoneName).toLowerCase();
    if (tz.contains('iran') || tz.contains('tehran')) {
      return RoutingRegion.iran;
    }
    if (tz.contains('china') ||
        tz.contains('shanghai') ||
        tz.contains('chongqing') ||
        tz.contains('harbin') ||
        tz.contains('urumqi')) {
      return RoutingRegion.china;
    }
    if (tz.contains('russia') ||
        tz.contains('moscow') ||
        tz.contains('yekaterinburg') ||
        tz.contains('novosibirsk') ||
        tz.contains('vladivostok') ||
        tz.contains('kaliningrad') ||
        tz.contains('samara') ||
        tz.contains('omsk') ||
        tz.contains('krasnoyarsk') ||
        tz.contains('irkutsk') ||
        tz.contains('magadan') ||
        tz.contains('kamchatka')) {
      return RoutingRegion.russia;
    }

    if (language == 'fa') return RoutingRegion.iran;
    if (language == 'zh') return RoutingRegion.china;
    if (language == 'ru') return RoutingRegion.russia;

    return RoutingRegion.iran;
  }
}
