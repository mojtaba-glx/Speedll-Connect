import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speedll_connect_app/application/connection/connection_controller.dart';
import 'package:speedll_connect_app/application/connection/connection_state.dart';
import 'package:speedll_connect_app/data/storage/secure_profile_storage.dart';
import 'package:speedll_connect_app/domain/connection/connection_phase.dart';
import 'package:speedll_connect_app/domain/engine/android_vpn_engine_adapter.dart';
import 'package:speedll_connect_app/domain/engine/connection_engine.dart';
import 'package:speedll_connect_app/domain/format/traffic_formatter.dart';
import 'package:speedll_connect_app/domain/share/share_qr_service.dart';
import 'package:speedll_connect_app/presentation/home/widgets/qr_share_dialog.dart';
import 'package:speedll_connect_app/presentation/home/widgets/select_server_dialog.dart';
import 'package:speedll_connect_app/presentation/home/widgets/statistics_panel.dart';
import 'package:speedll_subscription/speedll_subscription.dart';

class _TestVpnEngine implements ConnectionEngine {
  final StreamController<ConnectionPhase> phaseController =
      StreamController<ConnectionPhase>.broadcast();
  final List<ServerProfile> connectedProfiles = <ServerProfile>[];

  @override
  String get engineId => 'test-engine';

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

class _FakeShareAndQrService implements ShareAndQrService {
  String? lastSharedText;
  String? lastGeneratedQrText;

  @override
  Future<QrMatrixData?> generateQrMatrix(String text) async {
    lastGeneratedQrText = text;
    return const QrMatrixData(
      size: 3,
      modules: <int>[1, 0, 1, 0, 1, 0, 1, 0, 1],
    );
  }

