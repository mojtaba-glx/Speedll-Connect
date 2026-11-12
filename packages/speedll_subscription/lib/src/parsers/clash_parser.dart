import 'package:yaml/yaml.dart';
import '../models/server_profile.dart';
import 'subscription_parser.dart';
import 'wireguard_parser.dart';

/// Parses Clash / Clash Meta / Mihomo YAML subscription documents and converts
/// every supported `proxies` entry into a normalized [ServerProfile].
class ClashYamlParser implements SubscriptionParser {
  const ClashYamlParser();

  @override
  String get parserName => 'Clash YAML';

  @override
  bool canParse(String content) {
    final trimmed = content.replaceAll('\uFEFF', '').trim();
    if (trimmed.isEmpty || trimmed.startsWith('{')) return false;
    return RegExp(r'^\s*proxies\s*:', multiLine: true).hasMatch(trimmed);
  }

  @override
  Future<ParseResult> parse(String content) async {
    try {
      final document = loadYaml(content.replaceAll('\uFEFF', ''));
      if (document is! Map) {
        return ParseResult.failure('ساختار YAML اشتراک Clash نامعتبر است.');
      }
      final proxies = document['proxies'];
      if (proxies is! List) {
        return ParseResult.failure('فهرست proxies در فایل Clash یافت نشد.');
      }

      final profiles = <ServerProfile>[];
      final warnings = <String>[];
      for (final entry in proxies) {
        if (entry is! Map) continue;
        final map = <String, dynamic>{
          for (final item in entry.entries)
            item.key.toString(): item.value,
        };
        final profile = _profileFromProxy(map);
        if (profile != null) {
          profiles.add(profile);
        } else {
          final type = _string(map['type']) ?? 'unknown';
          warnings.add('پروکسی Clash از نوع $type پشتیبانی نمی‌شود.');
        }
      }

      if (profiles.isEmpty) {
        return ParseResult(
          isSuccess: false,
          errorMessage: 'هیچ پروکسی پشتیبانی‌شده‌ای در فایل Clash یافت نشد.',
          warnings: warnings,
        );
      }
      return ParseResult.success(profiles, warnings: warnings);
    } catch (e) {
      return ParseResult.failure('خطا در تحلیل فایل YAML اشتراک Clash: $e');
    }
  }

