import '../models/server_profile.dart';
import 'subscription_parser.dart';

class VlessParser implements SubscriptionParser {
  const VlessParser();

  @override
  String get parserName => 'VLESS';

  @override
  bool canParse(String content) {
    return content.trim().toLowerCase().startsWith('vless://');
  }

  @override
  Future<ParseResult> parse(String content) async {
    final trimmed = content.trim();
    if (!canParse(trimmed)) {
      return ParseResult.failure('محتوای داده شده لینک معتبر VLESS نیست.');
    }

    try {
      final uri = Uri.parse(trimmed);
      final uuid = uri.userInfo;
      if (uuid.isEmpty) {
        return ParseResult.failure('شناسه کاربری (UUID) در لینک VLESS یافت نشد.');
      }

      final host = uri.host;
      if (host.isEmpty) {
        return ParseResult.failure('آدرس سرور در لینک VLESS نامعتبر است.');
      }

      final port = uri.hasPort ? uri.port : 443;
      final query = uri.queryParameters;
      final warnings = <String>[];

      final security = query['security']?.toLowerCase() ?? 'none';
      final transportType = (query['type'] ?? 'tcp').toLowerCase();
      final flow = query['flow'];
      final sni = query['sni'];
      final pbk = query['pbk'];
      final sid = query['sid'];
      final fp = query['fp'] ?? 'chrome';
      final serviceName = query['serviceName'];
      final path = query['path'];
      final hostHeader = query['host'];

      if (security == 'reality' && (pbk == null || pbk.isEmpty)) {
        warnings.add('در کانفیگ Reality، کلید عمومی (pbk) یافت نشد.');
      }

      // Profile Display Name: fragment or fallback
      var displayName = uri.fragment.isNotEmpty
          ? Uri.decodeComponent(uri.fragment)
          : '$host:$port';

      final extra = <String, dynamic>{
        'uuid': uuid,
        'security': security,
        'transportType': transportType,
        'flow': flow,
        'sni': sni,
        'pbk': pbk,
        'sid': sid,
        'fingerprint': fp,
        if (serviceName != null) 'serviceName': serviceName,
        if (path != null) 'path': path,
        if (hostHeader != null) 'host': hostHeader,
        ...query,
      };

      final profile = ServerProfile(
        id: 'vless_${host}_${port}_${uuid.substring(0, uuid.length > 8 ? 8 : uuid.length)}',
        displayName: displayName,
        protocol: 'vless',
        source: ProfileSource.subscription,
        serverAddress: host,
        serverPort: port,
        extraParams: extra,
      );

      return ParseResult.success([profile], warnings: warnings);
    } catch (e) {
      return ParseResult.failure('خطا در تحلیل لینک VLESS: $e');
    }
  }
}
