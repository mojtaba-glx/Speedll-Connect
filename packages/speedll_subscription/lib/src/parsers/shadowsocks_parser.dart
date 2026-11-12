import 'dart:convert';
import '../models/server_profile.dart';
import 'subscription_parser.dart';

class ShadowsocksParser implements SubscriptionParser {
  const ShadowsocksParser();

  @override
  String get parserName => 'Shadowsocks';

  @override
  bool canParse(String content) {
    final trimmed = content.replaceAll('\uFEFF', '').trim();
    return !trimmed.contains('\n') &&
        !trimmed.contains('\r') &&
        trimmed.toLowerCase().startsWith('ss://');
  }

  @override
  Future<ParseResult> parse(String content) async {
    final trimmed = content.replaceAll('\uFEFF', '').trim();
    if (!canParse(trimmed)) {
      return ParseResult.failure('محتوای داده شده لینک معتبر Shadowsocks نیست.');
    }

    try {
      final safeUri = SafeProxyUri.parse(trimmed);
      final uri = safeUri.uri;
      final rawUserInfo = uri.userInfo;
      var host = uri.host;
      var port = uri.hasPort && uri.port > 0 ? uri.port : 8388;

      String method = 'aes-256-gcm';
      String password = '';

      if (rawUserInfo.isNotEmpty) {
        final percentDecoded = Uri.decodeComponent(rawUserInfo);
        String decodedUserInfo;
        if (percentDecoded.contains(':')) {
          decodedUserInfo = percentDecoded;
        } else {
          try {
            var padded = percentDecoded.replaceAll('-', '+').replaceAll('_', '/');
            while (padded.length % 4 != 0) {
              padded += '=';
            }
            decodedUserInfo = utf8.decode(base64Decode(padded));
          } catch (_) {
            decodedUserInfo = percentDecoded;
          }
        }

        if (decodedUserInfo.contains(':')) {
          final parts = decodedUserInfo.split(':');
          method = parts[0];
          password = parts.sublist(1).join(':');
        } else {
          password = decodedUserInfo;
        }
      } else {
        // Legacy format: ss://BASE64(method:password@host:port)#name
        final rawBody = trimmed.substring(5).split('#').first;
        try {
          var padded = rawBody.replaceAll('-', '+').replaceAll('_', '/');
          while (padded.length % 4 != 0) {
            padded += '=';
          }
          final decoded = utf8.decode(base64Decode(padded));
          final atIndex = decoded.lastIndexOf('@');
          if (atIndex != -1) {
            final authPart = decoded.substring(0, atIndex);
            final hostPart = decoded.substring(atIndex + 1);
            final authSplit = authPart.split(':');
            method = authSplit[0];
            password = authSplit.sublist(1).join(':');

            final hostSplit = hostPart.split(':');
            host = hostSplit[0];
            if (hostSplit.length > 1) {
              port = int.tryParse(hostSplit[1]) ?? port;
            }
          }
        } catch (_) {
          return ParseResult.failure(
            'ساختار لینک Shadowsocks قابل رمزگشایی نیست.',
          );
        }
      }

      if (host.isEmpty) {
        return ParseResult.failure('آدرس سرور Shadowsocks یافت نشد.');
      }

      final displayName =
          safeUri.fragment.isNotEmpty ? safeUri.fragment : '$host:$port';

      final isInfoNode = SafeProxyUri.isInfoMetadataProfile(
        host: host,
        port: port,
        displayName: displayName,
      );

      final uot = uri.queryParameters['uot'] == '1' ||
          uri.queryParameters['uot']?.toLowerCase() == 'true' ||
          uri.queryParameters['udp_over_tcp'] == '1' ||
          uri.queryParameters['udp_over_tcp']?.toLowerCase() == 'true';

      final extra = <String, dynamic>{
        'method': method,
        'password': password,
        'plugin': uri.queryParameters['plugin'],
        if (uri.queryParameters['plugin-opts'] != null)
          'pluginOpts': uri.queryParameters['plugin-opts'],
        if (uot) 'udpOverTcp': true,
        if (isInfoNode) 'isInfoNode': true,
      };

      final uniqueSuffix = SafeProxyUri.stableHash(trimmed);
      final profile = ServerProfile(
        id: 'ss_${host}_${port}_$uniqueSuffix',
        displayName: displayName,
        protocol: 'shadowsocks',
        source: ProfileSource.subscription,
        serverAddress: host,
        serverPort: port,
        extraParams: extra,
      );

      return ParseResult.success([profile]);
    } catch (e) {
      return ParseResult.failure('خطا در تحلیل لینک Shadowsocks: $e');
    }
  }
}
