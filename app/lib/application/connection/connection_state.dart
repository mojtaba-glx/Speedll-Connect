import '../../domain/connection/connection_phase.dart';
import '../../domain/profiles/server_profile.dart';

class ConnectionUiState {
  const ConnectionUiState({
    this.phase = ConnectionPhase.disconnected,
    this.activeProfile,
    this.connectedDuration = Duration.zero,
    this.errorMessage,
  });

  final ConnectionPhase phase;
  final ServerProfile? activeProfile;
  final Duration connectedDuration;
  final String? errorMessage;

  bool get isConnected => phase == ConnectionPhase.connected;
  bool get isConnecting =>
      phase == ConnectionPhase.connecting || phase == ConnectionPhase.preparing;
  bool get isDisconnected =>
      phase == ConnectionPhase.disconnected || phase == ConnectionPhase.failed;

  ConnectionUiState copyWith({
    ConnectionPhase? phase,
    ServerProfile? activeProfile,
    Duration? connectedDuration,
    String? errorMessage,
  }) {
    return ConnectionUiState(
      phase: phase ?? this.phase,
      activeProfile: activeProfile ?? this.activeProfile,
      connectedDuration: connectedDuration ?? this.connectedDuration,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