  ServerProfile? _profileFromProxy(Map<String, dynamic> proxy) {
    final type = (_string(proxy['type']) ?? '').toLowerCase();
    final server = _string(proxy['server']);
    final port = _integer(proxy['port']);
    if (server == null || port == null || port <= 0) return null;

    final name = _string(proxy['name']) ?? '$server:$port';
    final extra = <String, dynamic>{};
    final String protocol;

    switch (type) {
      case 'vless':
        protocol = 'vless';
        extra['uuid'] = _string(proxy['uuid']) ?? '';
        final reality = _map(proxy['reality-opts']);
        final hasReality = reality.isNotEmpty;
        extra['security'] = hasReality
            ? 'reality'
            : (_boolean(proxy['tls']) ? 'tls' : 'none');
        extra['sni'] =
            _string(proxy['servername']) ?? _string(proxy['sni']);
        extra['fingerprint'] = _string(proxy['client-fingerprint']);
        extra['flow'] = _string(proxy['flow']);
        extra['pbk'] = _string(reality['public-key']);
        extra['sid'] = _string(reality['short-id']);
        extra['alpn'] = _alpn(proxy['alpn']);
        _applyTransport(proxy, extra);
        break;
      case 'vmess':
        protocol = 'vmess';
        extra['uuid'] = _string(proxy['uuid']) ?? '';
        extra['alterId'] = _integer(proxy['alterId']) ?? 0;
        extra['scy'] = _string(proxy['cipher']) ?? 'auto';
        extra['tls'] = _boolean(proxy['tls']) ? 'tls' : '';
        extra['sni'] = _string(proxy['servername']) ?? _string(proxy['sni']);
        extra['fingerprint'] = _string(proxy['client-fingerprint']);
        extra['insecure'] = _boolean(proxy['skip-cert-verify']);
        extra['alpn'] = _alpn(proxy['alpn']);
        _applyTransport(proxy, extra);
        break;
      case 'trojan':
        protocol = 'trojan';
        extra['password'] = _string(proxy['password']) ?? '';
        final trojanReality = _map(proxy['reality-opts']);
        final hasTrojanReality = trojanReality.isNotEmpty;
        extra['security'] = hasTrojanReality
            ? 'reality'
            : (_boolean(proxy['tls'], fallback: true) ? 'tls' : 'none');
        extra['sni'] = _string(proxy['sni']) ?? _string(proxy['servername']);
        extra['fingerprint'] = _string(proxy['client-fingerprint']);
        extra['pbk'] = _string(trojanReality['public-key']);
        extra['sid'] = _string(trojanReality['short-id']);
        extra['alpn'] = _alpn(proxy['alpn']);
        extra['insecure'] = _boolean(proxy['skip-cert-verify']);
        _applyTransport(proxy, extra);
        break;
      case 'ss':
        protocol = 'shadowsocks';
        extra['method'] = _string(proxy['cipher']) ?? 'aes-256-gcm';
        extra['password'] = _string(proxy['password']) ?? '';
        final plugin = _string(proxy['plugin']);
        if (plugin != null) {
          final pluginOptions = _map(proxy['plugin-opts']);
          final parts = <String>[
            plugin,
            for (final item in pluginOptions.entries)
              '${item.key}=${item.value}',
          ];
          extra['plugin'] = parts.join(';');
        }
        break;
      case 'hysteria2' || 'hy2':
        protocol = 'hysteria2';
        extra['auth'] =
            _string(proxy['password']) ?? _string(proxy['auth']) ?? '';
        extra['sni'] = _string(proxy['sni']) ?? _string(proxy['servername']);
        extra['insecure'] = _boolean(proxy['skip-cert-verify']);
        extra['obfs'] = _string(proxy['obfs']);
        extra['obfsPassword'] = _string(proxy['obfs-password']);
        extra['alpn'] = _alpn(proxy['alpn']);
        break;
      case 'hysteria':
        protocol = 'hysteria';
        extra['auth'] =
            _string(proxy['auth-str']) ?? _string(proxy['auth']) ?? '';
        extra['sni'] = _string(proxy['sni']) ?? _string(proxy['peer']);
        extra['upMbps'] = _integer(proxy['up']);
        extra['downMbps'] = _integer(proxy['down']);
        extra['obfs'] = _string(proxy['obfs']);
        extra['insecure'] = _boolean(proxy['skip-cert-verify']);
        extra['alpn'] = _alpn(proxy['alpn']);
        break;
      case 'tuic':
        protocol = 'tuic';
        extra['uuid'] = _string(proxy['uuid']) ?? '';
        extra['password'] = _string(proxy['password']) ?? '';
        extra['congestionControl'] =
            _string(proxy['congestion-controller']);
        extra['udpRelayMode'] = _string(proxy['udp-relay-mode']);
        extra['sni'] = _string(proxy['sni']) ?? _string(proxy['servername']);
        extra['alpn'] = _alpn(proxy['alpn']) ?? 'h3';
        extra['insecure'] = _boolean(proxy['skip-cert-verify']);
        break;
      case 'anytls':
        protocol = 'anytls';
        extra['password'] = _string(proxy['password']) ?? '';
        extra['sni'] = _string(proxy['sni']) ?? _string(proxy['servername']);
        extra['insecure'] = _boolean(proxy['skip-cert-verify']);
        extra['alpn'] = _alpn(proxy['alpn']);
        break;
      case 'wireguard':
        protocol = 'wireguard';
        final privKey = _string(proxy['private-key']) ?? '';
        var pubKey = _string(proxy['public-key']) ?? '';
        var psk =
            _string(proxy['preshared-key']) ?? _string(proxy['pre-shared-key']);
        var reserved = WireguardParser.parseReserved(proxy['reserved']);
        if (pubKey.isEmpty && proxy['peers'] is List && (proxy['peers'] as List).isNotEmpty) {
          final firstPeer = _map((proxy['peers'] as List).first);
          pubKey = _string(firstPeer['public-key']) ?? '';
          psk ??= _string(firstPeer['preshared-key']) ??
              _string(firstPeer['pre-shared-key']);
          reserved ??= WireguardParser.parseReserved(firstPeer['reserved']);
        }
        if (privKey.isEmpty || pubKey.isEmpty) return null;
        final rawIps = <String>[
          if (_string(proxy['ip']) != null) _string(proxy['ip'])!,
          if (_string(proxy['ipv6']) != null) _string(proxy['ipv6'])!,
        ];
        extra['privateKey'] = privKey;
        extra['publicKey'] = pubKey;
        if (psk != null) extra['preSharedKey'] = psk;
        extra['localAddress'] = WireguardParser.normalizeAddressList(
          rawIps.isEmpty ? '172.16.0.2/32' : rawIps,
        );
        extra['mtu'] = _integer(proxy['mtu']) ?? 1408;
        if (reserved != null) extra['reserved'] = reserved;
        break;
      default:
        return null;
    }

    final isInfoNode = SafeProxyUri.isInfoMetadataProfile(
      host: server,
      port: port,
      displayName: name,
      uuid: _string(extra['uuid']),
    );

    final hash = SafeProxyUri.stableHash(
      'clash:$type:$server:$port:$name:'
      '${extra['uuid'] ?? extra['password'] ?? extra['auth'] ?? ''}',
    );

    return ServerProfile(
      id: '${protocol}_${server}_${port}_$hash',
      displayName: name,
      protocol: protocol,
      source: ProfileSource.subscription,
      serverAddress: server,
      serverPort: port,
      extraParams: <String, dynamic>{
        ...extra,
        if (isInfoNode) 'isInfoNode': true,
      },
    );
  }

