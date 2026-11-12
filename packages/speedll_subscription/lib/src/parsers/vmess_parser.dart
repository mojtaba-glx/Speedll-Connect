import 'dart:convert';
import '../models/server_profile.dart';
import 'subscription_parser.dart';

class VmessParser implements SubscriptionParser {
  const VmessParser();

  @override
  String get parserName => 'VMess';

  @override
  bool canParse(String content) {
    final trimmed = content.replaceAll('\uFEFF', '').trim();
    return !trimmed.contains('\n') &&
        !trimmed.contains('\r') &&
        trimmed.toLowerCase().startsWith('vmess://');
  }

  @override
  Future<ParseResult> parse(String content) async {
    final trimmed = content.replaceAll('\uFEFF', '').trim();
    if (!canParse(trimmed)) {
      return ParseResult.failure('محتوای داده شده لینک معتبر VMess نیست.');
    }

    try {
      final hashIndex = trimmed.indexOf('#');
      final rawFragment = hashIndex >= 0
          ? SafeProxyUri.decodeFragmentSafely(trimmed.substring(hashIndex + 1))
          : '';
      final bodyPart = (hashIndex >= 0
              ? trimmed.substring(8, hashIndex)
              : trimmed.substring(8))
          .trim();

      // Support standard URI format: vmess://uuid@host:port?type=...&security=...#name
      if (bodyPart.contains('@')) {
        return _parseUriFormat(trimmed);
      }

      final base64Part = bodyPart;

      // Normalize base64 padding
      var normalized = base64Part
          .replaceAll('-', '+')
          .replaceAll('_', '/')
          .replaceAll(RegExp(r'\s+'), '');
      while (normalized.length % 4 != 0) {
        normalized += '=';
      }

      final decodedBytes = base64Decode(normalized);
      final jsonString = utf8.decode(decodedBytes, allowMalformed: true);
      final dynamic raw = jsonDecode(jsonString);

      if (raw is! Map<String, dynamic>) {
        return ParseResult.failure('ساختار داده JSON در VMess نامعتبر است.');
      }

      final host = (raw['add']?.toString() ?? '').trim();
      final rawPort = raw['port'];
      final port = rawPort is int
          ? rawPort
          : (rawPort is String ? int.tryParse(rawPort.trim()) ?? 443 : 443);
      final uuid = (raw['id']?.toString() ?? '').trim();
      final nameFromPs = (raw['ps']?.toString() ?? '').trim();
      final name = nameFromPs.isNotEmpty
          ? nameFromPs
          : (rawFragment.isNotEmpty ? rawFragment : '$host:$port');

      if (host.isEmpty || uuid.isEmpty) {
        return ParseResult.failure('آدرس سرور یا شناسه کاربری در لینک VMess خالی است.');
      }

      final rawAid = raw['aid'];
      final alterId = rawAid is int
          ? rawAid
          : (rawAid is String ? int.tryParse(rawAid.trim()) ?? 0 : 0);

      final isInfoNode = SafeProxyUri.isInfoMetadataProfile(
        host: host,
        port: port,
        displayName: name,
        uuid: uuid,
      );

      final rawNet = (_nonEmpty(raw['net']?.toString()) ?? 'tcp').toLowerCase();
      final transportType = rawNet == 'h2' ? 'http' : rawNet;
      final pathVal = _nonEmpty(raw['path']?.toString());
      final serviceName = _nonEmpty(raw['serviceName']?.toString()) ??
          (transportType == 'grpc' ? pathVal : null);
      final rawTls = _nonEmpty(raw['tls']?.toString())?.toLowerCase();
      final isTls = rawTls == 'tls' || rawTls == '1' || rawTls == 'true';
      final allowInsecure = raw['allowInsecure'] == true ||
          raw['allowInsecure'] == '1' ||
          raw['insecure'] == true ||
          raw['insecure'] == '1' ||
          raw['verify_cert'] == false;

      final extra = <String, dynamic>{
        ...raw,
        'uuid': uuid,
        'alterId': alterId,
        'security': _nonEmpty(raw['scy']?.toString()) ?? 'auto',
        'transportType': transportType,
        if (_nonEmpty(raw['type']?.toString()) != null)
          'headerType': _nonEmpty(raw['type']?.toString())!.toLowerCase(),
        'path': pathVal,
        if (serviceName != null) 'serviceName': serviceName,
        'host': _nonEmpty(raw['host']?.toString()) ??
            _nonEmpty(raw['authority']?.toString()),
        'tls': isTls ? 'tls' : _nonEmpty(raw['tls']?.toString()),
        'sni': _nonEmpty(raw['sni']?.toString()) ??
            _nonEmpty(raw['peer']?.toString()),
        if (_nonEmpty(raw['alpn']?.toString()) != null)
          'alpn': _nonEmpty(raw['alpn']?.toString()),
        if (_nonEmpty(raw['fp']?.toString()) != null)
          'fingerprint': _nonEmpty(raw['fp']?.toString()),
        if (allowInsecure) 'allowInsecure': true,
        if (isInfoNode) 'isInfoNode': true,
      };

      final uniqueSuffix = SafeProxyUri.stableHash(trimmed);
      final profile = ServerProfile(
        id: 'vmess_${host}_${port}_$uniqueSuffix',
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

  Future<ParseResult> _parseUriFormat(String trimmed) async {
    try {
      final safeUri = SafeProxyUri.parse(trimmed);
      final uri = safeUri.uri;
      final host = uri.host.trim();
      if (host.isEmpty) {
        return ParseResult.failure('آدرس سرور در لینک VMess نامعتبر است.');
      }
      final port = uri.hasPort && uri.port > 0 ? uri.port : 443;
      final query = uri.queryParameters;

      var uuid = Uri.decodeComponent(uri.userInfo).trim();
      var scy = _nonEmpty(query['scy']) ?? _nonEmpty(query['encryption']) ?? 'auto';
      if (uuid.contains(':')) {
        final parts = uuid.split(':');
        scy = parts.first.trim();
        uuid = parts.sublist(1).join(':').trim();
      }
      if (uuid.isEmpty) {
        return ParseResult.failure('شناسه UUID در لینک VMess یافت نشد.');
      }

      final rawType = (_nonEmpty(query['type']) ?? 'tcp').toLowerCase();
      final transportType = rawType == 'h2' ? 'http' : rawType;
      final secParam = _nonEmpty(query['security'])?.toLowerCase();
      final isTls = secParam == 'tls' ||
          query['tls'] == '1' ||
          query['tls']?.toLowerCase() == 'true' ||
          query['tls']?.toLowerCase() == 'tls';
      final allowInsecure = query['allowInsecure'] == '1' ||
          query['allowInsecure']?.toLowerCase() == 'true' ||
          query['insecure'] == '1' ||
          query['insecure']?.toLowerCase() == 'true';

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
        'alterId': int.tryParse(query['aid'] ?? query['alterId'] ?? '0') ?? 0,
        'security': scy,
        'scy': scy,
        'transportType': transportType,
        if (_nonEmpty(query['headerType']) != null)
          'headerType': _nonEmpty(query['headerType'])!.toLowerCase(),
        'path': _nonEmpty(query['path']),
        'serviceName':
            _nonEmpty(query['serviceName']) ?? _nonEmpty(query['service_name']),
        'host': _nonEmpty(query['host']) ?? _nonEmpty(query['authority']),
        'tls': isTls ? 'tls' : null,
        'sni': _nonEmpty(query['sni']) ?? _nonEmpty(query['peer']),
        if (_nonEmpty(query['alpn']) != null) 'alpn': _nonEmpty(query['alpn']),
        if (_nonEmpty(query['fp']) != null)
          'fingerprint': _nonEmpty(query['fp']),
        if (allowInsecure) 'allowInsecure': true,
        if (isInfoNode) 'isInfoNode': true,
      };

      final uniqueSuffix = SafeProxyUri.stableHash(trimmed);
      return ParseResult.success([
        ServerProfile(
          id: 'vmess_${host}_${port}_$uniqueSuffix',
          displayName: displayName,
          protocol: 'vmess',
          source: ProfileSource.subscription,
          serverAddress: host,
          serverPort: port,
          extraParams: extra,
        ),
      ]);
    } catch (e) {
      return ParseResult.failure('خطا در تحلیل لینک VMess: $e');
    }
  }

  static String? _nonEmpty(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
