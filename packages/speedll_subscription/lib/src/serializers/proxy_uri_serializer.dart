import 'dart:convert';

import '../models/server_profile.dart';
import '../parsers/subscription_parser.dart';

/// Serializes normalized [ServerProfile] instances back into standard proxy
/// share URIs (`vless://`, `vmess://`, `trojan://`, `ss://`, `hysteria2://`,
/// `hysteria://`, `tuic://`, `anytls://`, `wireguard://`) without mutating or
/// persisting raw URIs alongside encrypted secrets.
class ProxyUriSerializer {
  const ProxyUriSerializer._();

  /// Returns a shareable proxy URI for [profile], or `null` if [profile]
  /// is an info placeholder, lacks a host, or is missing required credentials.
  static String? serialize(ServerProfile profile) {
    final hostRaw = profile.serverAddress?.trim() ?? '';
    if (hostRaw.isEmpty) return null;

    final protocol = profile.protocol.trim().toLowerCase();
    final extra = profile.extraParams;
    if (extra['isInfoNode'] == true) return null;

    final host = _formatHostAuthority(hostRaw);
    final fragment = _formatFragment(profile.displayName);

    switch (protocol) {
      case 'vless':
        return _serializeVless(
          host: host,
          port: _portOrDefault(profile.serverPort, 443),
          extra: extra,
          fragment: fragment,
        );
      case 'vmess':
        return _serializeVmess(
          rawHost: SafeProxyUri.normalizeHost(hostRaw),
          port: _portOrDefault(profile.serverPort, 443),
          displayName: profile.displayName,
          extra: extra,
        );
      case 'trojan':
        return _serializeTrojan(
          host: host,
          port: _portOrDefault(profile.serverPort, 443),
          extra: extra,
          fragment: fragment,
        );
      case 'shadowsocks':
      case 'ss':
        return _serializeShadowsocks(
          host: host,
          port: _portOrDefault(profile.serverPort, 8388),
          extra: extra,
          fragment: fragment,
        );
      case 'hysteria2':
      case 'hy2':
        return _serializeHysteria2(
          host: host,
          port: _portOrDefault(profile.serverPort, 443),
          extra: extra,
          fragment: fragment,
        );
      case 'hysteria':
        return _serializeHysteria1(
          host: host,
          port: _portOrDefault(profile.serverPort, 443),
          extra: extra,
          fragment: fragment,
        );
      case 'tuic':
        return _serializeTuic(
          host: host,
          port: _portOrDefault(profile.serverPort, 443),
          extra: extra,
          fragment: fragment,
        );
      case 'anytls':
        return _serializeAnyTls(
          host: host,
          port: _portOrDefault(profile.serverPort, 443),
          extra: extra,
          fragment: fragment,
        );
      case 'wireguard':
      case 'wg':
        return _serializeWireguard(
          host: host,
          port: _portOrDefault(profile.serverPort, 51820),
          extra: extra,
          fragment: fragment,
        );
      default:
        return null;
    }
  }

  static String? _serializeVless({
    required String host,
    required int port,
    required Map<String, dynamic> extra,
    required String fragment,
  }) {
    final uuid = _str(extra['uuid']) ?? _str(extra['id']);
    if (uuid == null) return null;

    final query = <String, String>{};
    final pbk = _str(extra['pbk']);
    final security = _str(extra['security']) ??
        (pbk != null ? 'reality' : 'none');
    final transportType =
        _str(extra['transportType']) ?? _str(extra['type']) ?? 'tcp';

    query['encryption'] = _str(extra['encryption']) ?? 'none';
    query['security'] = security;
    query['type'] = transportType;

    _putIfPresent(query, 'flow', _str(extra['flow']));
    _putIfPresent(query, 'sni', _str(extra['sni']) ?? _str(extra['peer']));
    _putIfPresent(query, 'fp', _str(extra['fingerprint']) ?? _str(extra['fp']));
    _putIfPresent(query, 'pbk', pbk);
    _putIfPresent(query, 'sid', _str(extra['sid']));
    _putIfPresent(query, 'spx', _str(extra['spx']));
    _putIfPresent(query, 'headerType', _str(extra['headerType']));
    _putIfPresent(query, 'host', _str(extra['host']) ?? _str(extra['authority']));
    _putIfPresent(query, 'path', _str(extra['path']));
    _putIfPresent(
      query,
      'serviceName',
      _str(extra['serviceName']) ?? _str(extra['service_name']),
    );
    _putIfPresent(query, 'mode', _str(extra['mode']));
    _putIfPresent(query, 'alpn', _str(extra['alpn']));
    _putIfPresent(
      query,
      'packetEncoding',
      _str(extra['packetEncoding']) ?? _str(extra['packet_encoding']),
    );
    if (_isTrue(extra['allowInsecure']) || _isTrue(extra['insecure'])) {
      query['allowInsecure'] = '1';
    }

    return _buildUri(
      scheme: 'vless',
      userInfo: Uri.encodeComponent(uuid),
      host: host,
      port: port,
      query: query,
      fragment: fragment,
    );
  }

