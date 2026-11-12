import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:speedll_subscription/speedll_subscription.dart';
import '../connection/connection_phase.dart';
import '../diagnostics/diagnostic_error_mapper.dart';
import '../ping/ping_service.dart';
import 'connection_engine.dart';

/// Live throughput and session total byte counts reported by Android [MainActivity].
class TrafficStatsSnapshot {
  const TrafficStatsSnapshot({
    required this.uplinkBps,
    required this.downlinkBps,
    required this.uplinkTotalBytes,
    required this.downlinkTotalBytes,
  });

  final int uplinkBps;
  final int downlinkBps;
  final int uplinkTotalBytes;
  final int downlinkTotalBytes;

  static TrafficStatsSnapshot? tryParse(String raw) {
    if (!raw.startsWith('stats:')) return null;
    final parts = raw.split(':');
    if (parts.length != 5) return null;
    final up = int.tryParse(parts[1]);
    final down = int.tryParse(parts[2]);
    final upTotal = int.tryParse(parts[3]);
    final downTotal = int.tryParse(parts[4]);
    if (up == null || down == null || upTotal == null || downTotal == null) {
      return null;
    }
    return TrafficStatsSnapshot(
      uplinkBps: up < 0 ? 0 : up,
      downlinkBps: down < 0 ? 0 : down,
      uplinkTotalBytes: upTotal < 0 ? 0 : upTotal,
      downlinkTotalBytes: downTotal < 0 ? 0 : downTotal,
    );
  }
}

class AndroidVpnEngineAdapter implements ConnectionEngine {
  AndroidVpnEngineAdapter({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
    SingboxConverter? converter,
    SingboxRoutingOptions routingOptions = const SingboxRoutingOptions(),
  })  : _methodChannel = methodChannel ??
            const MethodChannel('app.speedll.connect/vpn'),
        _eventChannel = eventChannel ??
            const EventChannel('app.speedll.connect/vpn_events'),
        _converter = converter ?? const SingboxConverter(),
        _routingOptions = routingOptions {
    _initEventListener();
  }

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;
  final SingboxConverter _converter;
  SingboxRoutingOptions _routingOptions;

  SingboxRoutingOptions get routingOptions => _routingOptions;

  void updateRoutingOptions(SingboxRoutingOptions options) {
    _routingOptions = options;
  }

  final StreamController<ConnectionPhase> _phaseController =
      StreamController<ConnectionPhase>.broadcast();
  final StreamController<TrafficStatsSnapshot> _trafficController =
      StreamController<TrafficStatsSnapshot>.broadcast();
  final StreamController<void> _quickTileConnectController =
      StreamController<void>.broadcast();

  ConnectionPhase _currentPhase = ConnectionPhase.disconnected;
  ConnectionPhase get currentPhase => _currentPhase;

  Stream<TrafficStatsSnapshot> get trafficStats => _trafficController.stream;
  Stream<void> get quickTileConnectRequests =>
      _quickTileConnectController.stream;

  DiagnosticReport? _lastDiagnosticReport;
  DiagnosticReport? get lastDiagnosticReport => _lastDiagnosticReport;