  void _applyTransport(Map<String, dynamic> proxy, Map<String, dynamic> extra) {
    final network = (_string(proxy['network']) ?? 'tcp').toLowerCase();
    if (network == 'ws') {
      extra['transportType'] = 'ws';
      final wsOpts = _map(proxy['ws-opts']);
      extra['path'] = _string(wsOpts['path']) ?? '/';
      final headers = _map(wsOpts['headers']);
      extra['host'] = _string(headers['Host']) ?? _string(headers['host']);
      extra['ed'] = _integer(wsOpts['max-early-data']);
    } else if (network == 'grpc') {
      extra['transportType'] = 'grpc';
      final grpcOpts = _map(proxy['grpc-opts']);
      extra['serviceName'] = _string(grpcOpts['grpc-service-name']);
    } else if (network == 'h2' || network == 'http') {
      extra['transportType'] = 'http';
      final httpOpts = _map(proxy['h2-opts']);
      extra['path'] = _string(httpOpts['path']) ?? '/';
      final hosts = httpOpts['host'];
      if (hosts is List) {
        extra['host'] = hosts.join(',');
      } else {
        extra['host'] = _string(hosts);
      }
    } else if (network == 'httpupgrade') {
      extra['transportType'] = 'httpupgrade';
      final opts = _map(proxy['httpupgrade-opts']);
      extra['path'] = _string(opts['path']) ?? '/';
      extra['host'] = _string(opts['host']);
    } else if (network == 'quic') {
      extra['transportType'] = 'quic';
    }
  }

  static Map<String, dynamic> _map(dynamic value) {
    if (value is! Map) return const <String, dynamic>{};
    return <String, dynamic>{
      for (final entry in value.entries) entry.key.toString(): entry.value,
    };
  }

  static String? _string(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static bool _boolean(dynamic value, {bool fallback = false}) {
    if (value == null) return fallback;
    if (value is bool) return value;
    final text = value.toString().toLowerCase();
    if (text == 'true' || text == '1') return true;
    if (text == 'false' || text == '0') return false;
    return fallback;
  }

  static int? _integer(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static String? _alpn(dynamic value) {
    if (value is List) {
      final list = value
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
      return list.isEmpty ? null : list.join(',');
    }
    return _string(value);
  }
}
