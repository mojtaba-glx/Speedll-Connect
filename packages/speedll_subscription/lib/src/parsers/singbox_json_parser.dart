import 'dart:convert';
import '../models/server_profile.dart';
import 'subscription_parser.dart';
import 'wireguard_parser.dart';

/// Parses a sing-box JSON configuration (full document with `outbounds` / `endpoints`,
/// or a single outbound/endpoint JSON object) and converts every supported entry
/// into a normalized [ServerProfile].
class SingboxJsonParser implements SubscriptionParser {
  const SingboxJsonParser();

  @override
  String get parserName => 'sing-box JSON';

  @override
  bool canParse(String content) {
    final trimmed = content.replaceAll('\uFEFF', '').trim();
    if (!trimmed.startsWith('{') || !trimmed.endsWith('}')) return false;
    final lower = trimmed.toLowerCase();
    return lower.contains('"outbounds"') ||
        lower.contains('"endpoints"') ||
        (lower.contains('"type"') &&
            (lower.contains('"server"') || lower.contains('"peers"')));
  }

  @override
  Future<ParseResult> parse(String content) async {
    try {
      final decoded = jsonDecode(content.replaceAll('\uFEFF', ''));
      if (decoded is! Map) {
        return ParseResult.failure('ساختار JSON اشتراک sing-box نامعتبر است.');
      }

      final rawEntries = <dynamic>[];
      if (decoded['outbounds'] is List) {
        rawEntries.addAll(decoded['outbounds'] as List);
      }
      if (decoded['endpoints'] is List) {
        rawEntries.addAll(decoded['endpoints'] as List);
      }
      if (rawEntries.isEmpty && decoded['type'] is String) {
        rawEntries.add(decoded);
      }

      if (rawEntries.isEmpty) {
        return ParseResult.failure(
          'فهرست outbounds یا endpoints در فایل sing-box یافت نشد.',
        );
      }

      final profiles = <ServerProfile>[];
      final warnings = <String>[];
      for (final entry in rawEntries) {
        if (entry is! Map) continue;
        final map = <String, dynamic>{
          for (final item in entry.entries) item.key.toString(): item.value,
        };
        final profile = _profileFromOutbound(map);
        if (profile != null) {
          profiles.add(profile);
        } else {
          final type = _string(map['type']) ?? 'unknown';
          if (!const <String>{
            'direct',
            'block',
            'dns',
            'selector',
            'urltest',
          }.contains(type.toLowerCase())) {
            warnings.add('Outbound از نوع $type پشتیبانی نمی‌شود.');
          }
        }
      }

      if (profiles.isEmpty) {
        return ParseResult(
          isSuccess: false,
          errorMessage:
              'هیچ outbound پشتیبانی‌شده‌ای در فایل sing-box یافت نشد.',
          warnings: warnings,
        );
      }
      return ParseResult.success(profiles, warnings: warnings);
    } catch (e) {
      return ParseResult.failure('خطا در تحلیل فایل JSON اشتراک sing-box: $e');
    }
  }

