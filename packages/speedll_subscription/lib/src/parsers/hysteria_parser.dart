import '../models/server_profile.dart';
import 'subscription_parser.dart';

class HysteriaParser implements SubscriptionParser {
  const HysteriaParser();

  @override
  String get parserName => 'Hysteria';

  @override
  bool canParse(String content) {
    final lower = content.replaceAll('\uFEFF', '').trim().toLowerCase();
    return !lower.contains('\n') &&
        !lower.contains('\r') &&
        lower.startsWith('hysteria://');
  }

  @override
  Future<ParseResult> parse(String content) async {
    final trimmed = content.replaceAll('\uFEFF', '').trim();
    if (!canParse(trimmed)) {
      return ParseResult.failure('محتوای داده شده لینک معتبر Hysteria نیست.');
    }

    try {
      final safeUri = SafeProxyUri.parse(trimmed);
      final uri = safeUri.uri;
      final query = uri.queryParameters;

      var auth = Uri.decodeComponent(uri.userInfo);
      if (auth.isEmpty) {
        auth = query['auth'] ?? query['auth_str'] ?? '';
      }

      final host = uri.host;
      if (host.isEmpty) {
        return ParseResult.failure('آدرس سرور در لینک Hysteria نامعتبر است.');
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
        'auth': auth,
        'sni': query['peer'] ?? query['sni'],
        'alpn': query['alpn'],
        'upMbps': query['upmbps'] ?? query['up'],
        'downMbps': query['downmbps'] ?? query['down'],
        'obfs': query['obfs'],
        'obfsPassword': query['obfsParam'] ?? query['obfs-password'],
        'insecure': insecure,
        if (isInfoNode) 'isInfoNode': true,
      };

      final uniqueSuffix = SafeProxyUri.stableHash(trimmed);
      final profile = ServerProfile(
        id: 'hysteria_${host}_${port}_$uniqueSuffix',
        displayName: displayName,
        protocol: 'hysteria',
        source: ProfileSource.subscription,
        serverAddress: host,
        serverPort: port,
        extraParams: extra,
      );

      return ParseResult.success([profile]);
    } catch (e) {
      return ParseResult.failure('خطا در تحلیل لینک Hysteria: $e');
    }
  }
}
