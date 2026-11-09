/// Normalized profile metadata. Secrets must be stored separately in secure storage.
class ServerProfile {
  const ServerProfile({
    required this.id,
    required this.displayName,
    required this.protocol,
    required this.source,
    this.countryCode,
    this.engineHint,
  });

  final String id;
  final String displayName;
  final String protocol;
  final ProfileSource source;
  final String? countryCode;
  final String? engineHint;
}

enum ProfileSource {
  manual,
  subscription,
  qrCode,
  speedllAccount,
}
