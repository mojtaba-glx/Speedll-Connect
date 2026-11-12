import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:speedll_connect_app/main.dart';
import 'package:speedll_connect_app/application/connection/connection_controller.dart';
import 'package:speedll_connect_app/data/storage/secure_profile_storage.dart';
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
    expect(AppVersion.fullVersion, equals('1.8.0 (Build 14)'));

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
}
