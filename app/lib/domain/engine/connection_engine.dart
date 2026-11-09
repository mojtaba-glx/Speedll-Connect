import '../connection/connection_phase.dart';
import '../profiles/server_profile.dart';

/// A platform-neutral contract. Implementations must live behind native/core adapters.
/// This interface is intentionally not wired to a real VPN engine yet.
abstract interface class ConnectionEngine {
  String get engineId;

  Future<EngineCapabilityReport> inspectProfile(ServerProfile profile);

  Future<void> connect(ServerProfile profile);

  Future<void> disconnect();

  Stream<ConnectionPhase> get connectionPhases;
}

class EngineCapabilityReport {
  const EngineCapabilityReport({
    required this.supported,
    required this.reasons,
    this.engineId,
  });

  final bool supported;
  final List<String> reasons;
  final String? engineId;
}
