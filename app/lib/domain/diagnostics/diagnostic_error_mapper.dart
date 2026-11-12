/// Maps native/engine failures and exceptions into user-friendly Persian messages
/// and redacted diagnostic codes without exposing any secrets, UUIDs, passwords,
/// tokens, or server IP addresses.
class DiagnosticReport {
  const DiagnosticReport({
    required this.code,
    required this.userMessage,
    required this.redactedDetail,
  });

  final String code;
  final String userMessage;
  final String redactedDetail;

  String get formattedDisplay => '$userMessage (کد تشخیصی: $code)';
}

class DiagnosticErrorMapper {
  const DiagnosticErrorMapper();

  static final RegExp _uuidPattern = RegExp(
    r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
  );

  static final RegExp _ipv4Pattern = RegExp(
    r'\b(?:\d{1,3}\.){3}\d{1,3}(?::\d{1,5})?\b',
  );

  static final RegExp _uriSchemePattern = RegExp(
    r'(?:vless|vmess|trojan|ss|hysteria2?|hy2|tuic|anytls|https?)://[^\s",]+',
    caseSensitive: false,
  );

  static final RegExp _kvSecretPattern = RegExp(
    r'(?:uuid|id|password|auth|auth_str|pbk|sid|shortId|privateKey|publicKey|token|secret|obfs-password|obfsPassword|plugin)\s*[:=]\s*[^\s,&"}]+',
    caseSensitive: false,
  );

  /// Redacts any sensitive credential, UUID, URI, or IP address from raw text.
  static String redactSecrets(String raw) {
    return raw
        .replaceAll(_uriSchemePattern, '[REDACTED-URI]')
        .replaceAll(_uuidPattern, '[REDACTED-UUID]')
        .replaceAll(_kvSecretPattern, '[REDACTED-SECRET]')
        .replaceAll(_ipv4Pattern, '[REDACTED-IP]');
  }

  /// Resolves a diagnostic code (such as `ERR-CORE-CONFIG` from native service)
  /// or an arbitrary exception into a safe [DiagnosticReport].
  static DiagnosticReport fromCodeOrError(Object errorOrCode) {
    final raw = errorOrCode.toString().trim();
    final safeRaw = redactSecrets(raw);

    // Check explicit native diagnostic codes (`failed:ERR-...` or `ERR-...`)
    final normalizedCode = _extractExplicitCode(raw);
    if (normalizedCode != null) {
      return DiagnosticReport(
        code: normalizedCode,
        userMessage: _messageForCode(normalizedCode),
        redactedDetail: safeRaw,
      );
    }

    final lower = raw.toLowerCase();
    if (lower.contains('permission') || lower.contains('مجوز')) {
      return DiagnosticReport(
        code: 'ERR-VPN-PERMISSION',
        userMessage: _messageForCode('ERR-VPN-PERMISSION'),
        redactedDetail: safeRaw,
      );
    }
    if (lower.contains('پشتیبانی نمی‌شود') ||
        lower.contains('singboxconvertexception') ||
        lower.contains('نامعتبر')) {
      return DiagnosticReport(
        code: 'ERR-PROFILE-INVALID',
        userMessage: _messageForCode('ERR-PROFILE-INVALID'),
        redactedDetail: safeRaw,
      );
    }
    if (lower.contains('network') || lower.contains('socket')) {
      return DiagnosticReport(
        code: 'ERR-NET-UNREACHABLE',
        userMessage: _messageForCode('ERR-NET-UNREACHABLE'),
        redactedDetail: safeRaw,
      );
    }

    return DiagnosticReport(
      code: 'ERR-CONN-GENERAL',
      userMessage: _messageForCode('ERR-CONN-GENERAL'),
      redactedDetail: safeRaw,
    );
  }

  static String? _extractExplicitCode(String input) {
    final match = RegExp(r'(ERR-[A-Z0-9-]+)').firstMatch(input.toUpperCase());
    return match?.group(1);
  }

  static String _messageForCode(String code) {
    return switch (code) {
      'ERR-CORE-CONFIG' =>
        'ساختار کانفیگ سرور با هسته اتصال سازگار نیست. لطفاً کانفیگ را بررسی یا به‌روزرسانی کنید.',
      'ERR-CORE-BINARY' ||
      'ERR-CORE-BINARY-MISSING' =>
        'فایل اجرایی هسته اتصال روی دستگاه یافت نشد یا مجوز اجرا ندارد.',
      'ERR-CORE-PORT' ||
      'ERR-CORE-PORT-TIMEOUT' =>
        'پورت داخلی تونل در حال استفاده است. لطفاً یک‌بار اتصال را قطع و مجدداً تلاش کنید.',
      'ERR-CORE-PERM' => 'سیستم‌عامل اجازه دسترسی شبکه به هسته اتصال را نداد.',
      'ERR-CORE-START' =>
        'راه‌اندازی هسته اتصال با خطا مواجه شد. لطفاً سرور دیگری را امتحان کنید.',
      'ERR-CORE-CRASH' =>
        'هسته اتصال به‌طور ناگهانی متوقف شد و اتصال قطع شد. لطفاً دوباره تلاش کنید.',
      'ERR-TUN-ESTABLISH' =>
        'ایجاد رابط شبکه VPN در اندروید ناموفق بود. لطفاً مجوز VPN دستگاه را بررسی کنید.',
      'ERR-TUN-ADMIN' =>
        'برای استفاده از حالت TUN در ویندوز، برنامه را با دسترسی Administrator اجرا کنید.',
      'ERR-NET-SWITCH' =>
        'بازیابی خودکار اتصال پس از تغییر شبکه (Wi-Fi/موبایل) ناموفق بود. لطفاً دوباره متصل شوید.',
      'ERR-VPN-PERMISSION' => 'مجوز ایجاد اتصال VPN توسط کاربر تایید نشد.',
      'ERR-PROFILE-INVALID' => 'تنظیمات این پروفایل ناقص یا ناسازگار است.',
      'ERR-NET-UNREACHABLE' =>
        'دسترسی به شبکه اینترنت برقرار نیست. اتصال Wi-Fi یا داده موبایل خود را بررسی کنید.',
      _ =>
        'برقراری اتصال با خطا مواجه شد. لطفاً تنظیمات شبکه یا سرور خود را بررسی کنید.',
    };
  }
}
