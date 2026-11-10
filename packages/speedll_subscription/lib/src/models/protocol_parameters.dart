import 'package:meta/meta.dart';

@immutable
class RealityParameters {
  const RealityParameters({
    required this.publicKey,
    this.shortId,
    this.fingerprint = 'chrome',
    this.serverName,
    this.spiderX,
  });

  final String publicKey;
  final String? shortId;
  final String fingerprint;
  final String? serverName;
  final String? spiderX;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'publicKey': publicKey,
        if (shortId != null) 'shortId': shortId,
        'fingerprint': fingerprint,
        if (serverName != null) 'serverName': serverName,
        if (spiderX != null) 'spiderX': spiderX,
      };

  factory RealityParameters.fromJson(Map<String, dynamic> json) {
    return RealityParameters(
      publicKey: json['publicKey'] as String? ?? '',
      shortId: json['shortId'] as String?,
      fingerprint: json['fingerprint'] as String? ?? 'chrome',
      serverName: json['serverName'] as String?,
      spiderX: json['spiderX'] as String?,
    );
  }
}

@immutable
class TransportParameters {
  const TransportParameters({
    this.type = 'tcp',
    this.path,
    this.host,
    this.serviceName,
  });

  final String type;
  final String? path;
  final String? host;
  final String? serviceName;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'type': type,
        if (path != null) 'path': path,
        if (host != null) 'host': host,
        if (serviceName != null) 'serviceName': serviceName,
      };

  factory TransportParameters.fromJson(Map<String, dynamic> json) {
    return TransportParameters(
      type: json['type'] as String? ?? 'tcp',
      path: json['path'] as String?,
      host: json['host'] as String?,
      serviceName: json['serviceName'] as String?,
    );
  }
}

@immutable
class Hysteria2Parameters {
  const Hysteria2Parameters({
    this.auth,
    this.obfsType,
    this.obfsPassword,
    this.multiPort,
    this.insecure = false,
    this.sni,
  });

  final String? auth;
  final String? obfsType;
  final String? obfsPassword;
  final String? multiPort;
  final bool insecure;
  final String? sni;

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (auth != null) 'auth': auth,
        if (obfsType != null) 'obfsType': obfsType,
        if (obfsPassword != null) 'obfsPassword': obfsPassword,
        if (multiPort != null) 'multiPort': multiPort,
        'insecure': insecure,
        if (sni != null) 'sni': sni,
      };

  factory Hysteria2Parameters.fromJson(Map<String, dynamic> json) {
    return Hysteria2Parameters(
      auth: json['auth'] as String?,
      obfsType: json['obfsType'] as String?,
      obfsPassword: json['obfsPassword'] as String?,
      multiPort: json['multiPort'] as String?,
      insecure: json['insecure'] as bool? ?? false,
      sni: json['sni'] as String?,
    );
  }
}
