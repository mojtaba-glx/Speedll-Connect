import 'dart:convert';
import '../models/server_profile.dart';
import 'subscription_parser.dart';

class VmessParser implements SubscriptionParser {
  const VmessParser();

  @override
  String get parserName => 'VMess';

  @override
  bool canParse(String content) {
    return content.trim().toLowerCase().startsWith('vmess://');
  }

  @override
  Future<ParseResult> parse(String content) async {
    final trimmed = content.trim();
    if (!canParse(trimmed)) {
      return ParseResult.failure('محتوای داده شده لینک معتبر VMess نیست.');
    }

    try {
      final base64Part = trimmed.substring(8);
      // Normalize base64 padding
      var normalized = base64Part.replaceAll('-', '+').replaceAll('_', '/');
      while (normalized.length % 4 != 0) {
        normalized += '=';
      }

      final decodedBytes = base64Decode(normalized);
      final jsonString = utf8.decode(decodedBytes);
      final dynamic raw = jsonDecode(jsonString);

      if (raw is! Map<String, dynamic>) {
        return ParseResult.failure('ساختار داده JSON در VMess نامعتبر است.');
      }

      final host = raw['add'] as String? ?? '';
      final rawPort = raw['port'];
      final port = rawPort is int
          ? rawPort
          : (rawPort is String ? int.tryParse(rawPort) ?? 443 : 443);
      final uuid = raw['id'] as String? ?? '';
      final name = raw['ps'] as String? ?? '$host:$port';

      if (host.isEmpty || uuid.isEmpty) {
        return ParseResult.failure('آدرس سرور یا شناسه کاربری در لینک VMess خالی است.');
      }

      final extra = <String, dynamic>{
        'uuid': uuid,
        'alterId': raw['aid'] ?? 0,
        'security': raw['scy'] ?? 'auto',
        'transportType': raw['net'] ?? 'tcp',
        'path': raw['path'],
        'host': raw['host'],
        'tls': raw['tls'],
        'sni': raw['sni'],
        ...raw,
      };

      final profile = ServerProfile(
        id: 'vmess_${host}_${port}_${uuid.substring(0, uuid.length > 8 ? 8 : uuid.length)}',
        displayName: name,
        protocol: 'vmess',
        source: ProfileSource.subscription,
        serverAddress: host,
        serverPort: port,
        extraParams: extra,
      );

      return ParseResult.success([profile]);
    } catch (e) {
      return ParseResult.failure('خطا در تحلیل لینک VMess: $e');
    }
  }
}