  ServerProfile? _profileFromOutbound(Map<String, dynamic> outbound) {
    final type = (_string(outbound['type']) ?? '').toLowerCase();
    if (type == 'wireguard') {
      return _profileFromWireguard(outbound);
    }

    final server = _string(outbound['server']);
    final port = _integer(outbound['server_port']);
    if (server == null || port == null || port <= 0) return null;

    final tag = _string(outbound['tag']) ?? '$server:$port';
    final extra = <String, dynamic>{};
    final String protocol;

    switch (type) {
      case 'vless':
        protocol = 'vless';
        extra['uuid'] = _string(outbound['uuid']) ?? '';
        extra['flow'] = _string(outbound['flow']);
        extra['packetEncoding'] = _string(outbound['packet_encoding']);
        _applyTls(outbound['tls'], extra);
        _applyTransport(outbound['transport'], extra);
        break;
      case 'vmess':
        protocol = 'vmess';
        extra['uuid'] = _string(outbound['uuid']) ?? '';
        extra['scy'] = _string(outbound['security']) ?? 'auto';
        extra['alterId'] = _integer(outbound['alter_id']) ?? 0;
        extra['packetEncoding'] = _string(outbound['packet_encoding']);
        _applyTls(outbound['tls'], extra);
        if (extra['security'] == 'tls') {
          extra['tls'] = 'tls';
        }
        _applyTransport(outbound['transport'], extra);
        break;
      case 'trojan':
        protocol = 'trojan';
        extra['password'] = _string(outbound['password']) ?? '';
        _applyTls(outbound['tls'], extra);
        if (extra['security'] == null) {
          extra['security'] = 'tls';
        }
        _applyTransport(outbound['transport'], extra);
        break;
      case 'shadowsocks':
        protocol = 'shadowsocks';
        extra['method'] = _string(outbound['method']) ?? 'aes-256-gcm';
        extra['password'] = _string(outbound['password']) ?? '';
        if (_string(outbound['plugin']) != null) {
          extra['plugin'] = _string(outbound['plugin']);
        }
        if (_string(outbound['plugin_opts']) != null) {
          extra['pluginOpts'] = _string(outbound['plugin_opts']);
        }
        if (outbound['udp_over_tcp'] == true || outbound['udp_over_tcp'] is Map) {
          extra['udpOverTcp'] = true;
        }
        break;
      case 'hysteria2':
        protocol = 'hysteria2';
        extra['auth'] = _string(outbound['password']) ?? '';
        final obfs = _map(outbound['obfs']);
        extra['obfs'] = _string(obfs['type']);
        extra['obfsPassword'] = _string(obfs['password']);
        final serverPorts = outbound['server_ports'];
        if (serverPorts is List && serverPorts.isNotEmpty) {
          extra['mport'] = serverPorts.map((e) => e.toString()).join(',');
        }
        final upMbps = _integer(outbound['up_mbps']);
        final downMbps = _integer(outbound['down_mbps']);
        if (upMbps != null && upMbps > 0) extra['upMbps'] = upMbps;
        if (downMbps != null && downMbps > 0) extra['downMbps'] = downMbps;
        _applyTls(outbound['tls'], extra);
        break;
      case 'hysteria':
        protocol = 'hysteria';
        extra['auth'] = _string(outbound['auth_str']) ?? '';
        extra['upMbps'] = _integer(outbound['up_mbps']);
        extra['downMbps'] = _integer(outbound['down_mbps']);
        extra['obfs'] = _string(outbound['obfs']);
        _applyTls(outbound['tls'], extra);
        break;
      case 'tuic':
        protocol = 'tuic';
        extra['uuid'] = _string(outbound['uuid']) ?? '';
        extra['password'] = _string(outbound['password']) ?? '';
        extra['congestionControl'] =
            _string(outbound['congestion_control']);
        extra['udpRelayMode'] = _string(outbound['udp_relay_mode']);
        extra['udpOverStream'] = outbound['udp_over_stream'] == true;
        extra['zeroRttHandshake'] =
            outbound['zero_rtt_handshake'] == true;
        _applyTls(outbound['tls'], extra);
        break;
      case 'anytls':
        protocol = 'anytls';
        extra['password'] = _string(outbound['password']) ?? '';
        _applyTls(outbound['tls'], extra);
        break;
      default:
        return null;
    }

    final isInfoNode = SafeProxyUri.isInfoMetadataProfile(
      host: server,
      port: port,
      displayName: tag,
      uuid: _string(extra['uuid']),
    );

    final hash = SafeProxyUri.stableHash(
      'singbox:$type:$server:$port:$tag:'
      '${extra['uuid'] ?? extra['password'] ?? extra['auth'] ?? ''}',
    );

    return ServerProfile(
      id: '${protocol}_${server}_${port}_$hash',
      displayName: tag,
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

  ServerProfile? _profileFromWireguard(Map<String, dynamic> raw) {
    final privateKey = _string(raw['private_key']) ?? '';
    if (privateKey.isEmpty) return null;

    String? server = _string(raw['server']);
    int? port = _integer(raw['server_port']);
    String? publicKey = _string(raw['peer_public_key']) ?? _string(raw['public_key']);
    String? preSharedKey = _string(raw['pre_shared_key']);
    List<int>? reserved = WireguardParser.parseReserved(raw['reserved']);

    final peers = raw['peers'];
    if (peers is List && peers.isNotEmpty) {
      final firstPeer = _map(peers.first);
      server ??= _string(firstPeer['address']) ?? _string(firstPeer['server']);
      port ??= _integer(firstPeer['port']) ?? _integer(firstPeer['server_port']);
      publicKey ??=
          _string(firstPeer['public_key']) ?? _string(firstPeer['peer_public_key']);
      preSharedKey ??= _string(firstPeer['pre_shared_key']);
      reserved ??= WireguardParser.parseReserved(firstPeer['reserved']);
    }

    if (server == null ||
        port == null ||
        port <= 0 ||
        publicKey == null ||
        publicKey.isEmpty) {
      return null;
    }

    final tag = _string(raw['tag']) ?? '$server:$port';
    final addresses = WireguardParser.normalizeAddressList(
      raw['address'] ?? raw['local_address'] ?? '172.16.0.2/32',
    );
    final mtu = _integer(raw['mtu']) ?? 1408;

    final isInfoNode = SafeProxyUri.isInfoMetadataProfile(
      host: server,
      port: port,
      displayName: tag,
    );

    final hash = SafeProxyUri.stableHash(
      'singbox:wireguard:$server:$port:$tag:$publicKey',
    );

    return ServerProfile(
      id: 'wireguard_${server}_${port}_$hash',
      displayName: tag,
      protocol: 'wireguard',
      source: ProfileSource.subscription,
      serverAddress: server,
      serverPort: port,
      extraParams: <String, dynamic>{
        'privateKey': privateKey,
        'publicKey': publicKey,
        if (preSharedKey != null) 'preSharedKey': preSharedKey,
        'localAddress': addresses,
        'mtu': mtu,
        if (reserved != null) 'reserved': reserved,
        if (isInfoNode) 'isInfoNode': true,
      },
    );
  }

  void _applyTls(dynamic rawTls, Map<String, dynamic> extra) {
    final tls = _map(rawTls);
    if (tls.isEmpty) return;
    final enabled = tls['enabled'] == true;
    extra['sni'] = _string(tls['server_name']);
    extra['insecure'] = tls['insecure'] == true;
    final alpn = tls['alpn'];
    if (alpn is List) {
      extra['alpn'] = alpn
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .join(',');
    }
    final utls = _map(tls['utls']);
    extra['fingerprint'] = _string(utls['fingerprint']);
    final reality = _map(tls['reality']);
    if (reality['enabled'] == true) {
      extra['security'] = 'reality';
      extra['pbk'] = _string(reality['public_key']);
      extra['sid'] = _string(reality['short_id']);
    } else if (enabled) {
      extra['security'] = 'tls';
    }
  }

  void _applyTransport(dynamic rawTransport, Map<String, dynamic> extra) {
    final transport = _map(rawTransport);
    final type = (_string(transport['type']) ?? '').toLowerCase();
    if (type.isEmpty) return;

    if (type == 'ws') {
      extra['transportType'] = 'ws';
      extra['path'] = _string(transport['path']) ?? '/';
      final headers = _map(transport['headers']);
      extra['host'] = _string(headers['Host']) ?? _string(headers['host']);
      extra['ed'] = _integer(transport['max_early_data']);
    } else if (type == 'grpc') {
      extra['transportType'] = 'grpc';
      extra['serviceName'] = _string(transport['service_name']);
    } else if (type == 'http' || type == 'h2') {
      extra['transportType'] = 'http';
      extra['path'] = _string(transport['path']) ?? '/';
      final hosts = transport['host'];
      if (hosts is List) {
        extra['host'] = hosts.join(',');
      } else {
        extra['host'] = _string(hosts);
      }
    } else if (type == 'httpupgrade') {
      extra['transportType'] = 'httpupgrade';
      extra['path'] = _string(transport['path']) ?? '/';
      extra['host'] = _string(transport['host']);
    } else if (type == 'quic') {
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

  static int? _integer(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}
