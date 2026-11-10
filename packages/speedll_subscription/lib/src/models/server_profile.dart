import 'package:meta/meta.dart';

enum ProfileSource {
  manual,
  subscription,
  qrCode,
  speedllAccount;

  String get wireName => name;

  static ProfileSource fromWireName(String value) {
    return ProfileSource.values.firstWhere(
      (element) => element.name.toLowerCase() == value.toLowerCase(),
      orElse: () => ProfileSource.manual,
    );
  }
}

/// Normalized profile metadata. Secrets must be stored separately in secure storage.
@immutable
class ServerProfile {
  static const int currentSchemaVersion = 1;

  const ServerProfile({
    required this.id,
    required this.displayName,
    required this.protocol,
    required this.source,
    this.schemaVersion = currentSchemaVersion,
    this.countryCode,
    this.engineHint,
    this.serverAddress,
    this.serverPort,
    this.extraParams = const <String, dynamic>{},
    this.createdAt,
    this.updatedAt,
  });

  final int schemaVersion;
  final String id;
  final String displayName;
  final String protocol;
  final ProfileSource source;
  final String? countryCode;
  final String? engineHint;
  final String? serverAddress;
  final int? serverPort;
  final Map<String, dynamic> extraParams;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  DateTime get safeCreatedAt =>
      createdAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  DateTime get safeUpdatedAt =>
      updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  ServerProfile copyWith({
    int? schemaVersion,
    String? id,
    String? displayName,
    String? protocol,
    ProfileSource? source,
    String? countryCode,
    String? engineHint,
    String? serverAddress,
    int? serverPort,
    Map<String, dynamic>? extraParams,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ServerProfile(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      protocol: protocol ?? this.protocol,
      source: source ?? this.source,
      countryCode: countryCode ?? this.countryCode,
      engineHint: engineHint ?? this.engineHint,
      serverAddress: serverAddress ?? this.serverAddress,
      serverPort: serverPort ?? this.serverPort,
      extraParams: extraParams ?? this.extraParams,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'schemaVersion': schemaVersion,
      'id': id,
      'displayName': displayName,
      'protocol': protocol,
      'source': source.wireName,
      if (countryCode != null) 'countryCode': countryCode,
      if (engineHint != null) 'engineHint': engineHint,
      if (serverAddress != null) 'serverAddress': serverAddress,
      if (serverPort != null) 'serverPort': serverPort,
      if (extraParams.isNotEmpty) 'extraParams': extraParams,
      if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    };
  }

  factory ServerProfile.fromJson(Map<String, dynamic> json) {
    final rawVersion = json['schemaVersion'];
    final version = rawVersion is int ? rawVersion : 1;

    final rawSource = json['source'] as String? ?? 'manual';
    final parsedSource = ProfileSource.fromWireName(rawSource);

    final rawCreated = json['createdAt'] as String?;
    final rawUpdated = json['updatedAt'] as String?;

    return ServerProfile(
      schemaVersion: version,
      id: json['id'] as String? ?? '',
      displayName: json['displayName'] as String? ?? 'سرور بدون نام',
      protocol: (json['protocol'] as String? ?? 'vless').toLowerCase(),
      source: parsedSource,
      countryCode: json['countryCode'] as String?,
      engineHint: json['engineHint'] as String?,
      serverAddress: json['serverAddress'] as String?,
      serverPort: json['serverPort'] as int?,
      extraParams: json['extraParams'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(json['extraParams'] as Map)
          : const <String, dynamic>{},
      createdAt: rawCreated != null ? DateTime.tryParse(rawCreated) : null,
      updatedAt: rawUpdated != null ? DateTime.tryParse(rawUpdated) : null,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ServerProfile &&
        other.schemaVersion == schemaVersion &&
        other.id == id &&
        other.displayName == displayName &&
        other.protocol == protocol &&
        other.source == source &&
        other.countryCode == countryCode &&
        other.engineHint == engineHint &&
        other.serverAddress == serverAddress &&
        other.serverPort == serverPort;
  }

  @override
  int get hashCode => Object.hash(
        schemaVersion,
        id,
        displayName,
        protocol,
        source,
        countryCode,
        engineHint,
        serverAddress,
        serverPort,
      );
}
