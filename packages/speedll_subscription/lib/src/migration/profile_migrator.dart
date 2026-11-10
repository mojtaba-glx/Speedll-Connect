import '../models/server_profile.dart';

class MigrationException implements Exception {
  const MigrationException(this.message, {this.fromVersion, this.toVersion});

  final String message;
  final int? fromVersion;
  final int? toVersion;

  @override
  String toString() => 'MigrationException: $message (from: $fromVersion, to: $toVersion)';
}

/// Upgrades raw profile maps or models from older schema versions to currentSchemaVersion.
class ProfileMigrator {
  const ProfileMigrator();

  int get targetVersion => ServerProfile.currentSchemaVersion;

  /// Migrates a raw JSON map to the current schema specification before parsing.
  Map<String, dynamic> migrateRawJson(Map<String, dynamic> rawJson) {
    final rawVersion = rawJson['schemaVersion'];
    int currentVersion = rawVersion is int ? rawVersion : 0;

    if (currentVersion > targetVersion) {
      throw MigrationException(
        'Profile version $currentVersion is newer than supported version $targetVersion',
        fromVersion: currentVersion,
        toVersion: targetVersion,
      );
    }

    var migrated = Map<String, dynamic>.from(rawJson);

    // Step from version 0 (legacy unversioned) to version 1
    if (currentVersion == 0) {
      migrated = _migrateV0ToV1(migrated);
      currentVersion = 1;
    }

    // Future version migrations will chain here:
    // if (currentVersion == 1 && targetVersion >= 2) { migrated = _migrateV1ToV2(migrated); currentVersion = 2; }

    return migrated;
  }

  /// Migrates a ServerProfile instance if its schemaVersion is outdated.
  ServerProfile migrateProfile(ServerProfile profile) {
    if (profile.schemaVersion == targetVersion) {
      return profile;
    }

    final raw = profile.toJson();
    final upgradedRaw = migrateRawJson(raw);
    return ServerProfile.fromJson(upgradedRaw);
  }

  /// Migrates a list of raw profile dictionaries.
  List<ServerProfile> migrateBatch(List<Map<String, dynamic>> rawItems) {
    return rawItems.map((raw) {
      final migratedRaw = migrateRawJson(raw);
      return ServerProfile.fromJson(migratedRaw);
    }).toList();
  }

  Map<String, dynamic> _migrateV0ToV1(Map<String, dynamic> legacy) {
    final updated = Map<String, dynamic>.from(legacy);
    updated['schemaVersion'] = 1;

    // Ensure id exists
    if (updated['id'] == null || (updated['id'] as String).trim().isEmpty) {
      updated['id'] = 'profile_${DateTime.now().millisecondsSinceEpoch}';
    }

    // Ensure displayName exists
    if (updated['displayName'] == null || (updated['displayName'] as String).trim().isEmpty) {
      updated['displayName'] = 'سرور بازیابی‌شده';
    }

    // Normalize protocol
    final proto = (updated['protocol'] as String? ?? 'vless').toLowerCase();
    updated['protocol'] = proto;

    // Ensure timestamps exist
    final nowIso = DateTime.now().toUtc().toIso8601String();
    updated['createdAt'] ??= nowIso;
    updated['updatedAt'] ??= nowIso;

    // Extra parameters default
    updated['extraParams'] ??= <String, dynamic>{};

    return updated;
  }
}