  static String? _serializeVmess({
    required String rawHost,
    required int port,
    required String displayName,
    required Map<String, dynamic> extra,
  }) {
    final uuid = _str(extra['uuid']) ?? _str(extra['id']);
    if (uuid == null) return null;

    final net = _str(extra['transportType']) ?? _str(extra['net']) ?? 'tcp';
    final rawTls = _str(extra['tls'])?.toLowerCase();
    final rawSecurity = _str(extra['security'])?.toLowerCase();
    final isTls = rawTls == 'tls' ||
        rawTls == '1' ||
        rawTls == 'true' ||
        rawSecurity == 'tls';

    final pathVal = net == 'grpc'
        ? (_str(extra['serviceName']) ?? _str(extra['path']) ?? '')
        : (_str(extra['path']) ?? '');

    final cipher = _str(extra['scy']) ??
        (rawSecurity != null && rawSecurity != 'tls' && rawSecurity != 'none'
            ? rawSecurity
            : 'auto');

    final payload = <String, dynamic>{
      'v': '2',
      'ps': displayName.trim().isNotEmpty ? displayName.trim() : '$rawHost:$port',
      'add': rawHost,
      'port': port,
      'id': uuid,
      'aid': '${extra['alterId'] ?? extra['aid'] ?? 0}',
      'scy': cipher,
      'net': net,
      'type': _str(extra['headerType']) ?? _str(extra['type']) ?? 'none',
      'host': _str(extra['host']) ?? _str(extra['authority']) ?? '',
      'path': pathVal,
      'tls': isTls ? 'tls' : '',
      if (_str(extra['sni']) != null) 'sni': _str(extra['sni']),
      if (_str(extra['alpn']) != null) 'alpn': _str(extra['alpn']),
      if ((_str(extra['fingerprint']) ?? _str(extra['fp'])) != null)
        'fp': _str(extra['fingerprint']) ?? _str(extra['fp']),
      if (_isTrue(extra['allowInsecure']) || _isTrue(extra['insecure']))
        'allowInsecure': 1,
    };

    final encoded = base64Encode(utf8.encode(jsonEncode(payload)));
    return 'vmess://$encoded';
  }

  static String? _serializeTrojan({
    required String host,
    required int port,
    required Map<String, dynamic> extra,
    required String fragment,
  }) {
    final password = _str(extra['password']);
    if (password == null) return null;

    final pbk = _str(extra['pbk']);
    final security = _str(extra['security']) ??
        (pbk != null ? 'reality' : 'tls');
    final transportType =
        _str(extra['transportType']) ?? _str(extra['type']) ?? 'tcp';

    final query = <String, String>{
      'security': security,
      'type': transportType,
    };
    _putIfPresent(query, 'sni', _str(extra['sni']) ?? _str(extra['peer']));
    _putIfPresent(query, 'fp', _str(extra['fingerprint']) ?? _str(extra['fp']));
    _putIfPresent(query, 'pbk', pbk);
    _putIfPresent(query, 'sid', _str(extra['sid']));
    _putIfPresent(query, 'headerType', _str(extra['headerType']));
    _putIfPresent(query, 'host', _str(extra['host']) ?? _str(extra['authority']));
    _putIfPresent(query, 'path', _str(extra['path']));
    _putIfPresent(
      query,
      'serviceName',
      _str(extra['serviceName']) ?? _str(extra['service_name']),
    );
    _putIfPresent(query, 'alpn', _str(extra['alpn']));
    if (_isTrue(extra['allowInsecure']) || _isTrue(extra['insecure'])) {
      query['allowInsecure'] = '1';
    }

    return _buildUri(
      scheme: 'trojan',
      userInfo: Uri.encodeComponent(password),
      host: host,
      port: port,
      query: query,
      fragment: fragment,
    );
  }

