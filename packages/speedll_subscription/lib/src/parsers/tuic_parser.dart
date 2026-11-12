import '../models/server_profile.dart';
import 'subscription_parser.dart';

class TuicParser implements SubscriptionParser {
  const TuicParser();

  @override
  String get parserName => 'TUIC';

  @override
  bool canParse(String content) {
    final lower = content.replaceAll('\uFEFF', '').trim().toLowerCase();
    return !lower.contains('\n') &&
        !lower.contains('\r') &&
        lower.startsWith('tuic://');
  }

  @override
  Future<ParseResult> parse(String content) async {
    final trimmed = content.replaceAll('\uFEFF', '').trim();
    if (!canParse(trimmed)) {
      return ParseResult.failure('محتوای داده شده لینک معتبر TUIC نیست.');
    }

    try {
      final safeUri = SafeProxyUri.parse(trimmed);
      final uri = safeUri.uri;
      final query = uri.queryParameters;

      var uuid = '';
      var password = '';
      final rawUserInfo = uri.userInfo;
      if (rawUserInfo.isNotEmpty) {
        final separator = rawUserInfo.indexOf(':');
        if (separator >= 0) {
          uuid = Uri.decodeComponent(rawUserInfo.substring(0, separator));
          password = Uri.decodeComponent(
            rawUserInfo.substring(separator + 1),
          );
        } else {
          final decodedUser = Uri.decodeComponent(rawUserInfo);
          final decodedSep = decodedUser.indexOf(':');
          if (decodedSep >= 0) {
            uuid = decodedUser.substring(0, decodedSep);
            password = decodedUser.substring(decodedSep + 1);
          } else {
            uuid = decodedUser;
          }
        }
      }
      if (uuid.isEmpty) {
        uuid = query['uuid'] ?? '';
      }
      if (password.isEmpty) {
        password = query['password'] ?? '';
      }

      final host = uri.host;
      if (host.isEmpty) {
        return ParseResult.failure('آدرس سرور در لینک TUIC نامعتبر است.');
      }
      if (uuid.isEmpty) {
        return ParseResult.failure('شناسه UUID در لینک TUIC یافت نشد.');
      }

      final port = uri.hasPort && uri.port > 0 ? uri.port : 443;
      final displayName =
          safeUri.fragment.isNotEmpty ? safeUri.fragment : '$host:$port';

      final insecure = query['insecure'] == '1' ||
          query['insecure']?.toLowerCase() == 'true' ||
          query['allow_insecure'] == '1' ||
          query['allowInsecure'] == '1';

      final isInfoNode = SafeProxyUri.isInfoMetadataProfile(
        host: host,
        port: port,
        displayName: displayName,
        uuid: uuid,
      );

      final extra = <String, dynamic>{
        ...query,
        'uuid': uuid,
        'password': password,
        'sni': query['sni'] ?? query['peer'],
        'alpn': query['alpn'] ?? 'h3',
        'congestionControl':
            query['congestion_control'] ?? query['congestionControl'],
        'udpRelayMode': query['udp_relay_mode'] ?? query['udpRelayMode'],
        'udpOverStream': query['udp_over_stream'] == '1' ||
            query['udp_over_stream']?.toLowerCase() == 'true',
        'zeroRttHandshake': query['zero_rtt_handshake'] == '1' ||
            query['zero_rtt_handshake']?.toLowerCase() == 'true',
        'insecure': insecure,
        if (isInfoNode) 'isInfoNode': true,
      };

      final uniqueSuffix = SafeProxyUri.stableHash(trimmed);
      final profile = ServerProfile(
        id: 'tuic_${host}_${port}_$uniqueSuffix',
        displayName: displayName,
        protocol: 'tuic',
        source: ProfileSource.subscription,
        serverAddress: host,
        serverPort: port,
        extraParams: extra,
      );

      return ParseResult.success([profile]);
    } catch (e) {
      return ParseResult.failure('خطا در تحلیل لینک TUIC: $e');
    }
  }
}
