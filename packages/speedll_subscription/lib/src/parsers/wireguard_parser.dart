import 'dart:convert';
import '../models/server_profile.dart';
import 'subscription_parser.dart';

/// Parses WireGuard configurations from:
/// 1. `wireguard://` or `wg://` single-line URIs
/// 2. Standard WireGuard `.conf` INI documents (`[Interface]` & `[Peer]`)
class WireguardParser implements SubscriptionParser {
  const WireguardParser();

  @override
  String get parserName => 'WireGuard';

  @override
  bool canParse(String content) {
    final trimmed = content.replaceAll('\uFEFF', '').trim();
    if (trimmed.isEmpty) return false;
    final lower = trimmed.toLowerCase();
    if (!lower.contains('\n') && !lower.contains('\r')) {
      return lower.startsWith('wireguard://') || lower.startsWith('wg://');
    }
    return RegExp(r'\[\s*interface\s*\]', caseSensitive: false)
            .hasMatch(trimmed) &&
        RegExp(r'\[\s*peer\s*\]', caseSensitive: false).hasMatch(trimmed);
  }

  @override
  Future<ParseResult> parse(String content) async {
    final trimmed = content.replaceAll('\uFEFF', '').trim();
    if (!canParse(trimmed)) {
      return ParseResult.failure('محتوای داده شده کانفیگ معتبر WireGuard نیست.');
    }

    final lower = trimmed.toLowerCase();
    if (!lower.contains('\n') &&
        !lower.contains('\r') &&
        (lower.startsWith('wireguard://') || lower.startsWith('wg://'))) {
      return _parseUri(trimmed);
    }
    return _parseIniConf(trimmed);
  }

  Future<ParseResult> _parseUri(String trimmed) async {
    try {
      final normalizedScheme = trimmed.toLowerCase().startsWith('wg://')
          ? 'wireguard://${trimmed.substring(5)}'
          : trimmed;

      final safeUri = SafeProxyUri.parse(normalizedScheme);
      final uri = safeUri.uri;
      final query = uri.queryParameters;

      final host = uri.host.trim();
      if (host.isEmpty) {
        return ParseResult.failure('آدرس سرور در لینک WireGuard یافت نشد.');
      }
      final port = uri.hasPort && uri.port > 0 ? uri.port : 51820;

      var privateKey = Uri.decodeComponent(uri.userInfo).trim();
      if (privateKey.isEmpty) {
        privateKey = _firstNonEmpty(query, const [
              'privatekey',
              'private_key',
              'privateKey',
              'secretkey',
              'secret_key',
            ]) ??
            '';
      }
      final publicKey = _firstNonEmpty(query, const [
            'publickey',
            'public_key',
            'publicKey',
            'peer_public_key',
            'peerPublicKey',
          ]) ??
          '';

      if (privateKey.isEmpty || publicKey.isEmpty) {
        return ParseResult.failure(
          'کلید خصوصی (PrivateKey) یا کلید عمومی سرور (PublicKey) در لینک WireGuard ناقص است.',
        );
      }

      final preSharedKey = _firstNonEmpty(query, const [
        'presharedkey',
        'pre_shared_key',
        'preshared_key',
        'preSharedKey',
        'psk',
      ]);

      final rawAddress = _firstNonEmpty(query, const [
            'address',
            'ip',
            'local_address',
            'localAddress',
          ]) ??
          '172.16.0.2/32';
      final addresses = normalizeAddressList(rawAddress);

      final mtu = int.tryParse(
            _firstNonEmpty(query, const ['mtu']) ?? '',
          ) ??
          1408;

      final reserved = parseReserved(
        _firstNonEmpty(query, const ['reserved']),
      );

      final displayName =
          safeUri.fragment.isNotEmpty ? safeUri.fragment : '$host:$port';

      final isInfoNode = SafeProxyUri.isInfoMetadataProfile(
        host: host,
        port: port,
        displayName: displayName,
      );

      final extra = <String, dynamic>{
        'privateKey': privateKey,
        'publicKey': publicKey,
        if (preSharedKey != null) 'preSharedKey': preSharedKey,
        'localAddress': addresses,
        'mtu': mtu,
        if (reserved != null) 'reserved': reserved,
        if (isInfoNode) 'isInfoNode': true,
      };

      final uniqueSuffix = SafeProxyUri.stableHash(trimmed);
      final profile = ServerProfile(
        id: 'wg_${host}_${port}_$uniqueSuffix',
        displayName: displayName,
        protocol: 'wireguard',
        source: ProfileSource.subscription,
        serverAddress: host,
        serverPort: port,
        extraParams: extra,
      );

      return ParseResult.success([profile]);
    } catch (e) {
      return ParseResult.failure('خطا در تحلیل لینک WireGuard: $e');
    }
  }

