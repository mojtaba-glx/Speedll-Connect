import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:speedll_subscription/speedll_subscription.dart';

/// Manages persistent storage of server profiles, separated secrets, active profile ID,
/// routing preferences, and subscription URLs inside OS secure storage (Android Keystore).
class SecureProfileStorage {
  const SecureProfileStorage({
    FlutterSecureStorage? secureStorage,
  }) : _storage = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                encryptedSharedPreferences: true,
                resetOnError: true,
              ),
            );

  final FlutterSecureStorage _storage;

  static const String _profilesKey = 'speedll_profiles_v1';
  static const String _activeProfileIdKey = 'speedll_active_profile_id_v1';
  static const String _subscriptionsKey = 'speedll_subscriptions_v1';
  static const String _routingOptionsKey = 'speedll_routing_options_v1';
  static const String _smartModeKey = 'speedll_smart_mode_v1';
  static const String _languageCodeKey = 'speedll_language_code_v1';
  static const String _languageOnboardedKey = 'speedll_language_onboarded_v1';
  static const String _themePresetKey = 'speedll_theme_preset_v1';
  static const String _secretKeyPrefix = 'speedll_secret_';

  /// Keys inside `ServerProfile.extraParams` that represent sensitive credentials
  /// and must be stored in dedicated secret entries rather than general metadata.
  static const Set<String> sensitiveExtraKeys = <String>{
    'uuid',
    'id',
    'password',
    'auth',
    'auth_str',
    'pbk',
    'privateKey',
    'publicKey',
    'shortId',
    'secret',
    'token',
    'obfsPassword',
    'plugin',
    'sid',
    'preSharedKey',
    'pre_shared_key',
    'presharedKey',
  };

  String _secretKeyForProfile(String profileId) =>
      '$_secretKeyPrefix$profileId';

  /// Loads all saved profiles from secure storage, runs schema migration if needed,
  /// and rehydrates each profile with its isolated credentials.
  Future<List<ServerProfile>> loadProfiles() async {
    final rawProfilesJson = await _storage.read(key: _profilesKey);
    if (rawProfilesJson == null || rawProfilesJson.trim().isEmpty) {
      return const <ServerProfile>[];
    }

    try {
      final decoded = jsonDecode(rawProfilesJson);
      if (decoded is! List) {
        return const <ServerProfile>[];
      }

      const migrator = ProfileMigrator();
      final result = <ServerProfile>[];

      for (final item in decoded) {
        if (item is! Map) continue;
        final rawMap = Map<String, dynamic>.from(item);
        final migratedMap = migrator.migrateRawJson(rawMap);
        final profile = ServerProfile.fromJson(migratedMap);
        if (profile.id.isEmpty) continue;

        final rawSecrets = await _storage.read(
          key: _secretKeyForProfile(profile.id),
        );
        Map<String, dynamic> mergedExtra =
            Map<String, dynamic>.from(profile.extraParams);

        if (rawSecrets != null && rawSecrets.isNotEmpty) {
          try {
            final secretMap = jsonDecode(rawSecrets);
            if (secretMap is Map) {
              mergedExtra.addAll(Map<String, dynamic>.from(secretMap));
            }
          } catch (_) {
            // Ignore malformed secret entry and retain metadata
          }
        }

        result.add(profile.copyWith(extraParams: mergedExtra));
      }

      return result;
    } catch (_) {
      return const <ServerProfile>[];
    }
  }

  /// Persists profiles by splitting sensitive credentials into dedicated Android Keystore
  /// entries and saving sanitized metadata separately.
  Future<void> saveProfiles(List<ServerProfile> profiles) async {
    final sanitizedMetadataList = <Map<String, dynamic>>[];

    for (final profile in profiles) {
      final publicExtra = <String, dynamic>{};
      final secretExtra = <String, dynamic>{};

      profile.extraParams.forEach((key, value) {
        if (sensitiveExtraKeys.contains(key)) {
          secretExtra[key] = value;
        } else {
          publicExtra[key] = value;
        }
      });

      await _storage.write(
        key: _secretKeyForProfile(profile.id),
        value: jsonEncode(secretExtra),
      );

      final sanitizedProfile = profile.copyWith(extraParams: publicExtra);
      sanitizedMetadataList.add(sanitizedProfile.toJson());
    }

    await _storage.write(
      key: _profilesKey,
      value: jsonEncode(sanitizedMetadataList),
    );
  }

  /// Deletes a specific profile's isolated secret entry and updates the stored profile list.
  Future<void> deleteProfileSecret(String profileId) async {
    await _storage.delete(key: _secretKeyForProfile(profileId));
  }

  Future<String?> loadActiveProfileId() async {
    return _storage.read(key: _activeProfileIdKey);
  }

  Future<void> saveActiveProfileId(String? profileId) async {
    if (profileId == null || profileId.isEmpty) {
      await _storage.delete(key: _activeProfileIdKey);
    } else {
      await _storage.write(key: _activeProfileIdKey, value: profileId);
    }
  }

  Future<SingboxRoutingOptions> loadRoutingOptions() async {
    final raw = await _storage.read(key: _routingOptionsKey);
    if (raw == null || raw.isEmpty) {
      return const SingboxRoutingOptions();
    }
    try {
      final map = jsonDecode(raw);
      if (map is Map) {
        final dnsVersion = map['dnsDefaultsVersion'] as int? ?? 1;
        var directDns = map['directDnsServer'] as String? ?? '178.22.122.100';
        if (dnsVersion < 2 && directDns == '8.8.8.8') {
          directDns = '178.22.122.100';
        }
        // Migrate pre-v3 installs to default Sniffing OFF while preserving
        // explicit user toggles once saved at dnsDefaultsVersion >= 3.
        final enableSniffing = dnsVersion < 3
            ? false
            : (map['enableTrafficSniffing'] as bool? ?? false);
        return SingboxRoutingOptions(
          region: RoutingRegion.fromWireName(map['region'] as String?),
          bypassLan: map['bypassLan'] as bool? ?? true,
          bypassIranDomains: map['bypassIranDomains'] as bool? ?? true,
          customDirectDomains: (map['customDirectDomains'] as List?)
                  ?.map((e) => e.toString())
                  .toList() ??
              const <String>[],
          customDirectCidrs: (map['customDirectCidrs'] as List?)
                  ?.map((e) => e.toString())
                  .toList() ??
              const <String>[],
          remoteDnsServer: map['remoteDnsServer'] as String? ?? '1.1.1.1',
          directDnsServer: directDns,
          enableTrafficSniffing: enableSniffing,
          enableMux: map['enableMux'] as bool? ?? false,
          killSwitch: map['killSwitch'] as bool? ?? false,
        );
      }
    } catch (_) {}
    return const SingboxRoutingOptions();
  }

  Future<void> saveRoutingOptions(SingboxRoutingOptions options) async {
    final payload = jsonEncode(<String, dynamic>{
      'region': options.region.name,
      'bypassLan': options.bypassLan,
      'bypassIranDomains': options.bypassIranDomains,
      'customDirectDomains': options.customDirectDomains,
      'customDirectCidrs': options.customDirectCidrs,
      'remoteDnsServer': options.remoteDnsServer,
      'directDnsServer': options.directDnsServer,
      'enableTrafficSniffing': options.enableTrafficSniffing,
      'enableMux': options.enableMux,
      'killSwitch': options.killSwitch,
      'dnsDefaultsVersion': 3,
    });
    await _storage.write(key: _routingOptionsKey, value: payload);
  }

  Future<List<SubscriptionSource>> loadSubscriptions() async {
    final raw = await _storage.read(key: _subscriptionsKey);
    if (raw == null || raw.isEmpty) {
      return const <SubscriptionSource>[];
    }
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const <SubscriptionSource>[];
      return list
          .whereType<Map>()
          .map((m) => SubscriptionSource.fromJson(Map<String, dynamic>.from(m)))
          .where((s) => s.url.isNotEmpty)
          .toList();
    } catch (_) {
      return const <SubscriptionSource>[];
    }
  }

  Future<void> saveSubscriptions(List<SubscriptionSource> subscriptions) async {
    final encoded = jsonEncode(subscriptions.map((s) => s.toJson()).toList());
    await _storage.write(key: _subscriptionsKey, value: encoded);
  }

  Future<bool> loadSmartModeEnabled() async {
    final raw = await _storage.read(key: _smartModeKey);
    if (raw == null || raw.isEmpty) {
      return false;
    }
    return raw.toLowerCase() == 'true';
  }

  Future<void> saveSmartModeEnabled(bool enabled) async {
    await _storage.write(key: _smartModeKey, value: enabled ? 'true' : 'false');
  }

  Future<String?> loadAppLanguageCode() async {
    final raw = await _storage.read(key: _languageCodeKey);
    if (raw == null || raw.trim().isEmpty) return null;
    return raw.trim().toLowerCase();
  }

  Future<void> saveAppLanguageCode(String languageCode) async {
    await _storage.write(
      key: _languageCodeKey,
      value: languageCode.trim().toLowerCase(),
    );
  }

  Future<bool> loadHasCompletedLanguageOnboarding() async {
    final raw = await _storage.read(key: _languageOnboardedKey);
    return raw?.toLowerCase() == 'true';
  }

  Future<void> saveHasCompletedLanguageOnboarding(bool completed) async {
    await _storage.write(
      key: _languageOnboardedKey,
      value: completed ? 'true' : 'false',
    );
  }

  Future<String?> loadThemePresetName() async {
    final raw = await _storage.read(key: _themePresetKey);
    if (raw == null || raw.trim().isEmpty) return null;
    return raw.trim();
  }

  Future<void> saveThemePresetName(String presetName) async {
    await _storage.write(
      key: _themePresetKey,
      value: presetName.trim(),
    );
  }
}
