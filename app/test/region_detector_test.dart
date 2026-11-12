import 'package:flutter_test/flutter_test.dart';
import 'package:speedll_subscription/speedll_subscription.dart';
import 'package:speedll_connect_app/domain/routing/region_detector.dart';

void main() {
  test('RegionDetector uses country, timezone, then language', () {
    expect(
      RegionDetector.detect(locale: 'fa_IR', timeZone: 'UTC'),
      RoutingRegion.iran,
    );
    expect(
      RegionDetector.detect(locale: 'zh_CN', timeZone: 'UTC'),
      RoutingRegion.china,
    );
    expect(
      RegionDetector.detect(locale: 'ru_RU', timeZone: 'UTC'),
      RoutingRegion.russia,
    );
    expect(
      RegionDetector.detect(locale: 'en_US', timeZone: 'Asia/Tehran'),
      RoutingRegion.iran,
    );
    expect(
      RegionDetector.detect(locale: 'en_US', timeZone: 'Asia/Shanghai'),
      RoutingRegion.china,
    );
    expect(
      RegionDetector.detect(locale: 'en_US', timeZone: 'Europe/Moscow'),
      RoutingRegion.russia,
    );
    expect(
      RegionDetector.detect(locale: 'fa', timeZone: 'UTC'),
      RoutingRegion.iran,
    );
  });

  test('RegionDetector keeps Iran fallback for unknown regions', () {
    expect(
      RegionDetector.detect(locale: 'en_US', timeZone: 'Europe/Berlin'),
      RoutingRegion.iran,
    );
  });
}
