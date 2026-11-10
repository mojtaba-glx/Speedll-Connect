import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:speedll_subscription/speedll_subscription.dart';
import '../connection/connection_phase.dart';
import 'connection_engine.dart';

class AndroidVpnEngineAdapter implements ConnectionEngine {
  AndroidVpnEngineAdapter({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
    SingboxConverter? converter,
  })  : _methodChannel = methodChannel ??
            const MethodChannel('ir.speedll.speedll_connect/vpn'),
        _eventChannel = eventChannel ??
            const EventChannel('ir.speedll.speedll_connect/vpn_events'),
        _converter = converter ?? const SingboxConverter() {
    _initEventListener();
  }

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;
  final SingboxConverter _converter;

  final StreamController<ConnectionPhase> _phaseController =
      StreamController<ConnectionPhase>.broadcast();

  ConnectionPhase _currentPhase = ConnectionPhase.disconnected;
  ConnectionPhase get currentPhase => _currentPhase;

  void _initEventListener() {
    _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is String) {
          final phase = _mapPhaseString(event);
          _currentPhase = phase;
          _phaseController.add(phase);
        }
      },
      onError: (dynamic error) {
        _currentPhase = ConnectionPhase.failed;
        _phaseController.add(ConnectionPhase.failed);
      },
    );
  }

  ConnectionPhase _mapPhaseString(String phaseStr) {
    return switch (phaseStr.toLowerCase()) {
      'preparing' => ConnectionPhase.preparing,
      'connecting' => ConnectionPhase.connecting,
      'connected' => ConnectionPhase.connected,
      'disconnecting' => ConnectionPhase.disconnecting,
      'failed' => ConnectionPhase.failed,
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
      _converter.buildOutbound(profile);
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

    final outbound = _converter.buildOutbound(profile);

    // Complete sing-box configuration with TUN inbound and direct DNS
    final fullConfig = <String, dynamic>{
      'log': {
        'level': 'info',
        'timestamp': true,
      },
      'dns': {
        'servers': [
          {
            'tag': 'dns-remote',
            'address': 'https://1.1.1.1/dns-query',
            'detour': 'proxy',
          },
          {
            'tag': 'dns-direct',
            'address': 'local',
            'detour': 'direct',
          }
        ]
      },
      'inbounds': [
        {
          'type': 'tun',
          'tag': 'tun-in',
          'interface_name': 'tun0',
          'inet4_address': '172.19.0.1/30',
          'auto_route': false,
          'strict_route': false,
          'stack': 'system',
          'sniff': true,
        }
      ],
      'outbounds': [
        outbound,
        {
          'type': 'direct',
          'tag': 'direct',
        },
        {
          'type': 'dns',
          'tag': 'dns-out',
        }
      ],
      'route': {
        'rules': [
          {
            'protocol': 'dns',
            'outbound': 'dns-out',
          }
        ],
        'auto_detect_interface': true,
      }
    };

    final configJson = jsonEncode(fullConfig);

    try {
      _currentPhase = ConnectionPhase.preparing;
      _phaseController.add(ConnectionPhase.preparing);

      final success = await _methodChannel.invokeMethod<bool>(
        'requestPermissionAndStart',
        <String, dynamic>{'config': configJson},
      );

      if (success != true) {
        _currentPhase = ConnectionPhase.failed;
        _phaseController.add(ConnectionPhase.failed);
      }
    } catch (e) {
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
}