  static String? _serializeShadowsocks({
    required String host,
    required int port,
    required Map<String, dynamic> extra,
    required String fragment,
  }) {
    final method = _str(extra['method']) ?? 'aes-256-gcm';
    final password = _str(extra['password']) ?? '';
    if (password.isEmpty && method.isEmpty) return null;

    final userInfoToken = base64UrlEncode(utf8.encode('$method:$password'))
        .replaceAll('=', '');

    final query = <String, String>{};
    final plugin = _str(extra['plugin']);
    final pluginOpts = _str(extra['pluginOpts']) ?? _str(extra['plugin-opts']);
    if (plugin != null) {
      query['plugin'] = pluginOpts != null && !plugin.contains(';')
          ? '$plugin;$pluginOpts'
          : plugin;
    }
    if (_isTrue(extra['udpOverTcp']) || _isTrue(extra['uot'])) {
      query['uot'] = '1';
    }

    return _buildUri(
      scheme: 'ss',
      userInfo: userInfoToken,
      host: host,
      port: port,
      query: query,
      fragment: fragment,
    );
  }

  static String? _serializeHysteria2({
    required String host,
    required int port,
    required Map<String, dynamic> extra,
    required String fragment,
  }) {
    final auth = _str(extra['auth']) ?? _str(extra['password']);
    final query = <String, String>{};
    _putIfPresent(query, 'sni', _str(extra['sni']) ?? _str(extra['peer']));
    if (_isTrue(extra['insecure']) || _isTrue(extra['allowInsecure'])) {
      query['insecure'] = '1';
    }
    _putIfPresent(query, 'mport', _str(extra['mport']));
    _putIfPresent(query, 'obfs', _str(extra['obfs']));
    _putIfPresent(
      query,
      'obfs-password',
      _str(extra['obfsPassword']) ?? _str(extra['obfs-password']),
    );
    _putIfPresent(query, 'alpn', _str(extra['alpn']));
    _putIfPresent(query, 'upmbps', _str(extra['upMbps']));
    _putIfPresent(query, 'downmbps', _str(extra['downMbps']));

    return _buildUri(
      scheme: 'hysteria2',
      userInfo: auth != null ? Uri.encodeComponent(auth) : null,
      host: host,
      port: port,
      query: query,
      fragment: fragment,
    );
  }

  static String? _serializeHysteria1({
    required String host,
    required int port,
    required Map<String, dynamic> extra,
    required String fragment,
  }) {
    final auth = _str(extra['auth']) ?? _str(extra['auth_str']);
    final query = <String, String>{};
    _putIfPresent(query, 'auth', auth);
    _putIfPresent(query, 'peer', _str(extra['sni']) ?? _str(extra['peer']));
    _putIfPresent(query, 'alpn', _str(extra['alpn']));
    _putIfPresent(query, 'upmbps', _str(extra['upMbps']) ?? _str(extra['up']));
    _putIfPresent(
      query,
      'downmbps',
      _str(extra['downMbps']) ?? _str(extra['down']),
    );
    _putIfPresent(query, 'obfs', _str(extra['obfs']));
    _putIfPresent(
      query,
      'obfsParam',
      _str(extra['obfsPassword']) ?? _str(extra['obfsParam']),
    );
    if (_isTrue(extra['insecure']) || _isTrue(extra['allowInsecure'])) {
      query['insecure'] = '1';
    }

    return _buildUri(
      scheme: 'hysteria',
      userInfo: auth != null ? Uri.encodeComponent(auth) : null,
      host: host,
      port: port,
      query: query,
      fragment: fragment,
    );
  }

  static String? _serializeTuic({
    required String host,
    required int port,
    required Map<String, dynamic> extra,
    required String fragment,
  }) {
    final uuid = _str(extra['uuid']);
    if (uuid == null) return null;
    final password = _str(extra['password']) ?? '';
    final encodedUserInfo = password.isNotEmpty
        ? '${Uri.encodeComponent(uuid)}:${Uri.encodeComponent(password)}'
        : Uri.encodeComponent(uuid);

    final query = <String, String>{};
    _putIfPresent(query, 'sni', _str(extra['sni']) ?? _str(extra['peer']));
    _putIfPresent(query, 'alpn', _str(extra['alpn']));
    _putIfPresent(
      query,
      'congestion_control',
      _str(extra['congestionControl']) ?? _str(extra['congestion_control']),
    );
    _putIfPresent(
      query,
      'udp_relay_mode',
      _str(extra['udpRelayMode']) ?? _str(extra['udp_relay_mode']),
    );
    if (_isTrue(extra['udpOverStream']) || _isTrue(extra['udp_over_stream'])) {
      query['udp_over_stream'] = '1';
    }
    if (_isTrue(extra['zeroRttHandshake']) ||
        _isTrue(extra['zero_rtt_handshake'])) {
      query['zero_rtt_handshake'] = '1';
    }
    if (_isTrue(extra['insecure']) ||
        _isTrue(extra['allow_insecure']) ||
        _isTrue(extra['allowInsecure'])) {
      query['allow_insecure'] = '1';
    }

    return _buildUri(
      scheme: 'tuic',
      userInfo: encodedUserInfo,
      host: host,
      port: port,
      query: query,
      fragment: fragment,
    );
  }

