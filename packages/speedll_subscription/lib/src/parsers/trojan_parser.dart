import '../models/server_profile.dart';
import 'subscription_parser.dart';

class TrojanParser implements SubscriptionParser {
  const TrojanParser();

  @override
  String get parserName => 'Trojan';

  @override
  bool canParse(String content) {
    return content.trim().toLowerCase().startsWith('trojan://');
  }

  @override
  Future<ParseResult> parse(String content) async {
    final trimmed = content.trim();
    if (!canParse(trimmed)) {
      return ParseResult.failure('محتوای داده شده لینک معتبر Trojan نیست.');
    }

    try {
      final uri = Uri.parse(trimmed);
      final password = uri.userInfo;
      if (password.isEmpty) {
        return ParseResult.failure('رمز عبور در لینک Trojan یافت نشد.');
      }

      final host = uri.host;
      if (host.isEmpty) {
        return ParseResult.failure('آدرس سرور در لینک Trojan خالی است.');
      }

      final port = uri.hasPort ? uri.port : 443;
      final query = uri.queryParameters;
      final displayName = uri.fragment.isNotEmpty
          ? Uri.decodeComponent(uri.fragment)
          : '$host:$port';

      final extra = <String, dynamic>{
        'password': password,
        'security': query['security'] ?? 'tls',
        'sni': query['sni'],
        'transportType': (query['type'] ?? 'tcp').toLowerCase(),
        'serviceName': query['serviceName'],
        'path': query['path'],
        ...query,
      };

      final profile = ServerProfile(
        id: 'trojan_${host}_${port}_${password.hashCode.abs()}',
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
}
