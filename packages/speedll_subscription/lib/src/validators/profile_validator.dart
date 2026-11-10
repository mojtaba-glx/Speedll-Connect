import '../models/server_profile.dart';

class ValidationResult {
  const ValidationResult({
    required this.isValid,
    this.errors = const <String>[],
  });

  final bool isValid;
  final List<String> errors;

  factory ValidationResult.valid() => const ValidationResult(isValid: true);

  factory ValidationResult.invalid(List<String> errors) =>
      ValidationResult(isValid: false, errors: errors);
}

class ProfileValidator {
  const ProfileValidator();

  static const List<String> supportedProtocols = <String>[
    'vless',
    'vmess',
    'trojan',
    'shadowsocks',
    'hysteria2',
  ];

  ValidationResult validate(ServerProfile profile) {
    final errors = <String>[];

    if (profile.id.trim().isEmpty) {
      errors.add('شناسه سرور نمی‌تواند خالی باشد.');
    }

    if (profile.displayName.trim().isEmpty) {
      errors.add('نام نمایشی سرور نامعتبر است.');
    }

    if (!supportedProtocols.contains(profile.protocol.toLowerCase())) {
      errors.add('پروتکل "${profile.protocol}" پشتیبانی نمی‌شود.');
    }

    if (profile.serverPort != null) {
      if (profile.serverPort! < 1 || profile.serverPort! > 65535) {
        errors.add('پورت سرور (${profile.serverPort}) باید بین ۱ تا ۶۵۵۳۵ باشد.');
      }
    }

    if (errors.isEmpty) {
      return ValidationResult.valid();
    }
    return ValidationResult.invalid(errors);
  }
}
