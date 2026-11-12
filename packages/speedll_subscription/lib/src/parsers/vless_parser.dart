import '../models/server_profile.dart';
import 'subscription_parser.dart';

class VlessParser implements SubscriptionParser {
  const VlessParser();

  @override
  String get parserName => 'VLESS';

  @override
  bool canParse(String content) {
    final trimmed = content.replaceAll('\uFEFF', '').trim();
    return !trimmed.contains('\n') &&
        !trimmed.contains('\r') &&
        trimmed.toLowerCase().startsWith('vless://');
  }

  @override
  Future<ParseResult> parse(String content) async {
    final trimmed = content.replaceAll('\uFEFF', '').trim();
    if (!canParse(trimmed)) {
      return ParseResult.failure('محتوای داده شده لینک معتبر VLESS نیست.');
    }

    try {
      final safeUri = SafeProxyUri.parse(trimmed);
      final uri = safeUri.uri;
      final uuid = Uri.decodeComponent(uri.userInfo);
      if (uuid.isEmpty) {
        return ParseResult.failure('شناسه کاربری (UUID) در لینک VLESS یافت نشد.');
      }

      final host = uri.host;
      if (host.isEmpty) {
        return ParseResult.failure('آدرس سرور در لینک VLESS نامعتبر است.');
      }

      final port = uri.hasPort && uri.port > 0 ? uri.port : 443;
      final query = uri.queryParameters;
      final warnings = <String>[];

      final rawSecurity = _nonEmpty(query['security'])?.toLowerCase();
      final pbk = _nonEmpty(query['pbk']);
      final hasTlsFlag = query['tls'] == '1' ||
          query['tls']?.toLowerCase() == 'true' ||
          query['tls']?.toLowerCase() == 'tls';
      final security = rawSecurity ??
          ((pbk != null && pbk.isNotEmpty)
              ? 'reality'
              : (hasTlsFlag ? 'tls' : 'none'));
      final rawType = _nonEmpty(query['type'])?.toLowerCase() ?? 'tcp';
      final transportType = rawType == 'h2' ? 'http' : rawType;
      final headerType = query['headerType']?.trim().toLowerCase();
      final flow = _nonEmpty(query['flow']);
      final sni = _nonEmpty(query['sni']) ?? _nonEmpty(query['peer']);
      final sid = _nonEmpty(query['sid']);
      final fp = _nonEmpty(query['fp']) ?? 'chrome';
      final serviceName =
          _nonEmpty(query['serviceName']) ?? _nonEmpty(query['service_name']);
      final path = _nonEmpty(query['path']);
      final hostHeader =
          _nonEmpty(query['host']) ?? _nonEmpty(query['authority']);
      final alpn = _nonEmpty(query['alpn']);
      final packetEncoding = _nonEmpty(query['packetEncoding']) ??
          _nonEmpty(query['packet_encoding']);
      final allowInsecure = query['allowInsecure'] == '1' ||
          query['allowInsecure']?.toLowerCase() == 'true' ||
          query['insecure'] == '1' ||
          query['insecure']?.toLowerCase() == 'true';

      if (security == 'reality' && (pbk == null || pbk.isEmpty)) {
        warnings.add('در کانفیگ Reality، کلید عمومی (pbk) یافت نشد.');
      }

      final displayName =
          safeUri.fragment.isNotEmpty ? safeUri.fragment : '$host:$port';

      final isInfoNode = SafeProxyUri.isInfoMetadataProfile(
        host: host,
        port: port,
        displayName: displayName,
        uuid: uuid,
      );

      final extra = <String, dynamic>{
        ...query,
        'uuid': uuid,
        'security': security,
        'transportType': transportType,
        if (headerType != null && headerType.isNotEmpty)
          'headerType': headerType,
        'flow': flow,
        'sni': sni,
        'pbk': pbk,
        'sid': sid,
        'fingerprint': fp,
        if (serviceName != null) 'serviceName': serviceName,
        if (path != null) 'path': path,
        if (hostHeader != null) 'host': hostHeader,
        if (alpn != null) 'alpn': alpn,
        if (packetEncoding != null) 'packetEncoding': packetEncoding,
        if (allowInsecure) 'allowInsecure': true,
        if (isInfoNode) 'isInfoNode': true,
      };

      final uniqueSuffix = SafeProxyUri.stableHash(trimmed);
      final profile = ServerProfile(
        id: 'vless_${host}_${port}_$uniqueSuffix',
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

  static String? _nonEmpty(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
