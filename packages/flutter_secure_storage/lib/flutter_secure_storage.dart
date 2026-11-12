library;

import 'dart:convert';
import 'dart:io' show Directory, File, Platform, Process;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'src/dpapi.dart';

@immutable
class AndroidOptions {
  const AndroidOptions({
    this.encryptedSharedPreferences = true,
    this.resetOnError = true,
    this.sharedPreferencesName,
    this.preferencesKeyPrefix,
  });

  static const AndroidOptions defaultOptions = AndroidOptions();

  final bool encryptedSharedPreferences;
  final bool resetOnError;
  final String? sharedPreferencesName;
  final String? preferencesKeyPrefix;

  Map<String, String> toMap() => <String, String>{
        'encryptedSharedPreferences': encryptedSharedPreferences.toString(),
        'resetOnError': resetOnError.toString(),
        if (sharedPreferencesName != null)
          'sharedPreferencesName': sharedPreferencesName!,
        if (preferencesKeyPrefix != null)
          'preferencesKeyPrefix': preferencesKeyPrefix!,
      };
}

@immutable
class IOSOptions {
  const IOSOptions();
  static const IOSOptions defaultOptions = IOSOptions();
}

/// Provides secure key-value storage backed by native OS Keystore (AndroidKeyStore AES-256-GCM on Android)
/// and user-isolated persistent vault storage on Windows/Linux/macOS desktop.
class FlutterSecureStorage {
  const FlutterSecureStorage({
    this.aOptions = AndroidOptions.defaultOptions,
    this.iOptions = IOSOptions.defaultOptions,
  });

  final AndroidOptions aOptions;
  final IOSOptions iOptions;

  static const MethodChannel _channel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  /// Fallback store used when native MethodChannel is unavailable (e.g. headless widget tests or desktop).
  static final Map<String, String> _fallbackMemoryStore = <String, String>{};
  static bool _desktopVaultLoaded = false;
  static const List<int> _vaultMagic = <int>[
    0x53,
    0x50,
    0x56,
    0x44,
    0x50,
    0x31
  ];

  static int _maskByte(int index) => (0x5A + (index * 31)) & 0xFF;

  static bool _hasVaultMagic(Uint8List bytes) {
    if (bytes.length < _vaultMagic.length) return false;
    for (var i = 0; i < _vaultMagic.length; i++) {
      if (bytes[i] != _vaultMagic[i]) return false;
    }
    return true;
  }

  static Uint8List _encodeDesktopVault(Map<String, String> store) {
    final plain = utf8.encode(jsonEncode(store));
    if (Platform.isWindows) {
      final protected = Dpapi.instance.protect(Uint8List.fromList(plain));
      return Uint8List.fromList(<int>[..._vaultMagic, ...protected]);
    }
    return Uint8List.fromList(
      List<int>.generate(plain.length, (i) => plain[i] ^ _maskByte(i)),
    );
  }

  static Map<String, String>? _decodeDesktopVault(Uint8List raw) {
    try {
      Uint8List plain;
      if (Platform.isWindows && _hasVaultMagic(raw)) {
        plain = Dpapi.instance.unprotect(
          Uint8List.fromList(raw.sublist(_vaultMagic.length)),
        );
      } else {
        plain = Uint8List.fromList(
          List<int>.generate(raw.length, (i) => raw[i] ^ _maskByte(i)),
        );
      }
      final decoded = jsonDecode(utf8.decode(plain));
      if (decoded is! Map) return null;
      final result = <String, String>{};
      decoded.forEach((dynamic k, dynamic v) {
        if (k != null && v != null) {
          result[k.toString()] = v.toString();
        }
      });
      return result;
    } catch (error) {
      debugPrint('Speedll vault decode failed: $error');
      return null;
    }
  }

  static bool get _isTestEnvironment =>
      !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