  Future<ParseResult> _parseIniConf(String content) async {
    try {
      String section = '';
      final interfaceMap = <String, String>{};
      final peerMap = <String, String>{};
      String? commentName;

      for (final rawLine in content.split(RegExp(r'[\r\n]+'))) {
        final line = rawLine.trim();
        if (line.isEmpty) continue;
        if (line.startsWith('#') || line.startsWith(';')) {
          final commentText = line.substring(1).trim();
          if (commentName == null &&
              commentText.isNotEmpty &&
              commentText.length <= 64) {
            commentName = commentText;
          }
          continue;
        }
        if (line.startsWith('[') && line.endsWith(']')) {
          section = line.substring(1, line.length - 1).trim().toLowerCase();
          continue;
        }
        final eqIndex = line.indexOf('=');
        if (eqIndex <= 0) continue;
        final key = line.substring(0, eqIndex).trim().toLowerCase();
        final value = line.substring(eqIndex + 1).trim();
        if (section == 'interface') {
          interfaceMap[key] = value;
        } else if (section == 'peer') {
          peerMap[key] = value;
        }
      }

      final privateKey = interfaceMap['privatekey'] ?? '';
      final publicKey = peerMap['publickey'] ?? '';
      final endpoint = peerMap['endpoint'] ?? '';

      if (privateKey.isEmpty || publicKey.isEmpty || endpoint.isEmpty) {
        return ParseResult.failure(
          'فیلدهای ضروری PrivateKey، PublicKey یا Endpoint در فایل WireGuard یافت نشد.',
        );
      }

      final parsedEndpoint = _parseEndpointHostPort(endpoint);
      if (parsedEndpoint == null) {
        return ParseResult.failure('مقدار Endpoint در فایل WireGuard نامعتبر است.');
      }

      final addresses = normalizeAddressList(
        interfaceMap['address'] ?? '172.16.0.2/32',
      );
      final preSharedKey =
          peerMap['presharedkey'] ?? peerMap['pre_shared_key'];
      final mtu = int.tryParse(interfaceMap['mtu'] ?? '') ?? 1408;
      final reserved = parseReserved(
        interfaceMap['reserved'] ?? peerMap['reserved'],
      );
      final displayName = commentName ??
          interfaceMap['name'] ??
          '${parsedEndpoint.host}:${parsedEndpoint.port}';

      final uniqueSuffix = SafeProxyUri.stableHash(content);
      final profile = ServerProfile(
        id: 'wg_${parsedEndpoint.host}_${parsedEndpoint.port}_$uniqueSuffix',
        displayName: displayName,
        protocol: 'wireguard',
        source: ProfileSource.manual,
        serverAddress: parsedEndpoint.host,
        serverPort: parsedEndpoint.port,
        extraParams: <String, dynamic>{
          'privateKey': privateKey,
          'publicKey': publicKey,
          if (preSharedKey != null && preSharedKey.isNotEmpty)
            'preSharedKey': preSharedKey,
          'localAddress': addresses,
          'mtu': mtu,
          if (reserved != null) 'reserved': reserved,
        },
      );

      return ParseResult.success([profile]);
    } catch (e) {
      return ParseResult.failure('خطا در تحلیل کانفیگ WireGuard: $e');
    }
  }

  static ({String host, int port})? _parseEndpointHostPort(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('[')) {
      final closeBracket = trimmed.indexOf(']');
      if (closeBracket <= 1) return null;
      final host = trimmed.substring(1, closeBracket);
      final rest = trimmed.substring(closeBracket + 1).trim();
      final port = rest.startsWith(':')
          ? (int.tryParse(rest.substring(1)) ?? 51820)
          : 51820;
      return (host: host, port: port);
    }
    final lastColon = trimmed.lastIndexOf(':');
    if (lastColon <= 0) {
      return (host: trimmed, port: 51820);
    }
    final host = trimmed.substring(0, lastColon).trim();
    final port = int.tryParse(trimmed.substring(lastColon + 1).trim()) ?? 51820;
    if (host.isEmpty || port <= 0 || port > 65535) return null;
    return (host: host, port: port);
  }

  static List<String> normalizeAddressList(dynamic raw) {
    final items = <String>[];
    if (raw is List) {
      for (final entry in raw) {
        items.addAll(entry.toString().split(','));
      }
    } else if (raw != null) {
      items.addAll(raw.toString().split(','));
    }

    final normalized = <String>[];
    for (final item in items) {
      final clean = item.trim();
      if (clean.isEmpty) continue;
      if (clean.contains('/')) {
        normalized.add(clean);
      } else if (clean.contains(':')) {
        normalized.add('$clean/128');
      } else {
        normalized.add('$clean/32');
      }
    }
    return normalized.isEmpty ? const <String>['172.16.0.2/32'] : normalized;
  }

  static List<int>? parseReserved(dynamic raw) {
    if (raw == null) return null;
    if (raw is List) {
      final ints = raw
          .map((e) => int.tryParse(e.toString().trim()))
          .whereType<int>()
          .where((v) => v >= 0 && v <= 255)
          .toList();
      return ints.length == 3 ? ints : null;
    }
    final text = raw.toString().trim();
    if (text.isEmpty) return null;
    if (text.contains(',')) {
      final ints = text
          .split(',')
          .map((e) => int.tryParse(e.trim()))
          .whereType<int>()
          .where((v) => v >= 0 && v <= 255)
          .toList();
      return ints.length == 3 ? ints : null;
    }
    try {
      var padded = text.replaceAll('-', '+').replaceAll('_', '/');
      while (padded.length % 4 != 0) {
        padded += '=';
      }
      final bytes = base64Decode(padded);
      if (bytes.length == 3) {
        return List<int>.from(bytes);
      }
    } catch (_) {}
    return null;
  }

  static String? _firstNonEmpty(Map<String, String> query, List<String> keys) {
    for (final key in keys) {
      final direct = query[key]?.trim();
      if (direct != null && direct.isNotEmpty) return direct;
      for (final entry in query.entries) {
        if (entry.key.toLowerCase() == key.toLowerCase()) {
          final val = entry.value.trim();
          if (val.isNotEmpty) return val;
        }
      }
    }
    return null;
  }
}
