import 'package:speedll_subscription/speedll_subscription.dart'
    show SingboxRoutingOptions;
import '../../domain/connection/connection_phase.dart';
import '../../domain/profiles/server_profile.dart';

class ConnectionUiState {
  const ConnectionUiState({
    this.phase = ConnectionPhase.disconnected,
    this.activeProfile,
    this.connectedDuration = Duration.zero,
    this.errorMessage,
    this.diagnosticCode,
    this.routingOptions = const SingboxRoutingOptions(),
    this.isRefreshingSubscriptions = false,
    this.lastSubscriptionStatus,
    this.isSmartMode = false,
    this.livePingMs,
    this.profilePings = const <String, int>{},
    this.isPingingAll = false,
    this.pingHistory = const <int>[],
    this.smartLockedProfileId,
  });

  final ConnectionPhase phase;
  final ServerProfile? activeProfile;
  final Duration connectedDuration;
  final String? errorMessage;
  final String? diagnosticCode;
  final SingboxRoutingOptions routingOptions;
  final bool isRefreshingSubscriptions;
  final String? lastSubscriptionStatus;
  final bool isSmartMode;
  final int? livePingMs;
  final Map<String, int> profilePings;
  final bool isPingingAll;
  final List<int> pingHistory;
  final String? smartLockedProfileId;

  bool get isSmartLocked =>
      isSmartMode &&
      smartLockedProfileId != null &&
      smartLockedProfileId == activeProfile?.id &&
      isConnected;

  bool get isConnected => phase == ConnectionPhase.connected;
  bool get isConnecting =>
      phase == ConnectionPhase.connecting ||
      phase == ConnectionPhase.preparing ||
      phase == ConnectionPhase.reconnecting;
  bool get isDisconnecting => phase == ConnectionPhase.disconnecting;
  bool get isDisconnected =>
      phase == ConnectionPhase.disconnected || phase == ConnectionPhase.failed;

  int? pingForProfile(String? profileId) {
    if (profileId == null) return livePingMs;
    return profilePings[profileId] ??
        (activeProfile?.id == profileId ? livePingMs : null);
  }

  static const Object _unset = Object();

  ConnectionUiState copyWith({
    ConnectionPhase? phase,
    Object? activeProfile = _unset,
    Duration? connectedDuration,
    Object? errorMessage = _unset,
    Object? diagnosticCode = _unset,
    SingboxRoutingOptions? routingOptions,
    bool? isRefreshingSubscriptions,
    Object? lastSubscriptionStatus = _unset,
    bool? isSmartMode,
    Object? livePingMs = _unset,
    Map<String, int>? profilePings,
    bool? isPingingAll,
    List<int>? pingHistory,
    Object? smartLockedProfileId = _unset,
  }) {
    return ConnectionUiState(
      phase: phase ?? this.phase,
      activeProfile: identical(activeProfile, _unset)
          ? this.activeProfile
          : activeProfile as ServerProfile?,
      connectedDuration: connectedDuration ?? this.connectedDuration,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
      diagnosticCode: identical(diagnosticCode, _unset)
          ? this.diagnosticCode
          : diagnosticCode as String?,
      routingOptions: routingOptions ?? this.routingOptions,
      isRefreshingSubscriptions:
          isRefreshingSubscriptions ?? this.isRefreshingSubscriptions,
      lastSubscriptionStatus: identical(lastSubscriptionStatus, _unset)
          ? this.lastSubscriptionStatus
          : lastSubscriptionStatus as String?,
      isSmartMode: isSmartMode ?? this.isSmartMode,
      livePingMs: identical(livePingMs, _unset)
          ? this.livePingMs
          : livePingMs as int?,
      profilePings: profilePings ?? this.profilePings,
      isPingingAll: isPingingAll ?? this.isPingingAll,
      pingHistory: pingHistory ?? this.pingHistory,
      smartLockedProfileId: identical(smartLockedProfileId, _unset)
          ? this.smartLockedProfileId
          : smartLockedProfileId as String?,
    );
  }
}
