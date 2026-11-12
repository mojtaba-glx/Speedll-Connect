import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:speedll_subscription/speedll_subscription.dart';
import '../connection/connection_phase.dart';
import '../diagnostics/diagnostic_error_mapper.dart';
import 'connection_engine.dart';

/// Native Windows & Desktop VPN Engine Adapter powered by `sing-box` (`sing-box.exe` on Windows).
///
/// Supports two operational modes on Windows (similar to v2rayN):
/// 1. **System Proxy + Mixed Inbound (`127.0.0.1:2080`)**: Works without Administrator privileges,
///    automatically configuring Windows WinINET/System Proxy on connect and restoring it on disconnect.
/// 2. **TUN Adapter Mode (`wintun.dll`)**: When [useTunAdapter] is enabled (requires Administrator),
///    creates a virtual TUN interface to tunnel all system-wide TCP/UDP traffic.
class WindowsVpnEngineAdapter implements ConnectionEngine {
  WindowsVpnEngineAdapter({
    SingboxConverter? converter,
    SingboxRoutingOptions routingOptions = const SingboxRoutingOptions(),
    this.useTunAdapter = false,
    String? customBinaryPath,
  })  : _converter = converter ?? const SingboxConverter(),
        _routingOptions = routingOptions,
        _customBinaryPath = customBinaryPath;

  final SingboxConverter _converter;
  SingboxRoutingOptions _routingOptions;
  bool useTunAdapter;
  final String? _customBinaryPath;

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

  Process? _singboxProcess;
  File? _activeConfigFile;
  bool _stoppingIntentionally = false;
  int _connectionGeneration = 0;
  bool _proxyActive = false;
  Map<String, String?>? _proxySnapshot;

  static const String _internetSettingsKey =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';

  @override
  String get engineId =>
      Platform.isWindows ? 'sing-box-windows' : 'sing-box-desktop';

  @override
  Stream<ConnectionPhase> get connectionPhases => _phaseController.stream;

  void _emitPhase(ConnectionPhase phase) {
    _currentPhase = phase;
    if (!_phaseController.isClosed) {
      _phaseController.add(phase);
    }
  }

  /// Resolves the path to `sing-box.exe` (on Windows) or `sing-box` (on Linux/macOS).
  String? resolveSingboxBinaryPath() {
    if (_customBinaryPath != null && File(_customBinaryPath).existsSync()) {
      return _customBinaryPath;
    }

    final binaryName = Platform.isWindows ? 'sing-box.exe' : 'sing-box';
    final execDir = File(Platform.resolvedExecutable).parent.path;
    final sep = Platform.pathSeparator;

    final candidates = <String>[
      '$execDir$sep$binaryName',
      '$execDir${sep}bin$sep$binaryName',
      '$execDir${sep}data${sep}flutter_assets${sep}bin$sep$binaryName',
      '${Directory.current.path}$sep$binaryName',
      '${Directory.current.path}${sep}bin$sep$binaryName',
      if (Platform.environment['LOCALAPPDATA'] != null)
        '${Platform.environment['LOCALAPPDATA']}${sep}SpeedllConnect${sep}bin$sep$binaryName',
    ];

    for (final path in candidates) {
      if (File(path).existsSync()) {
        return path;
      }
    }
    return null;
  }

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
        reasons: const [
          'پروتکل و تنظیمات توسط هسته sing-box دسکتاپ پشتیبانی می‌شود.',
        ],
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

  Map<String, dynamic> buildDesktopConfig(
    ServerProfile profile, {
    int listenPort = 2080,
  }) {
    final baseConfig = _converter.buildFullConfig(
      profile,
      routingOptions: _routingOptions,
    );

    final inbounds = <Map<String, dynamic>>[
      <String, dynamic>{
        'type': 'mixed',
        'tag': 'mixed-in',
        'listen': '127.0.0.1',
        'listen_port': listenPort,
        'sniff': _routingOptions.enableTrafficSniffing,
        'sniff_override_destination': false,
      },
      if (useTunAdapter)
        <String, dynamic>{
          'type': 'tun',
          'tag': 'tun-in',
          'interface_name': 'SpeedllTun',
          'inet4_address': '172.19.0.1/30',
          'inet6_address': 'fdfe:dcba:9876::1/126',
          'mtu': 1400,
          'auto_route': true,
          'strict_route': true,
          'stack': 'system',
          'sniff': _routingOptions.enableTrafficSniffing,
        },
    ];

    return <String, dynamic>{
      ...baseConfig,
      'inbounds': inbounds,
    };
  }

