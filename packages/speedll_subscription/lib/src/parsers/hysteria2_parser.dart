import '../models/server_profile.dart';
import 'subscription_parser.dart';

class Hysteria2Parser implements SubscriptionParser {
  const Hysteria2Parser();

  @override
  String get parserName => 'Hysteria2';

  @override
  bool canParse(String content) {
    final lower = content.trim().toLowerCase();
    return lower.startsWith('hysteria2://') || lower.startsWith('hy2://');
  }

  @override
  Future<ParseResult> parse(String content) async {
    final trimmed = content.trim();
    if (!canParse(trimmed)) {
      return ParseResult.failure('محتوای داده شده لینک معتبر Hysteria2 نیست.');
    }

    try {
      // Normalize hy2:// to hysteria2://
      final normalizedScheme = trimmed.startsWith('hy2://')
          ? 'hysteria2://${trimmed.substring(6)}'
          : trimmed;

      final uri = Uri.parse(normalizedScheme);
      final auth = uri.userInfo;
      final host = uri.host;
      if (host.isEmpty) {
        return ParseResult.failure('آدرس سرور در لینک Hysteria2 نامعتبر است.');
      }

      final port = uri.hasPort ? uri.port : 443;
      final query = uri.queryParameters;
      final displayName = uri.fragment.isNotEmpty
          ? Uri.decodeComponent(uri.fragment)
          : '$host:$port';

      final sni = query['sni'];
      final insecure = query['insecure'] == '1';
      final mport = query['mport'];
      final obfs = query['obfs'];
      final obfsPassword = query['obfs-password'];

      final extra = <String, dynamic>{
        'auth': auth,
        'sni': sni,
        'insecure': insecure,
        if (mport != null) 'mport': mport,
        if (obfs != null) 'obfs': obfs,
        if (obfsPassword != null) 'obfsPassword': obfsPassword,
        ...query,
      };

      final profile = ServerProfile(
        id: 'hy2_${host}_${port}_${auth.hashCode.abs()}',
        displayName: displayName,
        protocol: 'hysteria2',
        source: ProfileSource.subscription,
        serverAddress: host,
        serverPort: port,
        extraParams: extra,
      );

      return ParseResult.success([profile]);
    } catch (e) {
      return ParseResult.failure('خطا در تحلیل لینک Hysteria2: $e');
    }
  }
}
