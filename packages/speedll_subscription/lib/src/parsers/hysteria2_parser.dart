import '../models/server_profile.dart';
import 'subscription_parser.dart';

class Hysteria2Parser implements SubscriptionParser {
  const Hysteria2Parser();

  @override
  String get parserName => 'Hysteria2';

  @override
  bool canParse(String content) {
    final lower = content.replaceAll('\uFEFF', '').trim().toLowerCase();
    return !lower.contains('\n') &&
        !lower.contains('\r') &&
        (lower.startsWith('hysteria2://') || lower.startsWith('hy2://'));
  }

  @override
  Future<ParseResult> parse(String content) async {
    final trimmed = content.replaceAll('\uFEFF', '').trim();
    if (!canParse(trimmed)) {
      return ParseResult.failure('محتوای داده شده لینک معتبر Hysteria2 نیست.');
    }

    try {
      final normalizedScheme = trimmed.toLowerCase().startsWith('hy2://')
          ? 'hysteria2://${trimmed.substring(6)}'
          : trimmed;

      final safeUri = SafeProxyUri.parse(normalizedScheme);
      final uri = safeUri.uri;
      final auth = Uri.decodeComponent(uri.userInfo);
      final host = uri.host;
      if (host.isEmpty) {
        return ParseResult.failure('آدرس سرور در لینک Hysteria2 نامعتبر است.');
      }

      final port = uri.hasPort && uri.port > 0 ? uri.port : 443;
      final query = uri.queryParameters;
      final displayName =
          safeUri.fragment.isNotEmpty ? safeUri.fragment : '$host:$port';

      final resolvedAuth = auth.isNotEmpty
          ? auth
          : (query['auth'] ?? query['password'] ?? '');
      final sni = query['sni'] ?? query['peer'];
      final insecure = query['insecure'] == '1' ||
          query['insecure']?.toLowerCase() == 'true' ||
          query['allowInsecure'] == '1' ||
          query['allowInsecure']?.toLowerCase() == 'true';
      final mport = query['mport'];
      final obfs = query['obfs'];
      final obfsPassword = query['obfs-password'] ?? query['obfsPassword'];
      final alpn = query['alpn'];
      final upMbps = int.tryParse(
        query['upmbps'] ?? query['up_mbps'] ?? query['up'] ?? '',
      );
      final downMbps = int.tryParse(
        query['downmbps'] ?? query['down_mbps'] ?? query['down'] ?? '',
      );

      final isInfoNode = SafeProxyUri.isInfoMetadataProfile(
        host: host,
        port: port,
        displayName: displayName,
      );

      final extra = <String, dynamic>{
        ...query,
        'auth': resolvedAuth,
        'sni': sni,
        'insecure': insecure,
        if (mport != null) 'mport': mport,
        if (obfs != null) 'obfs': obfs,
        if (obfsPassword != null) 'obfsPassword': obfsPassword,
        if (alpn != null && alpn.trim().isNotEmpty) 'alpn': alpn.trim(),
        if (upMbps != null && upMbps > 0) 'upMbps': upMbps,
        if (downMbps != null && downMbps > 0) 'downMbps': downMbps,
        if (isInfoNode) 'isInfoNode': true,
      };

      final uniqueSuffix = SafeProxyUri.stableHash(trimmed);
      final profile = ServerProfile(
        id: 'hy2_${host}_${port}_$uniqueSuffix',
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
