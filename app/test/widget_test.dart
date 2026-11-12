import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:speedll_connect_app/main.dart';
import 'package:speedll_connect_app/application/connection/connection_controller.dart';
import 'package:speedll_connect_app/application/localization/locale_controller.dart';
import 'package:speedll_connect_app/data/storage/secure_profile_storage.dart';
import 'package:speedll_connect_app/presentation/home/widgets/language_onboarding_dialog.dart';
import 'package:speedll_connect_app/presentation/home/widgets/theme_onboarding_dialog.dart';
import 'package:speedll_connect_app/domain/diagnostics/diagnostic_error_mapper.dart';
import 'package:speedll_connect_app/domain/engine/connection_engine.dart';
import 'package:speedll_connect_app/domain/engine/windows_vpn_engine_adapter.dart';
import 'package:speedll_connect_app/domain/connection/connection_phase.dart';
import 'package:speedll_connect_app/domain/ping/ping_service.dart';
import 'package:speedll_connect_app/domain/profiles/country_flag_resolver.dart';
import 'package:speedll_connect_app/domain/scanner/qr_scanner_service.dart';
import 'package:speedll_connect_app/domain/version/app_version.dart';
import 'package:speedll_connect_app/application/theme/theme_controller.dart';
import 'package:speedll_subscription/speedll_subscription.dart';

class MockConnectionEngine implements ConnectionEngine {
  final StreamController<ConnectionPhase> phaseController =
      StreamController<ConnectionPhase>.broadcast();
  final List<ServerProfile> connectedProfiles = <ServerProfile>[];

  @override
  String get engineId => 'mock-engine';

  @override
  Stream<ConnectionPhase> get connectionPhases => phaseController.stream;

  @override
  Future<void> connect(ServerProfile profile) async {
    connectedProfiles.add(profile);
    phaseController.add(ConnectionPhase.connected);
  }

  @override
  Future<void> disconnect() async {
    phaseController.add(ConnectionPhase.disconnected);
  }

  @override
  Future<EngineCapabilityReport> inspectProfile(ServerProfile profile) async {
    return const EngineCapabilityReport(supported: true, reasons: []);
  }
}

class FakeQrScannerService implements QrScannerService {
  FakeQrScannerService(this.scannedPayload);
  final String? scannedPayload;

  @override
  Future<String?> scanQrCode() async => scannedPayload;
}