  @override
  Future<void> connect(ServerProfile profile) async {
    final capability = await inspectProfile(profile);
    if (!capability.supported) {
      _lastDiagnosticReport =
          DiagnosticErrorMapper.fromCodeOrError('ERR-CORE-CONFIG');
      _emitPhase(ConnectionPhase.failed);
      throw Exception(
        'پروفایل پشتیبانی نمی‌شود: ${capability.reasons.join(", ")}',
      );
    }

    _emitPhase(ConnectionPhase.preparing);

    // Stop any previous running instance before starting or hot-swapping
    await _stopRunningProcess(disableProxy: false);

    final binaryPath = resolveSingboxBinaryPath();
    if (binaryPath == null) {
      _lastDiagnosticReport =
          DiagnosticErrorMapper.fromCodeOrError('ERR-CORE-BINARY-MISSING');
      _emitPhase(ConnectionPhase.failed);
      throw Exception('ERR-CORE-BINARY-MISSING');
    }

    if (useTunAdapter && !await _isRunningAsAdministrator()) {
      _lastDiagnosticReport =
          DiagnosticErrorMapper.fromCodeOrError('ERR-TUN-ADMIN');
      _emitPhase(ConnectionPhase.failed);
      throw Exception('ERR-TUN-ADMIN');
    }

    _emitPhase(ConnectionPhase.connecting);

    final listenPort = await _findFreeLocalPort();
    if (listenPort == null) {
      _lastDiagnosticReport =
          DiagnosticErrorMapper.fromCodeOrError('ERR-CORE-PORT');
      _emitPhase(ConnectionPhase.failed);
      throw Exception('ERR-CORE-PORT');
    }

    final configMap = buildDesktopConfig(profile, listenPort: listenPort);
    final tempDir = await Directory.systemTemp.createTemp('speedll_desktop_');
    final configFile =
        File('${tempDir.path}${Platform.pathSeparator}active_config.json');
    await configFile.writeAsString(jsonEncode(configMap), flush: true);
    _activeConfigFile = configFile;

    _stoppingIntentionally = false;
    final generation = ++_connectionGeneration;
    try {
      final proc = await Process.start(
        binaryPath,
        <String>['run', '-c', configFile.path],
        workingDirectory: File(binaryPath).parent.path,
        runInShell: false,
      );
      _singboxProcess = proc;

      final stderrBuffer = StringBuffer();
      proc.stderr.transform(utf8.decoder).listen((chunk) {
        if (stderrBuffer.length < 2048) {
          stderrBuffer.write(chunk);
        }
      });

      var processExitedEarly = false;
      unawaited(
        proc.exitCode.then((code) async {
          if (generation != _connectionGeneration) return;
          processExitedEarly = true;
          if (_stoppingIntentionally) return;
          if (_currentPhase == ConnectionPhase.connected) {
            await _stopRunningProcess(disableProxy: true);
            _lastDiagnosticReport = DiagnosticErrorMapper.fromCodeOrError(
              'ERR-CORE-CRASH: exit=$code ${stderrBuffer.toString()}',
            );
            _emitPhase(ConnectionPhase.failed);
          }
        }),
      );

      final ready = await _waitForLocalInboundReady(
        port: listenPort,
        isExited: () => processExitedEarly,
      );

      if (!ready) {
        final diagnostic = processExitedEarly
            ? 'ERR-CORE-CRASH: exit=${await proc.exitCode} ${stderrBuffer.toString()}'
            : 'ERR-CORE-PORT-TIMEOUT: ${stderrBuffer.toString()}';
        await _stopRunningProcess(disableProxy: true);
        _lastDiagnosticReport =
            DiagnosticErrorMapper.fromCodeOrError(diagnostic);
        _emitPhase(ConnectionPhase.failed);
        throw Exception(diagnostic);
      }

      if (Platform.isWindows && !useTunAdapter) {
        await _configureWindowsSystemProxy(enable: true, port: listenPort);
      }

      _lastDiagnosticReport = null;
      _emitPhase(ConnectionPhase.connected);
    } catch (e) {
      await _stopRunningProcess(disableProxy: true);
      _lastDiagnosticReport ??= DiagnosticErrorMapper.fromCodeOrError(e);
      _emitPhase(ConnectionPhase.failed);
      rethrow;
    }
  }

  Future<int?> _findFreeLocalPort() async {
    ServerSocket? server;
    try {
      server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      return server.port;
    } catch (_) {
      return null;
    } finally {
      await server?.close();
    }
  }

