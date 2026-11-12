import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speedll_connect_app/application/localization/app_strings.dart';
import 'package:speedll_connect_app/application/theme/theme_controller.dart';
import 'package:speedll_connect_app/presentation/home/widgets/subscription_usage_card.dart';
import 'package:speedll_subscription/speedll_subscription.dart';

void main() {
  testWidgets('SubscriptionUsageCard renders usage and expiry', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final source = SubscriptionSource(
      id: 'sub-card',
      name: 'اشتراک تست',
      url: 'https://sub.speedll-sample.test/sub',
      userInfo: SubscriptionUserInfo(
        consumedBytes: (28.2 * 1024 * 1024 * 1024).round(),
        totalBytes: 50 * 1024 * 1024 * 1024,
        expiresAt: DateTime.now().toUtc().add(const Duration(days: 12)),
      ),
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.rtl,
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SubscriptionUsageCard(
                source: source,
                strings: const AppStrings(AppLanguage.fa),
                palette: SpeedllThemePalette.of(SpeedllThemePreset.royalPurple),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('اشتراک تست'), findsOneWidget);
    expect(find.text('56%'), findsOneWidget);
    expect(find.text('28.2 GB / 50.0 GB'), findsOneWidget);
    expect(find.text('21.8 GB'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