  static bool get _isDesktopEnvironment =>
      !kIsWeb &&
      !_isTestEnvironment &&
      (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  @visibleForTesting
  static void clearFallbackStore() {
    _fallbackMemoryStore.clear();
  }

  static File? _resolveDesktopVaultFile() {
    if (!_isDesktopEnvironment) return null;
    final sep = Platform.pathSeparator;
    final baseDir = Platform.isWindows
        ? (Platform.environment['LOCALAPPDATA'] ??
            Platform.environment['APPDATA'])
        : (Platform.environment['HOME'] != null
            ? '${Platform.environment['HOME']}$sep.config'
            : null);
    if (baseDir == null || baseDir.isEmpty) return null;
    final dir = Directory('$baseDir${sep}SpeedllConnect');
    if (!dir.existsSync()) {
      try {
        dir.createSync(recursive: true);
      } catch (_) {
        return null;
      }
    }
    return File('${dir.path}${sep}secure_vault_v1.bin');
  }

  static void _ensureDesktopVaultLoaded() {
    if (_desktopVaultLoaded || !_isDesktopEnvironment) return;
    _desktopVaultLoaded = true;
    final file = _resolveDesktopVaultFile();
    if (file == null || !file.existsSync()) return;
    try {
      final decoded = _decodeDesktopVault(file.readAsBytesSync());
      if (decoded != null) {
        _fallbackMemoryStore.addAll(decoded);
      }
    } catch (error) {
      debugPrint('Speedll vault load failed: $error');
    }
  }

  static void _persistDesktopVault() {
    if (!_isDesktopEnvironment) return;
    final file = _resolveDesktopVaultFile();
    if (file == null) return;
    try {
      file.writeAsBytesSync(_encodeDesktopVault(_fallbackMemoryStore),
          flush: true);
      if (!Platform.isWindows) {
        Process.runSync('chmod', <String>['600', file.path]);
      }
    } catch (error) {
      debugPrint('Speedll vault persist failed: $error');
    }
  }

  Map<String, dynamic> _buildArgs({
    String? key,
    String? value,
    AndroidOptions? aOptions,
  }) {
    final effectiveAndroid = aOptions ?? this.aOptions;
    return <String, dynamic>{
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      'options': effectiveAndroid.toMap(),
    };
  }

  Future<void> write({
    required String key,
    required String? value,
    AndroidOptions? aOptions,
    IOSOptions? iOptions,
  }) async {
    if (value == null) {
      await delete(key: key, aOptions: aOptions, iOptions: iOptions);
      return;
    }
    if (_isTestEnvironment) {
      _fallbackMemoryStore[key] = value;
      return;
    }
    if (_isDesktopEnvironment) {
      _ensureDesktopVaultLoaded();
      _fallbackMemoryStore[key] = value;
      _persistDesktopVault();
      return;
    }
    try {
      await _channel.invokeMethod<void>(
        'write',
        _buildArgs(key: key, value: value, aOptions: aOptions),
      );
    } on MissingPluginException {
      _fallbackMemoryStore[key] = value;
    }
  }

  Future<String?> read({
    required String key,
    AndroidOptions? aOptions,
    IOSOptions? iOptions,
  }) async {
    if (_isTestEnvironment) {
      return _fallbackMemoryStore[key];
    }
    if (_isDesktopEnvironment) {
      _ensureDesktopVaultLoaded();
      return _fallbackMemoryStore[key];
    }
    try {
      return await _channel.invokeMethod<String>(
        'read',
        _buildArgs(key: key, aOptions: aOptions),
      );
    } on MissingPluginException {
      return _fallbackMemoryStore[key];
    }
  }

  Future<bool> containsKey({
    required String key,
    AndroidOptions? aOptions,
    IOSOptions? iOptions,
  }) async {
    if (_isTestEnvironment) {
      return _fallbackMemoryStore.containsKey(key);
    }
    if (_isDesktopEnvironment) {
      _ensureDesktopVaultLoaded();
      return _fallbackMemoryStore.containsKey(key);
    }
    try {
      final result = await _channel.invokeMethod<bool>(
        'containsKey',
        _buildArgs(key: key, aOptions: aOptions),
      );
      return result ?? false;
    } on MissingPluginException {
      return _fallbackMemoryStore.containsKey(key);
    }
  }

  Future<void> delete({
    required String key,
    AndroidOptions? aOptions,
    IOSOptions? iOptions,
  }) async {
    if (_isTestEnvironment) {
      _fallbackMemoryStore.remove(key);
      return;
    }
    if (_isDesktopEnvironment) {
      _ensureDesktopVaultLoaded();
      _fallbackMemoryStore.remove(key);
      _persistDesktopVault();
      return;
    }
    try {
      await _channel.invokeMethod<void>(
        'delete',
        _buildArgs(key: key, aOptions: aOptions),
      );
    } on MissingPluginException {
      _fallbackMemoryStore.remove(key);
    }
  }

  Future<Map<String, String>> readAll({
    AndroidOptions? aOptions,
    IOSOptions? iOptions,
  }) async {
    if (_isTestEnvironment) {
      return Map<String, String>.unmodifiable(_fallbackMemoryStore);
    }
    if (_isDesktopEnvironment) {
      _ensureDesktopVaultLoaded();
      return Map<String, String>.unmodifiable(_fallbackMemoryStore);
    }
    try {
      final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'readAll',
        _buildArgs(aOptions: aOptions),
      );
      if (raw == null) return const <String, String>{};
      return raw.map(
        (dynamic k, dynamic v) => MapEntry(k.toString(), v?.toString() ?? ''),
      );
    } on MissingPluginException {
      return Map<String, String>.unmodifiable(_fallbackMemoryStore);
    }
  }

  Future<void> deleteAll({
    AndroidOptions? aOptions,
    IOSOptions? iOptions,
  }) async {
    if (_isTestEnvironment) {
      _fallbackMemoryStore.clear();
      return;
    }
    if (_isDesktopEnvironment) {
      _ensureDesktopVaultLoaded();
      _fallbackMemoryStore.clear();
      _persistDesktopVault();
      return;
    }
    try {
      await _channel.invokeMethod<void>(
        'deleteAll',
        _buildArgs(aOptions: aOptions),
      );
    } on MissingPluginException {
      _fallbackMemoryStore.clear();
    }
  }
}
