import '../models/server_profile.dart';
import 'subscription_parser.dart';

class AnyTlsParser implements SubscriptionParser {
  const AnyTlsParser();

  @override
  String get parserName => 'AnyTLS';

  @override
  bool canParse(String content) {
    final lower = content.replaceAll('\uFEFF', '').trim().toLowerCase();
    return !lower.contains('\n') &&
        !lower.contains('\r') &&
        lower.startsWith('anytls://');
  }

  @override
  Future<ParseResult> parse(String content) async {
    final trimmed = content.replaceAll('\uFEFF', '').trim();
    if (!canParse(trimmed)) {
      return ParseResult.failure('محتوای داده شده لینک معتبر AnyTLS نیست.');
    }

    try {
      final safeUri = SafeProxyUri.parse(trimmed);
      final uri = safeUri.uri;
      final query = uri.queryParameters;

      var password = Uri.decodeComponent(uri.userInfo);
      if (password.isEmpty) {
        password = query['password'] ?? '';
      }

      final host = uri.host;
      if (host.isEmpty) {
        return ParseResult.failure('آدرس سرور در لینک AnyTLS نامعتبر است.');
      }
      if (password.isEmpty) {
        return ParseResult.failure('رمز عبور در لینک AnyTLS یافت نشد.');
      }

      final port = uri.hasPort && uri.port > 0 ? uri.port : 443;
      final displayName =
          safeUri.fragment.isNotEmpty ? safeUri.fragment : '$host:$port';

      final insecure = query['insecure'] == '1' ||
          query['insecure']?.toLowerCase() == 'true' ||
          query['allowInsecure'] == '1';

      final isInfoNode = SafeProxyUri.isInfoMetadataProfile(
        host: host,
        port: port,
        displayName: displayName,
      );

      final extra = <String, dynamic>{
        ...query,
        'password': password,
        'sni': query['sni'] ?? query['peer'],
        'insecure': insecure,
        if (isInfoNode) 'isInfoNode': true,
      };

      final uniqueSuffix = SafeProxyUri.stableHash(trimmed);
      final profile = ServerProfile(
        id: 'anytls_${host}_${port}_$uniqueSuffix',
        displayName: displayName,
        protocol: 'anytls',
        source: ProfileSource.subscription,
        serverAddress: host,
        serverPort: port,
        extraParams: extra,
      );

      return ParseResult.success([profile]);
    } catch (e) {
      return ParseResult.failure('خطا در تحلیل لینک AnyTLS: $e');
    }
  }
}