  @override
  Future<bool> shareText(String text, {String? subject}) async {
    lastSharedText = text;
    return true;
  }
}

void main() {
  setUp(() {
    FlutterSecureStorage.clearFallbackStore();
  });

  test('TrafficFormatter and TrafficStatsSnapshot parse and format cleanly', () {
    final parsed = TrafficStatsSnapshot.tryParse('stats:2048:1048576:40960:20971520');
    expect(parsed, isNotNull);
    expect(parsed!.uplinkBps, 2048);
    expect(parsed.downlinkBps, 1048576);
    expect(parsed.uplinkTotalBytes, 40960);
    expect(parsed.downlinkTotalBytes, 20971520);
    expect(TrafficStatsSnapshot.tryParse('connected'), isNull);

    expect(TrafficFormatter.formatSpeed(0), '0 B/s');
    expect(TrafficFormatter.formatSpeed(1536), '1.50 KB/s');
    expect(TrafficFormatter.formatBytes(20971520), '20.0 MB');
    expect(TrafficFormatter.formatDurationHms(const Duration(hours: 2, minutes: 5, seconds: 9)), '02:05:09');
    expect(
      TrafficFormatter.formatAxisElapsed(
        const Duration(hours: 2, minutes: 15),
        totalSpan: const Duration(hours: 2, minutes: 15),
      ),
      '02:15',
    );
    expect(
      TrafficFormatter.formatConnectedHoursLabel(
        const Duration(hours: 2, minutes: 30),
        isPersian: true,
      ),
      '2.5 ساعت',
    );
    expect(TrafficFormatter.detectIpVersion('45.144.214.84'), 'IPv4');
    expect(TrafficFormatter.detectIpVersion('[2001:db8::1]'), 'IPv6');
    expect(TrafficFormatter.detectIpVersion('example.com'), isNull);
  });

  test('compactTrafficHistory spans multi-hour sessions while keeping initial anchor', () {
    var history = const <TrafficSample>[];
    for (var i = 0; i < 130; i++) {
      history = ConnectionController.compactTrafficHistory(
        history,
        TrafficSample(
          elapsed: Duration(minutes: i * 2),
          uplinkBps: 500 + i,
          downlinkBps: 4000 + i * 10,
        ),
        maxSamples: 60,
      );
    }
    expect(history.length, lessThanOrEqualTo(60));
    expect(history.first.elapsed, Duration.zero);
    expect(history.last.elapsed, const Duration(minutes: 258));
  });

  test('activateAndConnectImportedProfiles connects immediately and hot-switches active tunnel', () async {
    const rawStorage = FlutterSecureStorage();
    const profileStorage = SecureProfileStorage(secureStorage: rawStorage);
    final engine = _TestVpnEngine();

    final container = ProviderContainer(
      overrides: [
        secureProfileStorageProvider.overrideWithValue(profileStorage),
        connectionEngineProvider.overrideWithValue(engine),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(connectionControllerProvider.notifier);

    const oldSubNode = ServerProfile(
      id: 'srv_old',
      displayName: 'Old Server',
      protocol: 'vless',
      source: ProfileSource.subscription,
      serverAddress: '198.51.100.1',
      serverPort: 443,
      extraParams: <String, dynamic>{'uuid': 'old-uuid', 'security': 'tls'},
    );

    const newImportedSubNode = ServerProfile(
      id: 'srv_new',
      displayName: 'New Imported Server',
      protocol: 'vless',
      source: ProfileSource.subscription,
      serverAddress: '203.0.113.10',
      serverPort: 443,
      extraParams: <String, dynamic>{'uuid': 'new-uuid', 'security': 'reality', 'pbk': 'abc'},
    );

    await container.read(profilesListProvider.notifier).addProfiles([oldSubNode]);
    await notifier.activateAndConnectImportedProfiles([oldSubNode]);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(engine.connectedProfiles.map((p) => p.id), ['srv_old']);
    expect(container.read(connectionControllerProvider).isConnected, isTrue);

    // Import new server while already connected -> hot-switch onto newly imported server
    await container
        .read(profilesListProvider.notifier)
        .addProfiles([newImportedSubNode]);
    await notifier.activateAndConnectImportedProfiles([newImportedSubNode]);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(engine.connectedProfiles.map((p) => p.id), ['srv_old', 'srv_new']);
    expect(
      container.read(connectionControllerProvider).activeProfile?.id,
      'srv_new',
    );
  });

  test('AndroidVpnEngineAdapter handles battery optimization MethodChannel queries safely', () async {
    const channel = MethodChannel('app.speedll.connect/vpn');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'isIgnoringBatteryOptimizations') return true;
      if (call.method == 'openBatteryOptimizationSettings') return true;
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final adapter = AndroidVpnEngineAdapter(
      eventChannel: const EventChannel('app.speedll.connect/vpn_events_test_unused'),
    );
    expect(await adapter.isIgnoringBatteryOptimizations(), isTrue);
    expect(await adapter.openBatteryOptimizationSettings(), isTrue);
  });

  testWidgets('SelectServerDialog copies config & opens QrShareDialog cleanly on narrow phone width', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final copiedStrings = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        final args = call.arguments as Map<dynamic, dynamic>?;
        final text = args?['text']?.toString();
        if (text != null) copiedStrings.add(text);
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    final fakeShare = _FakeShareAndQrService();
    const rawStorage = FlutterSecureStorage();
    const profileStorage = SecureProfileStorage(secureStorage: rawStorage);

    const sub = SubscriptionSource(
      id: 'sub_share',
      name: 'اشتراک تست',
      url: 'https://panel.example.com/sub/test-token',
    );
    const srv = ServerProfile(
      id: 'srv_share_1',
      displayName: 'Germany Reality',
      protocol: 'vless',
      source: ProfileSource.subscription,
      serverAddress: '2001:db8::99',
      serverPort: 443,
      extraParams: <String, dynamic>{
        'subscriptionId': 'sub_share',
        'uuid': 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        'security': 'reality',
        'flow': 'xtls-rprx-vision',
        'pbk': 'PubKeyTest',
      },
    );

    final container = ProviderContainer(
      overrides: [
        secureProfileStorageProvider.overrideWithValue(profileStorage),
        shareQrServiceProvider.overrideWithValue(fakeShare),
      ],
    );

    await container.read(subscriptionsListProvider.notifier).addOrUpdateSubscription(sub);
    await container.read(profilesListProvider.notifier).addProfiles([srv]);
    await container.read(connectionControllerProvider.notifier).selectProfile(srv);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: SelectServerDialog(initialSubscriptionId: 'sub_share'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap copy button on the config row (second copy button after subscription card copy button)
    final copyButtons = find.byIcon(Icons.content_copy_rounded);
    expect(copyButtons, findsNWidgets(2));
    await tester.tap(copyButtons.last);
    await tester.pump();
    expect(copiedStrings.last, startsWith('vless://aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa@[2001:db8::99]:443'));

    // Tap QR button on subscription card -> opens QrShareDialog
    final qrButtons = find.byIcon(Icons.qr_code_2_rounded);
    expect(qrButtons, findsNWidgets(2));
    await tester.tap(qrButtons.first);
    await tester.pumpAndSettle();

    expect(find.byType(QrShareDialog), findsOneWidget);
    expect(fakeShare.lastGeneratedQrText, 'https://panel.example.com/sub/test-token');

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await tester.pump();
  });

  testWidgets('StatisticsPanel renders numeric speeds, hours timeline, IP/IPv6 badge, and full protocol model', (tester) async {
    const rawStorage = FlutterSecureStorage();
    const profileStorage = SecureProfileStorage(secureStorage: rawStorage);
    final engine = _TestVpnEngine();

    final container = ProviderContainer(
      overrides: [
        secureProfileStorageProvider.overrideWithValue(profileStorage),
        connectionEngineProvider.overrideWithValue(engine),
      ],
    );

    const profile = ServerProfile(
      id: 'de_ipv6',
      displayName: 'Germany Frankfurt',
      protocol: 'vless',
      source: ProfileSource.manual,
      countryCode: 'DE',
      serverAddress: '2001:db8::42',
      serverPort: 443,
      extraParams: <String, dynamic>{
        'uuid': 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
        'security': 'reality',
        'flow': 'xtls-rprx-vision',
        'transportType': 'tcp',
        'fingerprint': 'chrome',
      },
    );

    final notifier = container.read(connectionControllerProvider.notifier);
    await container.read(profilesListProvider.notifier).addProfiles([profile]);
    await notifier.selectProfile(profile);
    await notifier.toggleConnection();
    await tester.pump();

    // ignore: invalid_use_of_protected_member
    notifier.state = notifier.state.copyWith(
      connectedDuration: const Duration(hours: 2, minutes: 30),
      downlinkBytesPerSec: 1572864, // 1.50 MB/s
      uplinkBytesPerSec: 204800, // 200.0 KB/s -> >=100 KB -> 200 KB/s
      downlinkTotalBytes: 52428800, // 50.0 MB
      uplinkTotalBytes: 5242880, // 5.00 MB
      trafficHistory: const <TrafficSample>[
        TrafficSample(elapsed: Duration.zero, uplinkBps: 1024, downlinkBps: 4096),
        TrafficSample(elapsed: Duration(hours: 1, minutes: 15), uplinkBps: 102400, downlinkBps: 2097152),
        TrafficSample(elapsed: Duration(hours: 2, minutes: 30), uplinkBps: 204800, downlinkBps: 1572864),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: StatisticsPanel(),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('1.50 MB/s'), findsOneWidget);
    expect(find.text('2.00 MB/s'), findsOneWidget);
    expect(find.text('200 KB/s'), findsOneWidget);
    expect(find.textContaining('2.5 ساعت'), findsWidgets);
    expect(find.text('02:30'), findsOneWidget);
    expect(find.text('IPv6'), findsOneWidget);
    expect(find.text('2001:db8::42'), findsOneWidget);
    expect(find.text('VLESS · REALITY · Vision · TCP'), findsOneWidget);
    expect(find.textContaining('uTLS: chrome'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await tester.pump();
  });

  test('syncWithNativeState restores connected phase and elapsed duration when Activity recreates', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('app.speedll.connect/vpn_sync_test');
    const eventChannel = EventChannel('app.speedll.connect/vpn_events_sync_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getNativeTunnelState') {
        return <String, dynamic>{
          'isRunning': true,
          'connectedSeconds': 3182, // 00:53:02
        };
      }
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
      eventChannel,
      MockStreamHandler.inline(onListen: (_, __) {}),
    );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(eventChannel, null);
    });

    final adapter = AndroidVpnEngineAdapter(
      methodChannel: channel,
      eventChannel: eventChannel,
    );
    final nativeState = await adapter.getNativeTunnelState();
    expect(nativeState.isRunning, isTrue);
    expect(nativeState.connectedSeconds, 3182);

    final container = ProviderContainer(
      overrides: [
        connectionEngineProvider.overrideWithValue(adapter),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(connectionControllerProvider.notifier);
    await controller.syncWithNativeState();

    final state = container.read(connectionControllerProvider);
    expect(state.phase, ConnectionPhase.connected);
    expect(state.connectedDuration.inSeconds, greaterThanOrEqualTo(3182));
  });

  test('Quick Settings tile connect event triggers connection and sends serverLabel', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('app.speedll.connect/vpn_quick_tile_test');
    const eventChannel = EventChannel('app.speedll.connect/vpn_events_quick_tile_test');
    String? sentLabel;
    dynamic eventEmitter;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
      eventChannel,
      MockStreamHandler.inline(
        onListen: (arguments, events) {
          eventEmitter = events;
        },
        onCancel: (arguments) {
          eventEmitter = null;
        },
      ),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'requestAddQuickSettingsTile') return 'added';
      if (call.method == 'requestPermissionAndStart') {
        final args = call.arguments as Map<dynamic, dynamic>?;
        sentLabel = args?['serverLabel']?.toString();
        eventEmitter?.success('connected');
        return true;
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(eventChannel, null);
    });

    final adapter = AndroidVpnEngineAdapter(
      methodChannel: channel,
      eventChannel: eventChannel,
    );
    expect(await adapter.requestAddQuickSettingsTile(), 'added');

    final container = ProviderContainer(
      overrides: [
        connectionEngineProvider.overrideWithValue(adapter),
      ],
    );
    addTearDown(container.dispose);

    const profile = ServerProfile(
      id: 'tile_srv_1',
      displayName: 'Germany Quick Node',
      protocol: 'vless',
      source: ProfileSource.manual,
      serverAddress: '203.0.113.55',
      serverPort: 443,
      extraParams: <String, dynamic>{
        'uuid': 'cccccccc-cccc-cccc-cccc-cccccccccccc',
      },
    );
    await container.read(profilesListProvider.notifier).addProfiles([profile]);
    final controller = container.read(connectionControllerProvider.notifier);
    await controller.selectProfile(profile);

    eventEmitter?.success('event:quick_tile_connect');
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(sentLabel, 'Germany Quick Node');
    expect(container.read(connectionControllerProvider).isConnected, isTrue);
  });
}
