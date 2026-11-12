import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speedll_connect_app/application/connection/connection_controller.dart';
import 'package:speedll_connect_app/data/storage/secure_profile_storage.dart';
import 'package:speedll_connect_app/presentation/home/widgets/select_server_dialog.dart';
import 'package:speedll_subscription/speedll_subscription.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.clearFallbackStore();
  });

  testWidgets('SelectServerDialog implements Design 2 cleanly without search or all tab', (tester) async {
    const sub1 = SubscriptionSource(
      id: 'sub_ali',
      name: 'اشتراک علی',
      url: 'https://panel.example.com/sub/ali#ali',
      userInfo: SubscriptionUserInfo(
        consumedBytes: 10 * 1024 * 1024 * 1024,
        totalBytes: 50 * 1024 * 1024 * 1024,
      ),
    );

    const sub2 = SubscriptionSource(
      id: 'sub_reza',
      name: 'اشتراک رضا',
      url: 'https://panel.example.com/sub/reza#reza',
    );

    const srv1 = ServerProfile(
      id: 'srv_de',
      displayName: 'آلمان ۱',
      protocol: 'vless',
      source: ProfileSource.subscription,
      serverAddress: '198.51.100.1',
      serverPort: 443,
      extraParams: {'subscriptionId': 'sub_ali'},
    );

    const rawStorage = FlutterSecureStorage();
    const profileStorage = SecureProfileStorage(secureStorage: rawStorage);

    final container = ProviderContainer(
      overrides: [
        secureProfileStorageProvider.overrideWithValue(profileStorage),
      ],
    );

    // Seed subscriptions and servers
    await container.read(subscriptionsListProvider.notifier).addOrUpdateSubscription(sub1);
    await container.read(subscriptionsListProvider.notifier).addOrUpdateSubscription(sub2);
    await container.read(profilesListProvider.notifier).addProfiles([srv1]);
    await container.read(connectionControllerProvider.notifier).selectProfile(srv1);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: SelectServerDialog(initialSubscriptionId: 'sub_ali'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify Title
    expect(find.text('پروفایل‌های من'), findsOneWidget);

    // Verify Search bar is NOT present
    expect(find.byType(TextField), findsNothing);

    // Verify "همه" tab is NOT present
    expect(find.textContaining('همه ('), findsNothing);

    // Verify Subscription Cards with user names are present
    expect(find.text('اشتراک علی'), findsOneWidget);
    expect(find.text('اشتراک رضا'), findsOneWidget);

    // Verify Active status indicator
    expect(find.text('فعال'), findsOneWidget);

    // Verify Delete button exists for each card
    expect(find.byIcon(Icons.delete_outline_rounded), findsWidgets);

    // Verify Configs of active subscription are visible
    expect(find.text('آلمان ۱'), findsOneWidget);

    // Dispose container to cancel background timers
    container.dispose();
  });
}
