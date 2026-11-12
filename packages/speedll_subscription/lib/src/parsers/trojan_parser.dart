import '../models/server_profile.dart';
import 'subscription_parser.dart';

class TrojanParser implements SubscriptionParser {
  const TrojanParser();

  @override
  String get parserName => 'Trojan';

  @override
  bool canParse(String content) {
    final trimmed = content.replaceAll('\uFEFF', '').trim();
    return !trimmed.contains('\n') &&
        !trimmed.contains('\r') &&
        trimmed.toLowerCase().startsWith('trojan://');
  }

  @override
  Future<ParseResult> parse(String content) async {
    final trimmed = content.replaceAll('\uFEFF', '').trim();
    if (!canParse(trimmed)) {
      return ParseResult.failure('محتوای داده شده لینک معتبر Trojan نیست.');
    }

    try {
      final safeUri = SafeProxyUri.parse(trimmed);
      final uri = safeUri.uri;
      final password = Uri.decodeComponent(uri.userInfo);
      if (password.isEmpty) {
        return ParseResult.failure('رمز عبور در لینک Trojan یافت نشد.');
      }

      final host = uri.host;
      if (host.isEmpty) {
        return ParseResult.failure('آدرس سرور در لینک Trojan خالی است.');
      }

      final port = uri.hasPort && uri.port > 0 ? uri.port : 443;
      final query = uri.queryParameters;
      final displayName =
          safeUri.fragment.isNotEmpty ? safeUri.fragment : '$host:$port';

      final isInfoNode = SafeProxyUri.isInfoMetadataProfile(
        host: host,
        port: port,
        displayName: displayName,
      );

      final rawSecurity = _nonEmpty(query['security'])?.toLowerCase();
      final pbk = _nonEmpty(query['pbk']);
      final security = rawSecurity ??
          ((pbk != null && pbk.isNotEmpty) ? 'reality' : 'tls');
      final rawType = (_nonEmpty(query['type']) ?? 'tcp').toLowerCase();
      final transportType = rawType == 'h2' ? 'http' : rawType;
      final allowInsecure = query['allowInsecure'] == '1' ||
          query['allowInsecure']?.toLowerCase() == 'true' ||
          query['insecure'] == '1' ||
          query['insecure']?.toLowerCase() == 'true';

      final extra = <String, dynamic>{
        ...query,
        'password': password,
        'security': security,
        'sni': _nonEmpty(query['sni']) ?? _nonEmpty(query['peer']),
        'transportType': transportType,
        if (_nonEmpty(query['headerType']) != null)
          'headerType': _nonEmpty(query['headerType'])!.toLowerCase(),
        'serviceName':
            _nonEmpty(query['serviceName']) ?? _nonEmpty(query['service_name']),
        'path': _nonEmpty(query['path']),
        'host': _nonEmpty(query['host']) ?? _nonEmpty(query['authority']),
        if (pbk != null) 'pbk': pbk,
        if (_nonEmpty(query['sid']) != null) 'sid': _nonEmpty(query['sid']),
        if (_nonEmpty(query['alpn']) != null) 'alpn': _nonEmpty(query['alpn']),
        if (_nonEmpty(query['fp']) != null)
          'fingerprint': _nonEmpty(query['fp']),
        if (allowInsecure) 'allowInsecure': true,
        if (isInfoNode) 'isInfoNode': true,
      };

      final uniqueSuffix = SafeProxyUri.stableHash(trimmed);
      final profile = ServerProfile(
        id: 'trojan_${host}_${port}_$uniqueSuffix',
        displayName: displayName,
        protocol: 'trojan',
        source: ProfileSource.subscription,
        serverAddress: host,
        serverPort: port,
        extraParams: extra,
      );

      return ParseResult.success([profile]);
    } catch (e) {
      return ParseResult.failure('خطا در تحلیل لینک Trojan: $e');
    }
  }

  static String? _nonEmpty(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