  void _initEventListener() {
    _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is String) {
          final rawEvent = event.trim();
          final stats = TrafficStatsSnapshot.tryParse(rawEvent);
          if (stats != null) {
            _trafficController.add(stats);
            return;
          }
          final trimmed = rawEvent.toLowerCase();
          if (trimmed == 'event:dns_cleared') {
            PingService.clearDnsCache();
            return;
          }
          if (trimmed == 'event:quick_tile_connect') {
            _quickTileConnectController.add(null);
            return;
          }
          final phase = _mapPhaseString(event);
          if (phase == ConnectionPhase.failed) {
            _lastDiagnosticReport = DiagnosticErrorMapper.fromCodeOrError(event);
          } else if (phase == ConnectionPhase.connected ||
              phase == ConnectionPhase.preparing) {
            _lastDiagnosticReport = null;
          }
          _currentPhase = phase;
          _phaseController.add(phase);
        }
      },
      onError: (dynamic error) {
        _lastDiagnosticReport =
            DiagnosticErrorMapper.fromCodeOrError(error ?? 'ERR-CONN-GENERAL');
        _currentPhase = ConnectionPhase.failed;
        _phaseController.add(ConnectionPhase.failed);
      },
    );
  }

  ConnectionPhase _mapPhaseString(String phaseStr) {
    final normalized = phaseStr.trim().toLowerCase();
    if (normalized.startsWith('failed')) {
      return ConnectionPhase.failed;
    }
    return switch (normalized) {
      'preparing' => ConnectionPhase.preparing,
      'connecting' => ConnectionPhase.connecting,
      'connected' => ConnectionPhase.connected,
      'reconnecting' => ConnectionPhase.reconnecting,
      'disconnecting' => ConnectionPhase.disconnecting,
      _ => ConnectionPhase.disconnected,
    };
  }

  @override
  String get engineId => 'sing-box-android';

  @override
  Stream<ConnectionPhase> get connectionPhases => _phaseController.stream;

  @override
  Future<EngineCapabilityReport> inspectProfile(ServerProfile profile) async {
    const validator = ProfileValidator();
    final validation = validator.validate(profile);

    if (!validation.isValid) {
      return EngineCapabilityReport(
        supported: false,
        reasons: validation.errors,
        engineId: engineId,
      );
    }

    try {
      _converter.buildAndroidLibboxConfig(
        profile,
        routingOptions: _routingOptions,
      );
      return EngineCapabilityReport(
        supported: true,
        reasons: const ['پروتکل و تنظیمات توسط هسته sing-box پشتیبانی می‌شود.'],
        engineId: engineId,
      );
    } catch (e) {
      return EngineCapabilityReport(
        supported: false,
        reasons: ['خطا در تبدیل کانفیگ: $e'],
        engineId: engineId,
      );
    }
  }

  @override
  Future<void> connect(ServerProfile profile) async {
    final capability = await inspectProfile(profile);
    if (!capability.supported) {
      _currentPhase = ConnectionPhase.failed;
      _phaseController.add(ConnectionPhase.failed);
      throw Exception(
        'پروفایل پشتیبانی نمی‌شود: ${capability.reasons.join(", ")}',
      );
    }

    final config = _converter.buildAndroidLibboxConfig(
      profile,
      routingOptions: _routingOptions,
    );

    final configJson = jsonEncode(config);

    try {
      _currentPhase = ConnectionPhase.preparing;
      _phaseController.add(ConnectionPhase.preparing);

      final success = await _methodChannel.invokeMethod<bool>(
        'requestPermissionAndStart',
        <String, dynamic>{
          'config': configJson,
          'killSwitch': _routingOptions.killSwitch,
          'serverLabel': profile.displayName,
        },
      );

      if (success != true) {
        _lastDiagnosticReport =
            DiagnosticErrorMapper.fromCodeOrError('ERR-VPN-PERMISSION');
        _currentPhase = ConnectionPhase.failed;
        _phaseController.add(ConnectionPhase.failed);
      }
    } catch (e) {
      _lastDiagnosticReport = DiagnosticErrorMapper.fromCodeOrError(e);
      _currentPhase = ConnectionPhase.failed;
      _phaseController.add(ConnectionPhase.failed);
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    try {
      _currentPhase = ConnectionPhase.disconnecting;
      _phaseController.add(ConnectionPhase.disconnecting);
      await _methodChannel.invokeMethod<bool>('stop');
    } catch (e) {
      _currentPhase = ConnectionPhase.failed;
      _phaseController.add(ConnectionPhase.failed);
    }
  }

  /// Launches the native Android system VPN settings screen (Always-on VPN).
  Future<bool> openVpnSettings() async {
    try {
      final res = await _methodChannel.invokeMethod<bool>('openVpnSettings');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Queries whether the native [LibboxVpnService] tunnel is currently running.
  Future<bool> isRunning() async {
    try {
      final res = await _methodChannel.invokeMethod<bool>('isRunning');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Returns native running status alongside current tunnel uptime in seconds.
  Future<({bool isRunning, int connectedSeconds})> getNativeTunnelState() async {
    try {
      final dynamic raw = await _methodChannel.invokeMethod<dynamic>(
        'getNativeTunnelState',
      );
      if (raw is Map<dynamic, dynamic>) {
        final running = raw['isRunning'] == true;
        final rawSecs = raw['connectedSeconds'];
        final seconds = rawSecs is int
            ? rawSecs
            : int.tryParse(rawSecs?.toString() ?? '') ?? 0;
        return (
          isRunning: running,
          connectedSeconds: seconds < 0 ? 0 : seconds,
        );
      }
    } catch (_) {
      // Fall back to legacy isRunning query on unstubbed/test handlers.
    }
    final running = await isRunning();
    return (isRunning: running, connectedSeconds: 0);
  }

  /// Requests `libbox` to flush stale sockets and DNS caches on the running VPN service.
  Future<bool> resetNetwork() async {
    try {
      PingService.clearDnsCache();
      final res = await _methodChannel.invokeMethod<bool>('resetNetwork');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Checks whether Android battery optimization is disabled ("Unrestricted") for this app.
  Future<bool> isIgnoringBatteryOptimizations() async {
    try {
      final res = await _methodChannel.invokeMethod<bool>(
        'isIgnoringBatteryOptimizations',
      );
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Launches Android's system Battery Optimization settings screen.
  Future<bool> openBatteryOptimizationSettings() async {
    try {
      final res = await _methodChannel.invokeMethod<bool>(
        'openBatteryOptimizationSettings',
      );
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Requests Android 13+ system dialog to pin the Quick Settings Tile to the
  /// notification shade. Returns `'added'`, `'already_added'`, `'denied'`, or `'unsupported'`.
  Future<String> requestAddQuickSettingsTile() async {
    try {
      final res = await _methodChannel.invokeMethod<String>(
        'requestAddQuickSettingsTile',
      );
      return res ?? 'unsupported';
    } catch (_) {
      return 'unsupported';
    }
  }
}
