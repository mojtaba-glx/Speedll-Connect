import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speedll_connect_app/main.dart';
import 'package:speedll_connect_app/application/connection/connection_controller.dart';
import 'package:speedll_connect_app/domain/engine/connection_engine.dart';
import 'package:speedll_connect_app/domain/connection/connection_phase.dart';
import 'package:speedll_subscription/speedll_subscription.dart';

class MockConnectionEngine implements ConnectionEngine {
  @override
  String get engineId => 'mock-engine';

  @override
  Stream<ConnectionPhase> get connectionPhases => const Stream.empty();

  @override
  Future<void> connect(ServerProfile profile) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<EngineCapabilityReport> inspectProfile(ServerProfile profile) async {
    return const EngineCapabilityReport(supported: true, reasons: []);
  }
}

void main() {
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
    expect(find.text('افزودن اشتراک یا کانفیگ'), findsOneWidget);
  });
}
