import 'dart:convert';
import '../models/server_profile.dart';
import 'subscription_parser.dart';

class ShadowsocksParser implements SubscriptionParser {
  const ShadowsocksParser();

  @override
  String get parserName => 'Shadowsocks';

  @override
  bool canParse(String content) {
    return content.trim().toLowerCase().startsWith('ss://');
  }

  @override
  Future<ParseResult> parse(String content) async {
    final trimmed = content.trim();
    if (!canParse(trimmed)) {
      return ParseResult.failure('محتوای داده شده لینک معتبر Shadowsocks نیست.');
    }

    try {
      final uri = Uri.parse(trimmed);
      final rawUserInfo = uri.userInfo;
      var host = uri.host;
      var port = uri.hasPort ? uri.port : 8388;
      var displayName = uri.fragment.isNotEmpty
          ? Uri.decodeComponent(uri.fragment)
          : '$host:$port';

      String method = 'aes-256-gcm';
      String password = '';

      if (rawUserInfo.isNotEmpty) {
        // May be base64 encoded user info (SIP002 format)
        String decodedUserInfo;
        try {
          var padded = rawUserInfo.replaceAll('-', '+').replaceAll('_', '/');
          while (padded.length % 4 != 0) {
            padded += '=';
          }
          decodedUserInfo = utf8.decode(base64Decode(padded));
        } catch (_) {
          decodedUserInfo = rawUserInfo;
        }

        if (decodedUserInfo.contains(':')) {
          final parts = decodedUserInfo.split(':');
          method = parts[0];
          password = parts.sublist(1).join(':');
        } else {
          password = decodedUserInfo;
        }
      } else {
        // Old legacy format: ss://BASE64(method:password@host:port)#name
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
          return ParseResult.failure('ساختار لینک Shadowsocks قابل رمزگشایی نیست.');
        }
      }

      if (host.isEmpty) {
        return ParseResult.failure('آدرس سرور Shadowsocks یافت نشد.');
      }

      final extra = <String, dynamic>{
        'method': method,
        'password': password,
        'plugin': uri.queryParameters['plugin'],
      };

      final profile = ServerProfile(
        id: 'ss_${host}_${port}_${password.hashCode.abs()}',
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
