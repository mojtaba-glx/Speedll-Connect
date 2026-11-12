import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:speedll_subscription/speedll_subscription.dart';
import '../connection/connection_phase.dart';
import '../diagnostics/diagnostic_error_mapper.dart';
import 'connection_engine.dart';

const bool _nativeLibboxDefault = bool.fromEnvironment(
  'SPEEDLL_NATIVE_LIBBOX',
  defaultValue: true,
);

class AndroidVpnEngineAdapter implements ConnectionEngine {
  AndroidVpnEngineAdapter({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
    SingboxConverter? converter,
    SingboxRoutingOptions routingOptions = const SingboxRoutingOptions(),
    bool? useNativeLibbox,
  })  : _methodChannel = methodChannel ??
            const MethodChannel('app.speedll.connect/vpn'),
        _eventChannel = eventChannel ??
            const EventChannel('app.speedll.connect/vpn_events'),
        _converter = converter ?? const SingboxConverter(),
        _routingOptions = routingOptions,
        _useNativeLibbox = useNativeLibbox ?? _nativeLibboxDefault {
    _initEventListener();
  }

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;
  final SingboxConverter _converter;
  final bool _useNativeLibbox;
  SingboxRoutingOptions _routingOptions;

  SingboxRoutingOptions get routingOptions => _routingOptions;

  void updateRoutingOptions(SingboxRoutingOptions options) {
    _routingOptions = options;
  }

  final StreamController<ConnectionPhase> _phaseController =
      StreamController<ConnectionPhase>.broadcast();

  ConnectionPhase _currentPhase = ConnectionPhase.disconnected;
  ConnectionPhase get currentPhase => _currentPhase;

  DiagnosticReport? _lastDiagnosticReport;
  DiagnosticReport? get lastDiagnosticReport => _lastDiagnosticReport;

  void _initEventListener() {
    _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is String) {
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
      if (_useNativeLibbox) {
        _converter.buildAndroidLibboxConfig(
          profile,
          routingOptions: _routingOptions,
        );
      } else {
        _converter.buildFullConfig(
          profile,
          routingOptions: _routingOptions,
        );
      }
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

    final config = _useNativeLibbox
        ? _converter.buildAndroidLibboxConfig(
            profile,
            routingOptions: _routingOptions,
          )
        : _converter.buildFullConfig(
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
          'nativeLibbox': _useNativeLibbox,
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
}