  static String? _serializeAnyTls({
    required String host,
    required int port,
    required Map<String, dynamic> extra,
    required String fragment,
  }) {
    final password = _str(extra['password']);
    if (password == null) return null;

    final query = <String, String>{};
    _putIfPresent(query, 'sni', _str(extra['sni']) ?? _str(extra['peer']));
    if (_isTrue(extra['insecure']) || _isTrue(extra['allowInsecure'])) {
      query['insecure'] = '1';
    }

    return _buildUri(
      scheme: 'anytls',
      userInfo: Uri.encodeComponent(password),
      host: host,
      port: port,
      query: query,
      fragment: fragment,
    );
  }

  static String? _serializeWireguard({
    required String host,
    required int port,
    required Map<String, dynamic> extra,
    required String fragment,
  }) {
    final privateKey = _str(extra['privateKey']) ?? _str(extra['private_key']);
    final publicKey = _str(extra['publicKey']) ?? _str(extra['public_key']);
    if (privateKey == null || publicKey == null) return null;

    final query = <String, String>{
      'publickey': publicKey,
    };

    final rawLocal = extra['localAddress'] ?? extra['address'];
    if (rawLocal is List && rawLocal.isNotEmpty) {
      _putIfPresent(
        query,
        'address',
        rawLocal.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).join(','),
      );
    } else if (rawLocal != null) {
      _putIfPresent(query, 'address', rawLocal.toString());
    }

    _putIfPresent(query, 'mtu', _str(extra['mtu']));

    final rawReserved = extra['reserved'];
    if (rawReserved is List && rawReserved.length == 3) {
      query['reserved'] = rawReserved.map((e) => e.toString()).join(',');
    } else if (rawReserved != null) {
      _putIfPresent(query, 'reserved', _str(rawReserved));
    }

    _putIfPresent(
      query,
      'presharedkey',
      _str(extra['preSharedKey']) ??
          _str(extra['pre_shared_key']) ??
          _str(extra['presharedkey']),
    );

    return _buildUri(
      scheme: 'wireguard',
      userInfo: Uri.encodeComponent(privateKey),
      host: host,
      port: port,
      query: query,
      fragment: fragment,
    );
  }

  static String _buildUri({
    required String scheme,
    required String? userInfo,
    required String host,
    required int port,
    required Map<String, String> query,
    required String fragment,
  }) {
    final buffer = StringBuffer('$scheme://');
    if (userInfo != null && userInfo.isNotEmpty) {
      buffer.write('$userInfo@');
    }
    buffer.write('$host:$port');
    if (query.isNotEmpty) {
      buffer.write('?');
      var first = true;
      for (final entry in query.entries) {
        if (!first) buffer.write('&');
        first = false;
        buffer.write(
          '${Uri.encodeQueryComponent(entry.key)}='
          '${Uri.encodeQueryComponent(entry.value)}',
        );
      }
    }
    if (fragment.isNotEmpty) {
      buffer.write('#$fragment');
    }
    return buffer.toString();
  }

  static String _formatHostAuthority(String rawHost) {
    final normalized = SafeProxyUri.normalizeHost(rawHost);
    try {
      Uri.parseIPv6Address(normalized);
      return '[$normalized]';
    } on FormatException {
      return normalized;
    }
  }

  static String _formatFragment(String displayName) {
    final clean = displayName.trim();
    if (clean.isEmpty) return '';
    return Uri.encodeComponent(clean);
  }

  static int _portOrDefault(int? port, int fallback) {
    return port != null && port > 0 && port <= 65535 ? port : fallback;
  }

  static void _putIfPresent(
    Map<String, String> target,
    String key,
    String? value,
  ) {
    if (value != null && value.isNotEmpty) {
      target[key] = value;
    }
  }

  static String? _str(dynamic value) {
    if (value == null) return null;
    final trimmed = value.toString().trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static bool _isTrue(dynamic value) {
    if (value == true || value == 1) return true;
    final lower = value?.toString().trim().toLowerCase();
    return lower == 'true' || lower == '1';
  }
}