  Future<bool> _isRunningAsAdministrator() async {
    if (!Platform.isWindows) return true;
    try {
      final result = await Process.run(
        'whoami',
        <String>['/groups', '/fo', 'csv', '/nh'],
      );
      if (result.exitCode == 0) {
        final output = result.stdout.toString();
        if (output.contains('S-1-16-12288') ||
            output.contains('S-1-16-16384')) {
          return true;
        }
      }
      final fallback = await Process.run('net', <String>['session']);
      return fallback.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _waitForLocalInboundReady({
    required int port,
    required bool Function() isExited,
  }) async {
    final deadline = DateTime.now().add(const Duration(seconds: 12));
    while (DateTime.now().isBefore(deadline)) {
      if (isExited()) return false;
      try {
        final socket = await Socket.connect(
          '127.0.0.1',
          port,
          timeout: const Duration(milliseconds: 250),
        );
        socket.destroy();
        return true;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
    return false;
  }

  Future<String?> _readRegistryValue(String name) async {
    try {
      final result = await Process.run(
        'reg',
        <String>['query', _internetSettingsKey, '/v', name],
      );
      if (result.exitCode != 0) return null;
      final pattern = RegExp(
        '^\\s*${RegExp.escape(name)}\\s+REG_[A-Z_]+\\s+(.+?)\\s*\$',
        multiLine: true,
      );
      return pattern.firstMatch(result.stdout.toString())?.group(1);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeRegistryValue(
    String name,
    String value,
    String type,
  ) async {
    await Process.run('reg', <String>[
      'add',
      _internetSettingsKey,
      '/v',
      name,
      '/t',
      type,
      '/d',
      value,
      '/f',
    ]);
  }

  Future<void> _deleteRegistryValue(String name) async {
    await Process.run('reg', <String>[
      'delete',
      _internetSettingsKey,
      '/v',
      name,
      '/f',
    ]);
  }

  Future<void> _restoreRegistryValue(
    String name,
    String? value,
    String type,
  ) async {
    if (value == null) {
      await _deleteRegistryValue(name);
    } else {
      await _writeRegistryValue(name, value, type);
    }
  }

  Future<void> _configureWindowsSystemProxy({
    required bool enable,
    int port = 2080,
  }) async {
    if (!Platform.isWindows) return;
    try {
      if (enable) {
        if (!_proxyActive) {
          _proxySnapshot = <String, String?>{
            'ProxyEnable': await _readRegistryValue('ProxyEnable'),
            'ProxyServer': await _readRegistryValue('ProxyServer'),
            'AutoConfigURL': await _readRegistryValue('AutoConfigURL'),
          };
          _proxyActive = true;
        }
        await _deleteRegistryValue('AutoConfigURL');
        await _writeRegistryValue(
          'ProxyServer',
          '127.0.0.1:$port',
          'REG_SZ',
        );
        await _writeRegistryValue('ProxyEnable', '1', 'REG_DWORD');
      } else {
        if (!_proxyActive) return;
        final snapshot = _proxySnapshot;
        _proxyActive = false;
        _proxySnapshot = null;
        if (snapshot == null) {
          await _writeRegistryValue('ProxyEnable', '0', 'REG_DWORD');
        } else {
          await _restoreRegistryValue(
            'ProxyEnable',
            snapshot['ProxyEnable'],
            'REG_DWORD',
          );
          await _restoreRegistryValue(
            'ProxyServer',
            snapshot['ProxyServer'],
            'REG_SZ',
          );
          await _restoreRegistryValue(
            'AutoConfigURL',
            snapshot['AutoConfigURL'],
            'REG_SZ',
          );
        }
      }
    } catch (error) {
      developer.log(
        'Windows system proxy update failed',
        name: 'WindowsVpnEngineAdapter',
        error: error,
      );
    }
  }

  Future<void> _stopRunningProcess({required bool disableProxy}) async {
    _stoppingIntentionally = true;
    _connectionGeneration++;
    if (disableProxy && Platform.isWindows) {
      await _configureWindowsSystemProxy(enable: false);
    }
    final proc = _singboxProcess;
    _singboxProcess = null;
    if (proc != null) {
      try {
        proc.kill(ProcessSignal.sigterm);
      } catch (_) {}
    }
    final file = _activeConfigFile;
    _activeConfigFile = null;
    if (file != null) {
      try {
        if (file.existsSync()) {
          file.deleteSync();
        }
        if (file.parent.existsSync()) {
          file.parent.deleteSync(recursive: true);
        }
      } catch (_) {}
    }
  }

  @override
  Future<void> disconnect() async {
    _emitPhase(ConnectionPhase.disconnecting);
    await _stopRunningProcess(disableProxy: true);
    _emitPhase(ConnectionPhase.disconnected);
  }
}
