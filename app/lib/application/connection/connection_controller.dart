import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speedll_subscription/speedll_subscription.dart';
import '../../data/storage/secure_profile_storage.dart';
import '../../domain/connection/connection_phase.dart';
import '../../domain/diagnostics/diagnostic_error_mapper.dart';
import '../../domain/engine/android_vpn_engine_adapter.dart';
import '../../domain/engine/connection_engine.dart';
import '../../domain/engine/windows_vpn_engine_adapter.dart';
import '../../domain/ping/ping_service.dart';
import '../../domain/routing/region_detector.dart';
import '../../domain/scanner/qr_scanner_service.dart';
import 'connection_state.dart';

final secureProfileStorageProvider = Provider<SecureProfileStorage>((ref) {
  return const SecureProfileStorage();
});

final qrScannerServiceProvider = Provider<QrScannerService>((ref) {
  return const AndroidQrScannerService();
});

final pingServiceProvider = Provider<PingService>((ref) {
  return const PingService();
});

final subscriptionUpdaterProvider = Provider<SubscriptionUpdater>((ref) {
  final updater = SubscriptionUpdater();
  ref.onDispose(updater.stopPeriodicRefresh);
  return updater;
});

final connectionEngineProvider = Provider<ConnectionEngine>((ref) {
  if (!Platform.environment.containsKey('FLUTTER_TEST') &&
      (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    return WindowsVpnEngineAdapter();
  }
  return AndroidVpnEngineAdapter();
});

final subscriptionsListProvider =
    StateNotifierProvider<SubscriptionsNotifier, List<SubscriptionSource>>(
        (ref) {
  final storage = ref.watch(secureProfileStorageProvider);
  return SubscriptionsNotifier(storage: storage);
});

class SubscriptionsNotifier extends StateNotifier<List<SubscriptionSource>> {
  SubscriptionsNotifier({required this.storage}) : super(const []) {
    _loadInitial();
  }

  final SecureProfileStorage storage;

  Future<void> _loadInitial() async {
    final loaded = await storage.loadSubscriptions();
    if (mounted) {
      final merged = <String, SubscriptionSource>{
        for (final source in loaded) source.id: source,
        for (final source in state) source.id: source,
      };
      state = merged.values.toList();
    }
  }

  Future<void> addOrUpdateSubscription(SubscriptionSource source) async {
    final index = state.indexWhere(
      (s) => s.id == source.id || s.url == source.url,
    );
    if (index >= 0) {
      final updated = [...state];
      updated[index] = source;
      state = updated;
    } else {
      state = [...state, source];
    }
    await storage.saveSubscriptions(state);
  }

  Future<void> removeSubscription(String id) async {
    state = state.where((s) => s.id != id).toList();
    await storage.saveSubscriptions(state);
  }

  Future<void> renameSubscription(String id, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    state = [
      for (final s in state)
        if (s.id == id) s.copyWith(name: trimmed) else s,
    ];
    await storage.saveSubscriptions(state);
  }
}

final profilesListProvider =
    StateNotifierProvider<ProfilesNotifier, List<ServerProfile>>((ref) {
  final storage = ref.watch(secureProfileStorageProvider);
  return ProfilesNotifier(storage: storage);
});

class ProfilesNotifier extends StateNotifier<List<ServerProfile>> {
  ProfilesNotifier({required this.storage}) : super(const []) {
    _loadInitial();
  }

  final SecureProfileStorage storage;

  Future<void> _loadInitial() async {
    final allSavedProfiles = await storage.loadProfiles();
    final savedProfiles =
        allSavedProfiles.where(PingService.isConnectableServer).toList();
    if (allSavedProfiles.length != savedProfiles.length) {
      for (final removed in allSavedProfiles.where(
        (profile) => !PingService.isConnectableServer(profile),
      )) {
        await storage.deleteProfileSecret(removed.id);
      }
      await storage.saveProfiles(savedProfiles);
    }
    if (mounted && savedProfiles.isNotEmpty) {
      final byId = <String, ServerProfile>{
        for (final profile in savedProfiles) profile.id: profile,
        for (final profile in state) profile.id: profile,
      };
      state = byId.values.toList();
    }
  }

  Future<void> addProfiles(List<ServerProfile> newProfiles) async {
    final byId = <String, ServerProfile>{
      for (final existing in state)
        if (PingService.isConnectableServer(existing)) existing.id: existing,
    };
    for (final profile in newProfiles) {
      if (PingService.isConnectableServer(profile)) {
        byId[profile.id] = profile;
      }
    }
    state = byId.values.toList();
    await storage.saveProfiles(state);
  }

  /// Replaces all profiles belonging to [subscriptionId] with [newProfiles],
  /// removing entries that no longer exist in the upstream subscription while
  /// preserving manually added profiles and other subscriptions.
  Future<void> replaceSubscriptionProfiles(
    String subscriptionId,
    List<ServerProfile> newProfiles,
  ) async {
    final preserved = state
        .where(
          (p) =>
              p.extraParams['subscriptionId'] != subscriptionId &&
              PingService.isConnectableServer(p),
        )
        .toList();
    final merged = <String, ServerProfile>{
      for (final profile in preserved) profile.id: profile,
      for (final profile in newProfiles)
        if (PingService.isConnectableServer(profile)) profile.id: profile,
    };
    final removed = state.where(
      (p) =>
          p.extraParams['subscriptionId'] == subscriptionId &&
          !merged.containsKey(p.id),
    );
    state = merged.values.toList();
    for (final profile in removed) {
      await storage.deleteProfileSecret(profile.id);
    }
    await storage.saveProfiles(state);
  }

  Future<void> removeProfile(String id) async {
    state = state.where((p) => p.id != id).toList();
    await storage.deleteProfileSecret(id);
    await storage.saveProfiles(state);
  }

  /// Removes all profiles belonging to [subscriptionId] and purges their saved secrets.
  Future<void> removeSubscriptionProfiles(String subscriptionId) async {
    final toRemove = state
        .where((p) => p.extraParams['subscriptionId']?.toString() == subscriptionId)
        .toList();
    state = state
        .where((p) => p.extraParams['subscriptionId']?.toString() != subscriptionId)
        .toList();
    for (final p in toRemove) {
      await storage.deleteProfileSecret(p.id);
    }
    await storage.saveProfiles(state);
  }

  /// Removes all manual / single profiles that do not belong to any valid subscription.
  Future<void> removeManualProfiles(Set<String> validSubscriptionIds) async {
    final toRemove = state.where((p) {
      final subId = p.extraParams['subscriptionId']?.toString();
      return subId == null || !validSubscriptionIds.contains(subId);
    }).toList();
    final idsToRemove = toRemove.map((p) => p.id).toSet();
    state = state.where((p) => !idsToRemove.contains(p.id)).toList();
    for (final p in toRemove) {
      await storage.deleteProfileSecret(p.id);
    }
    await storage.saveProfiles(state);
  }

  Future<void> clearAllProfiles() async {
    final ids = state.map((p) => p.id).toList();
    state = const [];
    for (final id in ids) {
      await storage.deleteProfileSecret(id);
    }
    await storage.saveProfiles(const []);
  }

  Future<void> renameProfile(String id, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    state = [
      for (final p in state)
        if (p.id == id)
          p.copyWith(displayName: trimmed, updatedAt: DateTime.now().toUtc())
        else
          p,
    ];
    await storage.saveProfiles(state);
  }
}

final connectionControllerProvider =
    StateNotifierProvider<ConnectionController, ConnectionUiState>((ref) {
  final engine = ref.watch(connectionEngineProvider);
  final storage = ref.watch(secureProfileStorageProvider);
  final updater = ref.watch(subscriptionUpdaterProvider);
  final pingService = ref.watch(pingServiceProvider);
  final profilesNotifier = ref.read(profilesListProvider.notifier);
  final subscriptionsNotifier = ref.read(subscriptionsListProvider.notifier);

  return ConnectionController(
    engine: engine,
    storage: storage,
    updater: updater,
    pingService: pingService,
    profilesNotifier: profilesNotifier,
    subscriptionsNotifier: subscriptionsNotifier,
    readProfiles: () => ref.read(profilesListProvider),
    readSubscriptions: () => ref.read(subscriptionsListProvider),
  );
});

class ConnectionController extends StateNotifier<ConnectionUiState> {
  ConnectionController({
    required this.engine,
    required this.storage,
    required this.updater,
    required this.pingService,
    required this.profilesNotifier,
    required this.subscriptionsNotifier,
    required List<ServerProfile> Function() readProfiles,
    required List<SubscriptionSource> Function() readSubscriptions,
    Duration periodicRefreshInterval = const Duration(hours: 6),
  })  : _readProfiles = readProfiles,
        _readSubscriptions = readSubscriptions,
        _periodicRefreshInterval = periodicRefreshInterval,
        super(const ConnectionUiState()) {
    _subscription = engine.connectionPhases.listen((phase) {
      final previousPhase = state.phase;
      if (phase == ConnectionPhase.failed) {
        _isHotSwitching = false;
        final currentEngine = engine;
        final report = currentEngine is AndroidVpnEngineAdapter
            ? (currentEngine.lastDiagnosticReport ??
                DiagnosticErrorMapper.fromCodeOrError('ERR-CONN-GENERAL'))
            : currentEngine is WindowsVpnEngineAdapter
                ? (currentEngine.lastDiagnosticReport ??
                    DiagnosticErrorMapper.fromCodeOrError('ERR-CONN-GENERAL'))
                : DiagnosticErrorMapper.fromCodeOrError('ERR-CONN-GENERAL');
        state = state.copyWith(
          phase: phase,
          errorMessage: report.formattedDisplay,
          diagnosticCode: report.code,
        );
      } else if (phase == ConnectionPhase.connected) {
        state = state.copyWith(
          phase: phase,
          errorMessage: null,
          diagnosticCode: null,
        );
      } else {
        state = state.copyWith(phase: phase);
      }

      if (phase == ConnectionPhase.connected) {
        final keepTimer =
            previousPhase == ConnectionPhase.reconnecting || _isHotSwitching;
        _isHotSwitching = false;
        _consecutiveSmartHealthFailures = 0;
        _smartFailoverAttempts = 0;
        if (state.isSmartMode && state.activeProfile != null) {
          _smartLockedProfileId = state.activeProfile!.id;
          state = state.copyWith(smartLockedProfileId: _smartLockedProfileId);
        }
        _startTimer(resetDuration: !keepTimer);
        if (!Platform.environment.containsKey('FLUTTER_TEST')) {
          unawaited(pingActiveProfile());
        }
      } else if (phase == ConnectionPhase.failed) {
        _stopTimer();
        if (state.isSmartMode &&
            state.activeProfile != null &&
            _smartFailoverAttempts < 2 &&
            !Platform.environment.containsKey('FLUTTER_TEST')) {
          _smartFailoverAttempts++;
          unawaited(_triggerSmartFailover(state.activeProfile!.id));
        }
      } else if (phase != ConnectionPhase.reconnecting && !_isHotSwitching) {
        _stopTimer();
        if (phase == ConnectionPhase.disconnected) {
          _smartLockedProfileId = null;
          _consecutiveSmartHealthFailures = 0;
          state = state.copyWith(smartLockedProfileId: null);
        }
      }
    });

    _initPersistedState();
    _startPeriodicBackgroundUpdates(periodicRefreshInterval);
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      _lifecycleListener = AppLifecycleListener(
        onStateChange: (lifecycleState) {
          if (lifecycleState == AppLifecycleState.resumed) {
            if (mounted && state.isConnected) {
              _startTimer(resetDuration: false);
            }
          } else {
            _stopTimer();
          }
        },
      );
    }
  }

  final ConnectionEngine engine;
  final SecureProfileStorage storage;
  final SubscriptionUpdater updater;
  final PingService pingService;
  final ProfilesNotifier profilesNotifier;
  final SubscriptionsNotifier subscriptionsNotifier;
  final List<ServerProfile> Function() _readProfiles;
  final List<SubscriptionSource> Function() _readSubscriptions;

  StreamSubscription<ConnectionPhase>? _subscription;
  Timer? _timer;
  Timer? _smartHealthTimer;
  DateTime? _connectedSince;
  AppLifecycleListener? _lifecycleListener;
  bool _isHotSwitching = false;
  String? _smartLockedProfileId;
  int _consecutiveSmartHealthFailures = 0;
  int _smartFailoverAttempts = 0;
  bool _isCheckingSmartHealth = false;
  final Duration _periodicRefreshInterval;

  Future<void> _initPersistedState() async {
    var routingOptions = await storage.loadRoutingOptions();
    if (!Platform.environment.containsKey('FLUTTER_TEST') &&
        routingOptions.region == RoutingRegion.auto) {
      routingOptions = routingOptions.copyWith(
        region: RegionDetector.detect(),
      );
      await storage.saveRoutingOptions(routingOptions);
    }
    final smartMode = await storage.loadSmartModeEnabled();
    final currentEngine = engine;
    if (currentEngine is AndroidVpnEngineAdapter) {
      currentEngine.updateRoutingOptions(routingOptions);
    } else if (currentEngine is WindowsVpnEngineAdapter) {
      currentEngine.updateRoutingOptions(routingOptions);
    }

    final allSavedProfiles = await storage.loadProfiles();
    final savedProfiles =
        allSavedProfiles.where(PingService.isConnectableServer).toList();
    final savedActiveId = await storage.loadActiveProfileId();

    ServerProfile? resolvedActive;
    if (savedActiveId != null && savedProfiles.isNotEmpty) {
      for (final p in savedProfiles) {
        if (p.id == savedActiveId && PingService.isConnectableServer(p)) {
          resolvedActive = p;
          break;
        }
      }
    }
    if (resolvedActive == null && savedProfiles.isNotEmpty) {
      resolvedActive = savedProfiles.first;
    }

    if (mounted) {
      state = state.copyWith(
        routingOptions: routingOptions,
        isSmartMode: smartMode,
        activeProfile: resolvedActive ?? state.activeProfile,
      );
      if (resolvedActive != null &&
          !Platform.environment.containsKey('FLUTTER_TEST')) {
        unawaited(pingActiveProfile());
      }
    }

    await _maybeRefreshStaleSubscriptions();
  }

  Future<void> _maybeRefreshStaleSubscriptions() async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    final savedSubscriptions = await storage.loadSubscriptions();
    if (savedSubscriptions.isEmpty) return;
    final now = DateTime.now().toUtc();
    final hasStale = savedSubscriptions.any(
      (s) =>
          s.autoUpdate &&
          s.url.trim().isNotEmpty &&
          (s.lastUpdatedAt == null ||
              now.difference(s.lastUpdatedAt!) >= _periodicRefreshInterval),
    );
    if (!hasStale) return;
    await _refreshSubscriptions(savedSubscriptions);
  }

  void _startPeriodicBackgroundUpdates(Duration interval) {
    updater.startPeriodicRefresh(
      interval: interval,
      getSubscriptionUrls: () async {
        final subs = _readSubscriptions();
        return subs
            .where((s) => s.autoUpdate && s.url.trim().isNotEmpty)
            .map((s) => s.url)
            .toList();
      },
      onUpdateResult: (url, result) async {
        if (!mounted) return;
        final subs = _readSubscriptions();
        final source = subs.where((s) => s.url == url).firstOrNull;
        if (result.isSuccess && result.profiles.isNotEmpty) {
          if (source != null) {
            final annotated = _annotateProfiles(result.profiles, source.id);
            await profilesNotifier.replaceSubscriptionProfiles(
              source.id,
              annotated,
            );
            await subscriptionsNotifier.addOrUpdateSubscription(
              source.copyWith(
                lastUpdatedAt: DateTime.now().toUtc(),
                lastStatusMessage:
                    'به‌روزرسانی موفق (${result.profiles.length} سرور)',
                userInfo: result.userInfo,
                subscriberName: result.subscriberName ?? source.subscriberName,
                name: result.subscriberName != null &&
                        (source.name.contains('.') ||
                            source.name.startsWith('sub_') ||
                            RegExp(r'^اشتراک\s*\d+').hasMatch(source.name))
                    ? 'اشتراک ${result.subscriberName}'
                    : source.name,
              ),
            );
          } else {
            await profilesNotifier.addProfiles(result.profiles);
          }
          state = state.copyWith(
            lastSubscriptionStatus:
                'اشتراک در پس‌زمینه به‌روزرسانی شد (${result.profiles.length} سرور).',
          );
        } else if (result.isOfflineError) {
          state = state.copyWith(
            lastSubscriptionStatus: result.errorMessage,
          );
        } else if (source != null && result.userInfo != null) {
          await subscriptionsNotifier.addOrUpdateSubscription(
            source.copyWith(userInfo: result.userInfo),
          );
        }
      },
    );
  }

  /// Measures the real TCP ping of the currently active profile and updates [ConnectionUiState.livePingMs].
  Future<int?> pingActiveProfile() async {
    final active = state.activeProfile;
    if (active == null) return null;
    final ms = await pingService.measurePingMs(active, samples: 3);
    if (!mounted) return ms;

    final updatedMap = <String, int>{
      ...state.profilePings,
      active.id: ms,
    };
    final updatedHistory = ms > 0
        ? <int>[
            ...state.pingHistory.skip(
              state.pingHistory.length >= 16
                  ? state.pingHistory.length - 15
                  : 0,
            ),
            ms,
          ]
        : state.pingHistory;

    state = state.copyWith(
      livePingMs: ms,
      profilePings: updatedMap,
      pingHistory: updatedHistory,
    );
    return ms;
  }

  /// Measures real TCP latency for all saved profiles and updates [ConnectionUiState.profilePings].
  /// If [isSmartMode] is enabled, automatically selects (and hot-switches if connected) the fastest profile.
  Future<Map<String, int>> pingAllProfiles() async {
    if (state.isPingingAll) return state.profilePings;
    final profiles = _readProfiles();
    if (profiles.isEmpty) return const <String, int>{};

    state = state.copyWith(isPingingAll: true);
    try {
      final results = await pingService.measureAllPings(
        profiles,
        onSingleResult: (profileId, ms) {
          if (!mounted) return;
          final nextMap = <String, int>{
            ...state.profilePings,
            profileId: ms,
          };
          state = state.copyWith(
            profilePings: nextMap,
            livePingMs:
                state.activeProfile?.id == profileId ? ms : state.livePingMs,
          );
        },
      );

      if (!mounted) return results;

      // In Smart Mode, only auto-select from pingAllProfiles when NOT already
      // connected and locked onto a working server.
      if (state.isSmartMode &&
          (!state.isConnected || _smartLockedProfileId == null)) {
        final best = pingService.pickBestProfile(profiles, results);
        if (best != null && best.id != state.activeProfile?.id) {
          await selectProfile(best, keepSmartMode: true);
        }
      }
      return results;
    } finally {
      if (mounted) {
        state = state.copyWith(isPingingAll: false);
      }
    }
  }

  /// Enables or disables Smart Auto-Select mode.
  /// When enabled, pings all profiles, picks the lowest-latency server, and locks onto it if connected.
  Future<void> setSmartMode(bool enabled) async {
    if (!enabled) {
      _smartLockedProfileId = null;
      _consecutiveSmartHealthFailures = 0;
    }
    state = state.copyWith(
      isSmartMode: enabled,
      smartLockedProfileId: enabled ? _smartLockedProfileId : null,
    );
    await storage.saveSmartModeEnabled(enabled);

    if (enabled) {
      final profiles = _readProfiles();
      if (profiles.isEmpty) return;

      var pingMap = state.profilePings;
      if (pingMap.isEmpty &&
          !Platform.environment.containsKey('FLUTTER_TEST')) {
        pingMap = await pingService.measureBatchParallel(
          profiles,
          samplesPerProfile: 1,
          onSingleResult: (profileId, ms) {
            if (!mounted) return;
            state = state.copyWith(
              profilePings: <String, int>{
                ...state.profilePings,
                profileId: ms,
              },
            );
          },
        );
      }
      final best = pingService.pickBestProfile(profiles, pingMap);
      if (best != null) {
        if (state.isConnected) {
          _smartLockedProfileId = best.id;
          state = state.copyWith(smartLockedProfileId: _smartLockedProfileId);
        }
        await selectProfile(best, keepSmartMode: true);
      }
    }
  }

  /// Manually triggers a background refresh of all saved subscription links.
  Future<SubscriptionUpdateResult> refreshSubscriptionsNow() async {
    final subs = _readSubscriptions();
    if (subs.isEmpty) {
      return const SubscriptionUpdateResult(
        isSuccess: false,
        errorMessage:
            'هنوز هیچ لینک اشتراک (HTTPS) برای به‌روزرسانی ثبت نشده است.',
      );
    }
    return _refreshSubscriptions(subs);
  }

  /// Deletes a subscription and all associated profiles and keys.
  Future<void> deleteSubscription(String subscriptionId) async {
    final active = state.activeProfile;
    final isActiveSub =
        active?.extraParams['subscriptionId']?.toString() == subscriptionId;

    await subscriptionsNotifier.removeSubscription(subscriptionId);
    await profilesNotifier.removeSubscriptionProfiles(subscriptionId);

    if (isActiveSub) {
      final remaining =
          _readProfiles().where(PingService.isConnectableServer).toList();
      await selectProfile(remaining.isNotEmpty ? remaining.first : null);
    }
  }

  /// Removes all manual / standalone profiles that do not belong to a subscription.
  Future<void> deleteManualProfiles() async {
    final subs = _readSubscriptions();
    final validSubIds = subs.map((s) => s.id).toSet();
    final active = state.activeProfile;
    final activeSubId = active?.extraParams['subscriptionId']?.toString();
    final isActiveManual =
        activeSubId == null || !validSubIds.contains(activeSubId);

    await profilesNotifier.removeManualProfiles(validSubIds);

    if (isActiveManual) {
      final remaining =
          _readProfiles().where(PingService.isConnectableServer).toList();
      await selectProfile(remaining.isNotEmpty ? remaining.first : null);
    }
  }

  List<ServerProfile> _annotateProfiles(
    List<ServerProfile> profiles,
    String subscriptionId,
  ) {
    return profiles
        .map(
          (profile) => profile.copyWith(
            extraParams: <String, dynamic>{
              ...profile.extraParams,
              'subscriptionId': subscriptionId,
            },
          ),
        )
        .toList();
  }

  Future<SubscriptionUpdateResult> _refreshSubscriptions(
    List<SubscriptionSource> subs,
  ) async {
    state = state.copyWith(
      isRefreshingSubscriptions: true,
      errorMessage: null,
    );

    SubscriptionUpdateResult? lastResult;
    var totalUpdated = 0;

    try {
      for (final sub in subs) {
        final res = await updater.fetchAndValidate(sub.url);
        lastResult = res;
        if (res.isSuccess && res.profiles.isNotEmpty) {
          totalUpdated += res.profiles.length;
          final annotated = _annotateProfiles(res.profiles, sub.id);
          await profilesNotifier.replaceSubscriptionProfiles(
            sub.id,
            annotated,
          );
          await subscriptionsNotifier.addOrUpdateSubscription(
            sub.copyWith(
              lastUpdatedAt: DateTime.now().toUtc(),
              lastStatusMessage:
                  'به‌روزرسانی موفق (${res.profiles.length} سرور)',
              userInfo: res.userInfo,
              subscriberName: res.subscriberName ?? sub.subscriberName,
              name: res.subscriberName != null &&
                      (sub.name.contains('.') ||
                          sub.name.startsWith('sub_') ||
                          RegExp(r'^اشتراک\s*\d+').hasMatch(sub.name))
                  ? 'اشتراک ${res.subscriberName}'
                  : sub.name,
            ),
          );
          if (state.activeProfile == null ||
              !PingService.isConnectableServer(state.activeProfile!)) {
            final firstConnectable = res.profiles.firstWhere(
              PingService.isConnectableServer,
              orElse: () => res.profiles.first,
            );
            await selectProfile(
              firstConnectable,
              keepSmartMode: state.isSmartMode,
            );
          }
        } else {
          await subscriptionsNotifier.addOrUpdateSubscription(
            sub.copyWith(
              lastStatusMessage: res.errorMessage,
              userInfo: res.userInfo,
            ),
          );
        }
      }

      if (totalUpdated > 0) {
        final profiles = _readProfiles();
        final active = state.activeProfile;
        if (active != null &&
            profiles.isNotEmpty &&
            !profiles.any((p) => p.id == active.id)) {
          final replacement = profiles.firstWhere(
            PingService.isConnectableServer,
            orElse: () => profiles.first,
          );
          await selectProfile(
            replacement,
            keepSmartMode: state.isSmartMode,
          );
        }

        final msg = 'تعداد $totalUpdated سرور از لینک اشتراک به‌روزرسانی شد.';
        state = state.copyWith(
          isRefreshingSubscriptions: false,
          lastSubscriptionStatus: msg,
        );
        if (!Platform.environment.containsKey('FLUTTER_TEST')) {
          unawaited(pingActiveProfile());
        }
        return SubscriptionUpdateResult(
          isSuccess: true,
          profiles: profiles,
        );
      } else {
        final err = lastResult?.errorMessage ?? 'خطا در به‌روزرسانی اشتراک.';
        state = state.copyWith(
          isRefreshingSubscriptions: false,
          lastSubscriptionStatus: err,
        );
        return lastResult ??
            SubscriptionUpdateResult(
              isSuccess: false,
              errorMessage: err,
            );
      }
    } finally {
      if (mounted && state.isRefreshingSubscriptions) {
        state = state.copyWith(isRefreshingSubscriptions: false);
      }
    }
  }

  /// Selects [profile] as active. If the VPN is currently connected (`isConnected` or `isConnecting`),
  /// automatically hot-switches the active VPN tunnel to the new profile without disconnecting first.
  Future<void> selectProfile(
    ServerProfile? profile, {
    bool manualSelection = false,
    bool keepSmartMode = false,
  }) async {
    final previousId = state.activeProfile?.id;
    final nextSmart = manualSelection ? false : state.isSmartMode;
    if (manualSelection) {
      _smartLockedProfileId = null;
      _consecutiveSmartHealthFailures = 0;
    } else if (nextSmart && state.isConnected && profile != null) {
      _smartLockedProfileId = profile.id;
    }

    final cachedPing = profile != null ? state.profilePings[profile.id] : null;

    state = state.copyWith(
      activeProfile: profile,
      isSmartMode: nextSmart,
      livePingMs: cachedPing,
      smartLockedProfileId: nextSmart ? _smartLockedProfileId : null,
    );

    if (manualSelection) {
      await storage.saveSmartModeEnabled(false);
    }
    await storage.saveActiveProfileId(profile?.id);

    if (profile != null &&
        !Platform.environment.containsKey('FLUTTER_TEST') &&
        cachedPing == null) {
      unawaited(pingActiveProfile());
    }

    // Hot-switch active connection if user changes profile while already connected
    if (profile != null &&
        previousId != null &&
        previousId != profile.id &&
        (state.isConnected || state.isConnecting)) {
      _isHotSwitching = true;
      try {
        state = state.copyWith(errorMessage: null, diagnosticCode: null);
        await engine.connect(profile);
      } catch (e) {
        _isHotSwitching = false;
        final report = DiagnosticErrorMapper.fromCodeOrError(e);
        state = state.copyWith(
          errorMessage: report.formattedDisplay,
          diagnosticCode: report.code,
        );
      }
    }
  }

  Future<void> updateRoutingOptions(SingboxRoutingOptions options) async {
    final currentEngine = engine;
    if (currentEngine is AndroidVpnEngineAdapter) {
      currentEngine.updateRoutingOptions(options);
    } else if (currentEngine is WindowsVpnEngineAdapter) {
      currentEngine.updateRoutingOptions(options);
    }
    state = state.copyWith(routingOptions: options);
    await storage.saveRoutingOptions(options);

    // If currently connected, hot-apply the updated routing rules to the active tunnel
    final active = state.activeProfile;
    if (active != null && state.isConnected) {
      _isHotSwitching = true;
      try {
        await engine.connect(active);
      } catch (e) {
        _isHotSwitching = false;
        final report = DiagnosticErrorMapper.fromCodeOrError(e);
        state = state.copyWith(
          errorMessage: report.formattedDisplay,
          diagnosticCode: report.code,
        );
      }
    }
  }

  Future<RoutingRegion> detectAndApplyRegion() async {
    final region = RegionDetector.detect();
    final isGlobal = region == RoutingRegion.global;
    await updateRoutingOptions(
      state.routingOptions.copyWith(
        region: region,
        bypassIranDomains: !isGlobal,
        bypassLan: !isGlobal,
      ),
    );
    return region;
  }

  /// Opens the native platform VPN system settings (e.g. Always-on VPN / Kill Switch on Android).
  Future<bool> openSystemVpnSettings() async {
    final currentEngine = engine;
    if (currentEngine is AndroidVpnEngineAdapter) {
      return currentEngine.openVpnSettings();
    }
    return false;
  }

  void _startTimer({bool resetDuration = true}) {
    _timer?.cancel();
    if (resetDuration || _connectedSince == null) {
      _connectedSince = DateTime.now();
      state = state.copyWith(connectedDuration: Duration.zero);
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final since = _connectedSince;
      if (since == null) return;
      state = state.copyWith(
        connectedDuration: DateTime.now().difference(since),
      );
    });
    _startSmartHealthMonitor();
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
    _smartHealthTimer?.cancel();
    _smartHealthTimer = null;
  }

  void _startSmartHealthMonitor() {
    _smartHealthTimer?.cancel();
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    _smartHealthTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(checkSmartConnectionHealth());
    });
  }

  /// Checks active server health in Smart Mode; if the locked server fails or
  /// experiences extreme latency (>1800ms) for 2 consecutive checks, automatically
  /// fails over to the next best working server and locks onto it.
  Future<void> checkSmartConnectionHealth() async {
    if (!mounted ||
        _isCheckingSmartHealth ||
        !state.isConnected ||
        !state.isSmartMode ||
        _isHotSwitching ||
        state.isPingingAll) {
      return;
    }
    final active = state.activeProfile;
    if (active == null) return;

    _isCheckingSmartHealth = true;
    try {
      final ms = await pingActiveProfile();
      if (!mounted || !state.isConnected || !state.isSmartMode) return;

      final isUnhealthy = ms == null || ms <= 0 || ms > 1800;
      if (isUnhealthy) {
        _consecutiveSmartHealthFailures++;
        if (_consecutiveSmartHealthFailures >= 2) {
          _consecutiveSmartHealthFailures = 0;
          await _triggerSmartFailover(active.id);
        }
      } else {
        _consecutiveSmartHealthFailures = 0;
      }
    } finally {
      _isCheckingSmartHealth = false;
    }
  }

  Future<void> _triggerSmartFailover(String unhealthyProfileId) async {
    if (!mounted || !state.isSmartMode) return;
    final profiles = _readProfiles();
    if (profiles.length <= 1) return;

    final results = await pingService.measureBatchParallel(
      profiles,
      samplesPerProfile: 1,
      onSingleResult: (profileId, ms) {
        if (!mounted) return;
        state = state.copyWith(
          profilePings: <String, int>{
            ...state.profilePings,
            profileId: ms,
          },
        );
      },
    );
    if (!mounted || !state.isSmartMode) return;

    final best = pingService.pickBestProfile(
      profiles,
      results,
      excludeIds: <String>{unhealthyProfileId},
    );
    if (best != null &&
        best.id != unhealthyProfileId &&
        (results[best.id] ?? -1) > 0) {
      _smartLockedProfileId = best.id;
      state = state.copyWith(
        smartLockedProfileId: _smartLockedProfileId,
        lastSubscriptionStatus:
            'اتصال هوشمند به سرور پایدارتر (${best.displayName}) جابه‌جا شد.',
      );
      await selectProfile(best, keepSmartMode: true);
    }
  }

  Future<void> toggleConnection() async {
    if (state.isDisconnecting) return;
    if (state.isConnected || state.isConnecting) {
      _smartLockedProfileId = null;
      _consecutiveSmartHealthFailures = 0;
      state = state.copyWith(smartLockedProfileId: null);
      await engine.disconnect();
    } else {
      var profile = state.activeProfile;
      final profiles = _readProfiles();

      if (state.isSmartMode && profiles.isNotEmpty) {
        state = state.copyWith(
          phase: ConnectionPhase.preparing,
          isPingingAll: true,
          errorMessage: null,
          diagnosticCode: null,
        );
        Map<String, int> pingMap = state.profilePings;
        try {
          if (!Platform.environment.containsKey('FLUTTER_TEST') ||
              pingMap.isEmpty) {
            pingMap = await pingService.measureBatchParallel(
              profiles,
              samplesPerProfile: 1,
              onSingleResult: (profileId, ms) {
                if (!mounted) return;
                state = state.copyWith(
                  profilePings: <String, int>{
                    ...state.profilePings,
                    profileId: ms,
                  },
                );
              },
            );
          }
        } finally {
          if (mounted) {
            state = state.copyWith(isPingingAll: false);
          }
        }
        final best = pingService.pickBestProfile(profiles, pingMap);
        if (best != null) {
          profile = best;
          _smartLockedProfileId = best.id;
          state = state.copyWith(
            activeProfile: best,
            smartLockedProfileId: best.id,
            livePingMs: pingMap[best.id],
          );
          await storage.saveActiveProfileId(best.id);
        }
      } else if (profile != null &&
          !PingService.isConnectableServer(profile) &&
          profiles.isNotEmpty) {
        final best = pingService.pickBestProfile(profiles, state.profilePings);
        if (best != null) {
          profile = best;
          state = state.copyWith(activeProfile: best);
          await storage.saveActiveProfileId(best.id);
        }
      }

      if (profile == null) {
        state = state.copyWith(
          phase: ConnectionPhase.disconnected,
          errorMessage: 'لطفاً ابتدا یک سرور را انتخاب یا اضافه کنید.',
          diagnosticCode: null,
        );
        return;
      }
      try {
        state = state.copyWith(errorMessage: null, diagnosticCode: null);
        await engine.connect(profile);
      } catch (e) {
        final report = DiagnosticErrorMapper.fromCodeOrError(e);
        state = state.copyWith(
          errorMessage: report.formattedDisplay,
          diagnosticCode: report.code,
        );
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _smartHealthTimer?.cancel();
    _lifecycleListener?.dispose();
    _subscription?.cancel();
    updater.stopPeriodicRefresh();
    super.dispose();
  }
}