void main() {
  setUp(() {
    FlutterSecureStorage.clearFallbackStore();
  });

  testWidgets('shows Speedll Connect interface, status and import action',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectionEngineProvider.overrideWithValue(MockConnectionEngine()),
        ],
        child: const SpeedllConnectApp(),
      ),
    );

    expect(find.text('Speedll Connect'), findsOneWidget);
    expect(find.text('قطع شده'), findsOneWidget);
    expect(find.byTooltip('افزودن اشتراک یا کانفیگ'), findsOneWidget);
  });

  test(
      'SecureProfileStorage isolates secrets from metadata and cleans up on delete',
      () async {
    const rawStorage = FlutterSecureStorage();
    const profileStorage = SecureProfileStorage(secureStorage: rawStorage);

    const sampleProfile = ServerProfile(
      id: 'de-vless-01',
      displayName: 'آلمان ریالیتی',
      protocol: 'vless',
      source: ProfileSource.manual,
      serverAddress: '198.51.100.10',
      serverPort: 443,
      extraParams: {
        'uuid': '00000000-0000-0000-0000-000000000001',
        'pbk': '1111111111111111111111111111111111111111111=',
        'security': 'reality',
        'sni': 'de.speedll-sample.test',
      },
    );

    await profileStorage.saveProfiles([sampleProfile]);

    // Verify metadata stored in speedll_profiles_v1 does NOT contain sensitive uuid or pbk
    final rawMetadata = await rawStorage.read(key: 'speedll_profiles_v1');
    expect(rawMetadata, isNotNull);
    expect(
        rawMetadata, isNot(contains('00000000-0000-0000-0000-000000000001')));
    expect(
      rawMetadata,
      isNot(contains('1111111111111111111111111111111111111111111=')),
    );

    // Verify secret is stored separately under speedll_secret_de-vless-01
    final rawSecret = await rawStorage.read(key: 'speedll_secret_de-vless-01');
    expect(rawSecret, isNotNull);
    final secretJson = jsonDecode(rawSecret!) as Map<String, dynamic>;
    expect(
      secretJson['uuid'],
      equals('00000000-0000-0000-0000-000000000001'),
    );

    // Verify loadProfiles rehydrates the full profile accurately
    final loaded = await profileStorage.loadProfiles();
    expect(loaded.length, equals(1));
    expect(
      loaded.first.extraParams['uuid'],
      equals('00000000-0000-0000-0000-000000000001'),
    );
    expect(loaded.first.extraParams['sni'], equals('de.speedll-sample.test'));

    // Verify deleting profile secret removes it from secure storage
    await profileStorage.deleteProfileSecret('de-vless-01');
    expect(
      await rawStorage.read(key: 'speedll_secret_de-vless-01'),
      isNull,
    );
  });

  testWidgets('imports server profile via QR code camera scanner button',
      (tester) async {
    const sampleQrUri =
        'vless://00000000-0000-0000-0000-000000000001@198.51.100.10:443?type=tcp&security=reality&pbk=1111111111111111111111111111111111111111111=&fp=chrome#QR-Server-DE';

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectionEngineProvider.overrideWithValue(MockConnectionEngine()),
          qrScannerServiceProvider.overrideWithValue(
            FakeQrScannerService(sampleQrUri),
          ),
        ],
        child: const SpeedllConnectApp(),
      ),
    );

    await tester.tap(find.byTooltip('افزودن اشتراک یا کانفیگ'));
    await tester.pumpAndSettle();

    expect(find.text('اسکن بارکد QR با دوربین'), findsOneWidget);
    await tester.tap(find.text('اسکن بارکد QR با دوربین'));
    await tester.pumpAndSettle();

    // Verify the QR-scanned server is now selected on the home screen
    expect(find.text('آلمان'), findsOneWidget);
  });

  test('DiagnosticErrorMapper maps codes and redacts UUIDs, IPs, and secrets',
      () {
    const rawError =
        'failed:ERR-CORE-CONFIG uuid=00000000-0000-0000-0000-000000000001 server=198.51.100.10:443 vless://secret@198.51.100.10:443';
    final report = DiagnosticErrorMapper.fromCodeOrError(rawError);

    expect(report.code, equals('ERR-CORE-CONFIG'));
    expect(report.formattedDisplay, contains('ERR-CORE-CONFIG'));
    expect(report.formattedDisplay,
        isNot(contains('00000000-0000-0000-0000-000000000001')));
    expect(report.formattedDisplay, isNot(contains('198.51.100.10')));
    expect(report.redactedDetail,
        isNot(contains('00000000-0000-0000-0000-000000000001')));
    expect(report.redactedDetail, isNot(contains('198.51.100.10')));
    expect(report.redactedDetail, isNot(contains('vless://secret')));

    final tunAdmin = DiagnosticErrorMapper.fromCodeOrError('ERR-TUN-ADMIN');
    expect(tunAdmin.code, equals('ERR-TUN-ADMIN'));
    expect(tunAdmin.userMessage, contains('Administrator'));

    final missingCore =
        DiagnosticErrorMapper.fromCodeOrError('ERR-CORE-BINARY-MISSING');
    expect(missingCore.code, equals('ERR-CORE-BINARY-MISSING'));
    expect(missingCore.userMessage, contains('هسته'));
  });

  testWidgets('HomeScreen reflects reconnecting and diagnostic failure states',
      (tester) async {
    final mockEngine = MockConnectionEngine();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectionEngineProvider.overrideWithValue(mockEngine),
        ],
        child: const SpeedllConnectApp(),
      ),
    );

    mockEngine.phaseController.add(ConnectionPhase.reconnecting);
    await tester.pump();
    expect(find.text('تلاش مجدد اتصال...'), findsOneWidget);

    mockEngine.phaseController.add(ConnectionPhase.failed);
    await tester.pump();
    expect(find.text('خطا در برقراری اتصال'), findsOneWidget);
    expect(find.textContaining('ERR-CONN-GENERAL'), findsOneWidget);
  });

  test(
      'CountryFlagResolver and PingService Smart Mode select lowest ping and hot-switch while connected',
      () async {
    const deProfile = ServerProfile(
      id: 'de-01',
      displayName: '🇩🇪 http WS direct vlessآلمان',
      protocol: 'vless',
      source: ProfileSource.subscription,
      serverAddress: '198.51.100.10',
      serverPort: 80,
    );
    const trProfile = ServerProfile(
      id: 'tr-01',
      displayName: '🇹🇷 سرور ترکیه',
      protocol: 'vless',
      source: ProfileSource.subscription,
      serverAddress: '198.51.100.20',
      serverPort: 443,
    );

    final deLoc = CountryFlagResolver.resolve(deProfile);
    expect(deLoc.countryCode, equals('DE'));
    expect(deLoc.flagEmoji, equals('🇩🇪'));

    final pingService = PingService(
      customProber: (profile) async => profile.id == 'tr-01' ? 38 : 110,
    );
    final pings = await pingService.measureAllPings([deProfile, trProfile]);
    final best = pingService.pickBestProfile([deProfile, trProfile], pings);
    expect(best?.id, equals('tr-01'));
  });

  test(
      'PingService skips 127.0.0.1 subscription info nodes and ThemePresets + AppVersion are valid',
      () {
    const infoNode = ServerProfile(
      id: 'info-01',
      displayName: '📊 حجم باقیمانده: 45 GB',
      protocol: 'vless',
      source: ProfileSource.subscription,
      serverAddress: '127.0.0.1',
      serverPort: 1080,
      extraParams: {'isInfoNode': true},
    );
    const realServer = ServerProfile(
      id: 'de-real',
      displayName: '🇩🇪 آلمان VIP',
      protocol: 'vless',
      source: ProfileSource.subscription,
      serverAddress: '198.51.100.55',
      serverPort: 443,
    );

    expect(PingService.isConnectableServer(infoNode), isFalse);
    expect(PingService.isConnectableServer(realServer), isTrue);

    const pingService = PingService();
    final chosen = pingService.pickBestProfile(
      [infoNode, realServer],
      const {'info-01': 1, 'de-real': 65},
    );
    expect(chosen?.id, equals('de-real'));

    expect(SpeedllThemePreset.values.length, equals(6));
    for (final preset in SpeedllThemePreset.values) {
      final palette = SpeedllThemePalette.of(preset);
      expect(palette.backgroundGradient.length, greaterThanOrEqualTo(3));
    }
    expect(
      AppVersion.fullVersion,
      equals('${AppVersion.versionName} (Build ${AppVersion.buildNumber})'),
    );
    expect(AppVersion.versionName, equals('1.9.0'));
    expect(AppVersion.buildNumber, equals(15));

    final winAdapter = WindowsVpnEngineAdapter(useTunAdapter: true);
    final desktopConfig =
        winAdapter.buildDesktopConfig(realServer, listenPort: 34567);
    final inbounds = desktopConfig['inbounds'] as List;
    expect(inbounds.length, equals(2));
    final mixedInbound = inbounds.first as Map;
    expect(mixedInbound['listen_port'], equals(34567));
    expect(mixedInbound.containsKey('set_system_proxy'), isFalse);
    final tunInbound = inbounds.last as Map;
    expect(tunInbound['inet6_address'], isNotNull);
    expect(tunInbound['strict_route'], isTrue);
  });

  testWidgets(
      'Tapping Connect button when no profiles exist opens ImportSubscriptionDialog',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectionEngineProvider.overrideWithValue(MockConnectionEngine()),
        ],
        child: const SpeedllConnectApp(),
      ),
    );

    await tester.tap(find.byIcon(Icons.power_settings_new_rounded));
    await tester.pumpAndSettle();

    expect(find.text('اسکن بارکد QR با دوربین'), findsOneWidget);
  });

  test(
      'Smart Mode locks onto best server when connected and fails over after 2 unhealthy checks',
      () async {
    const s1 = ServerProfile(
      id: 'srv-1',
      displayName: 'Server 1',
      protocol: 'vless',
      source: ProfileSource.subscription,
      serverAddress: '198.51.100.11',
      serverPort: 443,
    );
    const s2 = ServerProfile(
      id: 'srv-2',
      displayName: 'Server 2',
      protocol: 'vless',
      source: ProfileSource.subscription,
      serverAddress: '198.51.100.12',
      serverPort: 443,
    );

    var s1Latency = 42;
    var s2Latency = 95;
    final mockEngine = MockConnectionEngine();
    final pingService = PingService(
      customProber: (profile) async =>
          profile.id == 'srv-1' ? s1Latency : s2Latency,
    );

    final container = ProviderContainer(
      overrides: [
        connectionEngineProvider.overrideWithValue(mockEngine),
        pingServiceProvider.overrideWithValue(pingService),
      ],
    );
    addTearDown(container.dispose);

    await container.read(profilesListProvider.notifier).addProfiles([s1, s2]);
    final controller = container.read(connectionControllerProvider.notifier);
    await controller.setSmartMode(true);

    // Connect in Smart Mode -> picks srv-1 (42ms) and locks onto it
    await controller.toggleConnection();
    await Future<void>.delayed(Duration.zero);

    var state = container.read(connectionControllerProvider);
    expect(state.isConnected, isTrue);
    expect(state.activeProfile?.id, equals('srv-1'));
    expect(state.isSmartLocked, isTrue);

    // Even if srv-2 becomes faster (25ms) during a manual pingAllProfiles,
    // Smart Mode stays locked on srv-1 while srv-1 is healthy!
    s2Latency = 25;
    await controller.pingAllProfiles();
    state = container.read(connectionControllerProvider);
    expect(state.activeProfile?.id, equals('srv-1'));

    // Now srv-1 goes down (-1 timeout) for 2 consecutive health checks -> auto-failover to srv-2
    s1Latency = -1;
    await controller.checkSmartConnectionHealth();
    expect(
        container.read(connectionControllerProvider).activeProfile?.id, 'srv-1');
    await controller.checkSmartConnectionHealth();
    state = container.read(connectionControllerProvider);
    expect(state.activeProfile?.id, equals('srv-2'));
    expect(state.isSmartLocked, isTrue);
  });

  test(
      'SecureProfileStorage defaults enableTrafficSniffing to false and migrates v2 installs',
      () async {
    const rawStorage = FlutterSecureStorage();
    const profileStorage = SecureProfileStorage(secureStorage: rawStorage);

    // Fresh install defaults to OFF
    final fresh = await profileStorage.loadRoutingOptions();
    expect(fresh.enableTrafficSniffing, isFalse);

    // Upgrade from dnsDefaultsVersion < 3 with sniffing=true migrates to OFF
    await rawStorage.write(
      key: 'speedll_routing_options_v1',
      value: jsonEncode(<String, dynamic>{
        'dnsDefaultsVersion': 2,
        'enableTrafficSniffing': true,
        'remoteDnsServer': '1.1.1.1',
        'directDnsServer': '8.8.8.8',
      }),
    );
    final migrated = await profileStorage.loadRoutingOptions();
    expect(migrated.enableTrafficSniffing, isFalse);
    expect(migrated.directDnsServer, equals('8.8.8.8'));

    // Explicit opt-in saved at v3+ persists ON
    await profileStorage.saveRoutingOptions(
      migrated.copyWith(enableTrafficSniffing: true),
    );
    final saved = await profileStorage.loadRoutingOptions();
    expect(saved.enableTrafficSniffing, isTrue);
  });

  testWidgets(
      'Home screen hides live ping and server IP until VPN is connected',
      (tester) async {
    const storage = SecureProfileStorage();
    const profile = ServerProfile(
      id: 'srv-ip-1',
      displayName: 'Germany-01',
      protocol: 'vless',
      source: ProfileSource.manual,
      serverAddress: '198.51.100.42',
      serverPort: 443,
      extraParams: <String, dynamic>{
        'uuid': '00000000-0000-0000-0000-000000000001',
      },
    );
    await storage.saveProfiles(const <ServerProfile>[profile]);
    await storage.saveActiveProfileId(profile.id);
    await storage.saveAppLanguageCode('fa');
    await storage.saveHasCompletedLanguageOnboarding(true);

    final mockEngine = MockConnectionEngine();
    final pingService = PingService(customProber: (_) async => 88);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectionEngineProvider.overrideWithValue(mockEngine),
          pingServiceProvider.overrideWithValue(pingService),
        ],
        child: const SpeedllConnectApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Disconnected: server IP and live ping must be hidden
    expect(find.text('قطع شده'), findsOneWidget);
    expect(find.text('198.51.100.42'), findsNothing);
    expect(find.textContaining('پینگ لحظه‌ای'), findsNothing);

    // Connect: server IP and live ping become visible
    await tester.tap(find.byIcon(Icons.power_settings_new_rounded));
    await tester.pumpAndSettle();

    expect(find.text('متصل شد'), findsOneWidget);
    expect(find.text('198.51.100.42'), findsOneWidget);
    expect(find.textContaining('پینگ لحظه‌ای'), findsOneWidget);

    // Disconnect again: hidden once more
    await tester.tap(find.byIcon(Icons.power_settings_new_rounded));
    await tester.pumpAndSettle();

    expect(find.text('198.51.100.42'), findsNothing);
    expect(find.textContaining('پینگ لحظه‌ای'), findsNothing);
  });

  testWidgets(
      'First launch opens Language onboarding then Theme onboarding dialog',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectionEngineProvider.overrideWithValue(MockConnectionEngine()),
          localeControllerProvider.overrideWith(
            (ref) => LocaleController(
              storage: ref.watch(secureProfileStorageProvider),
              isTestOverride: false,
            ),
          ),
        ],
        child: const SpeedllConnectApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LanguageOnboardingDialog), findsOneWidget);
    expect(find.byType(ThemeOnboardingDialog), findsNothing);

    // Choose English and confirm
    await tester.tap(find.text('English'));
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byType(LanguageOnboardingDialog),
        matching: find.byType(FilledButton),
      ),
    );
    await tester.pumpAndSettle();

    // Theme onboarding opens next in the chosen English language
    expect(find.byType(LanguageOnboardingDialog), findsNothing);
    expect(find.byType(ThemeOnboardingDialog), findsOneWidget);
    expect(find.text('Choose Default Theme'), findsOneWidget);

    // Pick Ocean Blue and confirm
    await tester.tap(find.text('Ocean Blue'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(ThemeOnboardingDialog),
        matching: find.byType(FilledButton),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ThemeOnboardingDialog), findsNothing);
    expect(await const SecureProfileStorage().loadThemePresetName(),
        equals('oceanBlue'));
  });

  testWidgets('Manual DNS input validates bad inputs and saves valid ones',
      (tester) async {
    const storage = SecureProfileStorage();
    await storage.saveAppLanguageCode('fa');
    await storage.saveHasCompletedLanguageOnboarding(true);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectionEngineProvider.overrideWithValue(MockConnectionEngine()),
        ],
        child: const SpeedllConnectApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Switch to Settings tab
    await tester.tap(find.byIcon(Icons.settings_rounded));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('سرور DNS مستقیم (Direct DNS)'),
      250,
    );
    await tester.tap(find.text('سرور DNS مستقیم (Direct DNS)'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('DNS دستی'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '999.999.999.999');
    await tester.tap(find.text('انتخاب'));
    await tester.pump();

    // Invalid input shows error and keeps dialog open
    expect(
      find.text('آدرس DNS معتبر نیست؛ یک IP معتبر وارد کنید.'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField), '8.8.8.8');
    await tester.tap(find.text('انتخاب'));
    await tester.pumpAndSettle();

    final savedRouting = await storage.loadRoutingOptions();
    expect(savedRouting.directDnsServer, equals('8.8.8.8'));
  });

  test(
      'PingService strictly stays on IPv4 when preferIpv6 is false and prefers IPv6 when enabled',
      () async {
    PingService.clearDnsCache();

    var v6Queried = false;
    final pingService = PingService(
      customDnsLookup: (host, type) async {
        if (type == InternetAddressType.IPv6) {
          v6Queried = true;
          return <InternetAddress>[InternetAddress('2a01:4f8::1')];
        }
        return <InternetAddress>[InternetAddress('198.51.100.10')];
      },
    );

    const domainProfile = ServerProfile(
      id: 'dual-1',
      displayName: 'DualStack Server',
      protocol: 'vless',
      source: ProfileSource.manual,
      serverAddress: 'dualstack.example.com',
      serverPort: 443,
    );

    // 1. Default IPv4 mode must NOT query or select IPv6 automatically
    final v4Targets = await pingService.resolveTargetCandidates(
      'dualstack.example.com',
      preferIpv6: false,
    );
    expect(v6Queried, isFalse);
    expect(v4Targets, equals(const <String>['198.51.100.10']));
    expect(
      PingService.resolveServerIpSync(domainProfile, preferIpv6: false),
      equals('198.51.100.10'),
    );

    // 2. Opt-in IPv6 mode prioritizes IPv6 first while keeping IPv4 fallback
    final v6Targets = await pingService.resolveTargetCandidates(
      'dualstack.example.com',
      preferIpv6: true,
    );
    expect(v6Queried, isTrue);
    expect(v6Targets, equals(const <String>['2a01:4f8::1', '198.51.100.10']));
    expect(
      PingService.resolveServerIpSync(domainProfile, preferIpv6: true),
      equals('2a01:4f8::1'),
    );

    // 3. Literal bracketed IPv6 server strips brackets cleanly
    const bracketedIpv6Profile = ServerProfile(
      id: 'lit-v6',
      displayName: 'Literal IPv6',
      protocol: 'vless',
      source: ProfileSource.manual,
      serverAddress: '[2001:db8::42]',
      serverPort: 443,
    );
    expect(
      PingService.resolveServerIpSync(bracketedIpv6Profile, preferIpv6: true),
      equals('2001:db8::42'),
    );
  });

  testWidgets(
      'Settings IPv6 toggle defaults OFF, persists enableIpv6, Home displays IPv6 badge & decoded base64 sub title',
      (tester) async {
    const storage = SecureProfileStorage();
    await storage.saveAppLanguageCode('fa');
    await storage.saveHasCompletedLanguageOnboarding(true);
    await storage.saveThemePresetName('royalViolet');
    await storage.saveRoutingOptions(const SingboxRoutingOptions());

    const ipv6Profile = ServerProfile(
      id: 'srv-v6-1',
      displayName: '🇩🇪 Germany IPv6',
      protocol: 'vless',
      source: ProfileSource.subscription,
      serverAddress: '2001:db8::abcd:1234',
      serverPort: 443,
      extraParams: <String, dynamic>{
        'subscriptionId': 'sub-b64',
        'uuid': '11111111-1111-1111-1111-111111111111',
      },
    );
    await storage.saveProfiles(const <ServerProfile>[ipv6Profile]);
    await storage.saveActiveProfileId(ipv6Profile.id);

    // Simulate legacy corrupted saved JSON containing raw "اشتراک base64:bW9qdGFiYQ=="
    final corruptedSub = SubscriptionSource.fromJson(const <String, dynamic>{
      'id': 'sub-b64',
      'name': 'اشتراک base64:bW9qdGFiYQ==',
      'url': 'https://example.com/sub/secret',
    });
    await storage.saveSubscriptions(<SubscriptionSource>[corruptedSub]);

    final mockEngine = MockConnectionEngine();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectionEngineProvider.overrideWithValue(mockEngine),
        ],
        child: const SpeedllConnectApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Decoded title renders instead of raw base64
    expect(find.text('اشتراک mojtaba'), findsOneWidget);
    expect(find.textContaining('base64:'), findsNothing);

    // Connect and verify Home Screen displays the IPv6 address badge cleanly
    await tester.tap(find.byIcon(Icons.power_settings_new_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.text('2001:db8::abcd:1234'), findsOneWidget);

    // Verify enableIpv6 defaults to false before toggling
    final initialRouting = await storage.loadRoutingOptions();
    expect(initialRouting.enableIpv6, isFalse);

    // Navigate to Settings and toggle IPv6 Support ON
    await tester.tap(find.byIcon(Icons.settings_rounded));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('پشتیبانی از IPv6'),
      250,
    );
    expect(find.text('پشتیبانی از IPv6'), findsOneWidget);

    await tester.tap(find.text('پشتیبانی از IPv6'));
    await tester.pumpAndSettle();

    final updatedRouting = await storage.loadRoutingOptions();
    expect(updatedRouting.enableIpv6, isTrue);
  });
}
