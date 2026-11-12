import '../models/server_profile.dart';
import '../parsers/subscription_parser.dart';
import '../parsers/wireguard_parser.dart';
import '../routing/china_direct_assets.dart';
import '../routing/iran_direct_assets.dart';
import '../routing/russia_direct_assets.dart';

class SingboxConvertException implements Exception {
  const SingboxConvertException(this.message);
  final String message;
  @override
  String toString() => 'SingboxConvertException: $message';
}

/// Regions with bundled domestic direct-routing data. `auto` is resolved by the
/// apps at startup; the converter treats it as Iran for backward compatibility.
enum RoutingRegion {
  auto,
  iran,
  china,
  russia,
  global;

  static RoutingRegion fromWireName(String? value) {
    return RoutingRegion.values.firstWhere(
      (region) => region.name == value?.trim().toLowerCase(),
      orElse: () => RoutingRegion.auto,
    );
  }
}

/// Configuration options for sing-box routing, DNS, and core protocol behavior.
class SingboxRoutingOptions {
  const SingboxRoutingOptions({
    this.region = RoutingRegion.auto,
    this.bypassLan = true,
    this.bypassIranDomains = true,
    this.customDirectDomains = const <String>[],
    this.customDirectCidrs = const <String>[],
    this.remoteDnsServer = '1.1.1.1',
    this.directDnsServer = '178.22.122.100',
    this.enableTrafficSniffing = false,
    this.enableMux = false,
    this.killSwitch = false,
    this.enableIpv6 = false,
  });

  final RoutingRegion region;
  final bool bypassLan;
  final bool bypassIranDomains;
  final List<String> customDirectDomains;
  final List<String> customDirectCidrs;
  final String remoteDnsServer;
  final String directDnsServer;
  final bool enableTrafficSniffing;
  final bool enableMux;
  final bool killSwitch;
  final bool enableIpv6;

  SingboxRoutingOptions copyWith({
    RoutingRegion? region,
    bool? bypassLan,
    bool? bypassIranDomains,
    List<String>? customDirectDomains,
    List<String>? customDirectCidrs,
    String? remoteDnsServer,
    String? directDnsServer,
    bool? enableTrafficSniffing,
    bool? enableMux,
    bool? killSwitch,
    bool? enableIpv6,
  }) {
    return SingboxRoutingOptions(
      region: region ?? this.region,
      bypassLan: bypassLan ?? this.bypassLan,
      bypassIranDomains: bypassIranDomains ?? this.bypassIranDomains,
      customDirectDomains: customDirectDomains ?? this.customDirectDomains,
      customDirectCidrs: customDirectCidrs ?? this.customDirectCidrs,
      remoteDnsServer: remoteDnsServer ?? this.remoteDnsServer,
      directDnsServer: directDnsServer ?? this.directDnsServer,
      enableTrafficSniffing:
          enableTrafficSniffing ?? this.enableTrafficSniffing,
      enableMux: enableMux ?? this.enableMux,
      killSwitch: killSwitch ?? this.killSwitch,
      enableIpv6: enableIpv6 ?? this.enableIpv6,
    );
  }
}

/// Converts normalized ServerProfile into deterministic sing-box outbound and full JSON structures.
class SingboxConverter {
  const SingboxConverter();

  static const List<String> defaultLanCidrs = <String>[
    '10.0.0.0/8',
    '172.16.0.0/12',
    '192.168.0.0/16',
    '127.0.0.0/8',
    '100.64.0.0/10',
    '169.254.0.0/16',
    'fc00::/7',
    'fe80::/10',
    '::1/128',
  ];

  static const List<String> defaultLanDomainSuffixes = <String>[
    '.local',
    '.lan',
    '.home.arpa',
    'localhost',
  ];

  static const List<String> defaultIranDomainSuffixes = iranDomainSuffixes;
  static const List<String> defaultChinaDomainSuffixes = chinaDomainSuffixes;
  static const List<String> defaultRussiaDomainSuffixes = russiaDomainSuffixes;

  static List<String> domesticDomainSuffixes(RoutingRegion region) {
    return switch (region) {
      RoutingRegion.china => chinaDomainSuffixes,
      RoutingRegion.russia => russiaDomainSuffixes,
      RoutingRegion.global => const <String>[],
      RoutingRegion.auto || RoutingRegion.iran => iranDomainSuffixes,
    };
  }

  static List<String> domesticIpCidrs(RoutingRegion region) {
    return switch (region) {
      RoutingRegion.china => chinaIpCidrs,
      RoutingRegion.russia => russiaIpCidrs,
      RoutingRegion.global => const <String>[],
      RoutingRegion.auto || RoutingRegion.iran => iranIpCidrs,
    };
  }

  /// Builds deterministic sing-box v1.14+ routing rules including sniff, DNS hijack, LAN/private IP bypass, and .ir domain bypass.
  List<Map<String, dynamic>> buildRoutingRules([
    SingboxRoutingOptions options = const SingboxRoutingOptions(),
  ]) {
    final rules = <Map<String, dynamic>>[
      // Hijack DNS traffic before optional traffic sniffing so DNS packets
      // never stall or fail inside stream/packet sniffers on Android gVisor TUN.
      <String, dynamic>{
        'inbound': 'dns-in',
        'action': 'hijack-dns',
      },
      <String, dynamic>{
        'port': <int>[53],
        'action': 'hijack-dns',
      },
      <String, dynamic>{
        'protocol': 'dns',
        'action': 'hijack-dns',
      },
      if (options.enableTrafficSniffing)
        <String, dynamic>{
          'action': 'sniff',
          'sniffer': <String>['tls', 'http', 'quic'],
          'timeout': '100ms',
        },
    ];

    if (options.bypassLan) {
      rules.add(<String, dynamic>{
        'ip_is_private': true,
        'outbound': 'direct',
      });
      rules.add(<String, dynamic>{
        'ip_cidr': List<String>.from(defaultLanCidrs),
        'outbound': 'direct',
      });
      rules.add(<String, dynamic>{
        'domain_suffix': List<String>.from(defaultLanDomainSuffixes),
        'outbound': 'direct',
      });
    }

    if (options.bypassIranDomains) {
      final domesticDomains = domesticDomainSuffixes(options.region);
      final domesticCidrs = domesticIpCidrs(options.region);
      if (domesticDomains.isNotEmpty) {
        rules.add(<String, dynamic>{
          'domain_suffix': List<String>.from(domesticDomains),
          'outbound': 'direct',
        });
      }
      if (domesticCidrs.isNotEmpty) {
        rules.add(<String, dynamic>{
          'ip_cidr': List<String>.from(domesticCidrs),
          'outbound': 'direct',
        });
      }
    }

    if (options.customDirectDomains.isNotEmpty) {
      rules.add(<String, dynamic>{
        'domain_suffix': List<String>.from(options.customDirectDomains),
        'outbound': 'direct',
      });
    }

    if (options.customDirectCidrs.isNotEmpty) {
      rules.add(<String, dynamic>{
        'ip_cidr': List<String>.from(options.customDirectCidrs),
        'outbound': 'direct',
      });
    }

    return rules;
  }

  /// Builds sing-box v1.14+ DNS configuration aligned with the active routing rules to prevent DNS leaks while allowing direct resolution for bypassed domains.
  Map<String, dynamic> buildDnsConfig([
    SingboxRoutingOptions options = const SingboxRoutingOptions(),
  ]) {
    final directDnsDomains = <String>[
      if (options.bypassLan) ...defaultLanDomainSuffixes,
      if (options.bypassIranDomains) ...domesticDomainSuffixes(options.region),
      ...options.customDirectDomains,
    ];

    // Keep direct/local DNS entries free of `detour: 'direct'` because sing-box
    // v1.14 rejects detouring to an empty direct outbound on core startup.
    final directDnsEntry = parseDnsServerConfig(
          options.directDnsServer,
          tag: 'dns-direct',
          mapIranDefaultToLocal: true,
        ) ??
        <String, dynamic>{
          'type': 'local',
          'tag': 'dns-direct',
        };

    final remoteDnsEntry = parseDnsServerConfig(
          options.remoteDnsServer,
          tag: 'dns-remote',
          detour: 'proxy',
        ) ??
        <String, dynamic>{
          'type': 'udp',
          'tag': 'dns-remote',
          'server': '1.1.1.1',
          'server_port': 53,
          'detour': 'proxy',
        };

    return <String, dynamic>{
      'servers': <Map<String, dynamic>>[
        remoteDnsEntry,
        <String, dynamic>{
          'type': 'local',
          'tag': 'dns-local',
        },
        directDnsEntry,
      ],
      if (directDnsDomains.isNotEmpty)
        'rules': <Map<String, dynamic>>[
          <String, dynamic>{
            'domain_suffix': directDnsDomains,
            'server': 'dns-direct',
          },
        ],
      'strategy': options.enableIpv6 ? 'prefer_ipv6' : 'ipv4_only',
      'final': 'dns-remote',
    };
  }

  static final RegExp _dnsHostnamePattern = RegExp(
    r'^(?=.{1,253}$)(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,63}$',
  );
  static final RegExp _bracketedIpv6WithPortPattern = RegExp(
    r'^\[([^\]]+)\](?::(\d+))?$',
  );

  /// Returns whether [host] is a valid IPv4 or IPv6 address literal.
  static bool isIpLiteral(String host) {
    try {
      Uri.parseIPv4Address(host);
      return true;
    } on FormatException {
      return _tryIsIpv6(host);
    }
  }

  /// Returns whether [raw] is a supported DNS server string (`local`, IP,
  /// `ip:port`, domain, or `udp://` / `tcp://` / `tls://` / `https://` / `h3://`).
  static bool isValidDnsServer(String raw) {
    return parseDnsServerConfig(raw, tag: 'validate') != null;
  }

  /// Parses [raw] into a sing-box DNS server configuration map for [tag],
  /// returning `null` if [raw] is empty or malformed.
  ///
  /// When [detour] is omitted or `'direct'`, no `detour` key is emitted so
  /// sing-box uses its direct dialer without triggering an empty-detour error.
  static Map<String, dynamic>? parseDnsServerConfig(
    String raw, {
    required String tag,
    String? detour,
    bool mapIranDefaultToLocal = false,
  }) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || RegExp(r'\s').hasMatch(trimmed)) {
      return null;
    }

    if (trimmed.toLowerCase() == 'local' ||
        (mapIranDefaultToLocal && trimmed == '178.22.122.100')) {
      return <String, dynamic>{
        'type': 'local',
        'tag': tag,
      };
    }

    final includeProxyDetour =
        detour != null && detour.isNotEmpty && detour != 'direct';

    if (trimmed.contains('://')) {
      final uri = Uri.tryParse(trimmed);
      if (uri == null || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
        return null;
      }
      final scheme = uri.scheme.toLowerCase();
      if (scheme != 'udp' &&
          scheme != 'tcp' &&
          scheme != 'tls' &&
          scheme != 'https' &&
          scheme != 'h3') {
        return null;
      }

      final host = uri.host;
      final isIp = isIpLiteral(host);
      if (!isIp && !_dnsHostnamePattern.hasMatch(host)) {
        return null;
      }
      if (uri.hasPort && (uri.port < 1 || uri.port > 65535)) {
        return null;
      }

      final defaultPort = switch (scheme) {
        'https' || 'h3' => 443,
        'tls' => 853,
        _ => 53,
      };
      final entry = <String, dynamic>{
        'type': scheme,
        'tag': tag,
        'server': host,
        'server_port': uri.hasPort ? uri.port : defaultPort,
      };
      if (scheme == 'https' || scheme == 'h3') {
        final path = uri.path.isEmpty ? '/dns-query' : uri.path;
        entry['path'] = uri.hasQuery ? '$path?${uri.query}' : path;
      }
      if (!isIp) {
        entry['domain_resolver'] = 'dns-local';
      }
      if (includeProxyDetour) {
        entry['detour'] = detour;
      }
      return entry;
    }

    String host;
    var port = 53;
    var isIp = false;

    if (trimmed.startsWith('[')) {
      final match = _bracketedIpv6WithPortPattern.firstMatch(trimmed);
      if (match == null) {
        return null;
      }
      host = match.group(1)!;
      try {
        Uri.parseIPv6Address(host);
        isIp = true;
      } on FormatException {
        return null;
      }
      final portGroup = match.group(2);
      if (portGroup != null) {
        final parsedPort = int.tryParse(portGroup);
        if (parsedPort == null || parsedPort < 1 || parsedPort > 65535) {
          return null;
        }
        port = parsedPort;
      }
    } else if (_tryIsIpv6(trimmed)) {
      host = trimmed;
      isIp = true;
    } else if (trimmed.contains('/')) {
      return null;
    } else if (trimmed.contains(':')) {
      final parts = trimmed.split(':');
      if (parts.length != 2 || parts[0].isEmpty) {
        return null;
      }
      host = parts[0];
      final parsedPort = int.tryParse(parts[1]);
      if (parsedPort == null || parsedPort < 1 || parsedPort > 65535) {
        return null;
      }
      port = parsedPort;
      isIp = isIpLiteral(host);
      if (!isIp && !_dnsHostnamePattern.hasMatch(host)) {
        return null;
      }
    } else {
      host = trimmed;
      isIp = isIpLiteral(host);
      if (!isIp && !_dnsHostnamePattern.hasMatch(host)) {
        return null;
      }
    }

    return <String, dynamic>{
      'type': 'udp',
      'tag': tag,
      'server': host,
      'server_port': port,
      if (!isIp) 'domain_resolver': 'dns-local',
      if (includeProxyDetour) 'detour': detour,
    };
  }

  static bool _tryIsIpv6(String value) {
    try {
      Uri.parseIPv6Address(value);
      return true;
    } on FormatException {
      return false;
    }
  }

  /// Builds a complete sing-box v1.14+ configuration JSON map with local mixed SOCKS5/HTTP + UDP DNS inbounds, outbounds/endpoints, DNS, and routing rules.
  Map<String, dynamic> buildFullConfig(
    ServerProfile profile, {
    SingboxRoutingOptions routingOptions = const SingboxRoutingOptions(),
  }) {
    final isWireguard = profile.protocol.toLowerCase() == 'wireguard';
    final outboundOrEndpoint = buildOutbound(
      profile,
      enableMux: routingOptions.enableMux,
    );
    return <String, dynamic>{
      'log': <String, dynamic>{
        'level': 'info',
        'timestamp': true,
      },
      'dns': buildDnsConfig(routingOptions),
      if (isWireguard)
        'endpoints': <Map<String, dynamic>>[
          outboundOrEndpoint,
        ],
      'inbounds': <Map<String, dynamic>>[
        <String, dynamic>{
          'type': 'mixed',
          'tag': 'mixed-in',
          'listen': '127.0.0.1',
          'listen_port': 2080,
        },
        <String, dynamic>{
          'type': 'direct',
          'tag': 'dns-in',
          'listen': '127.0.0.1',
          'listen_port': 2053,
          'network': 'udp',
        },
      ],
      'outbounds': <Map<String, dynamic>>[
        if (!isWireguard) outboundOrEndpoint,
        <String, dynamic>{
          'type': 'direct',
          'tag': 'direct',
        },
      ],
      'route': <String, dynamic>{
        'rules': buildRoutingRules(routingOptions),
        'final': 'proxy',
        'default_domain_resolver': 'dns-direct',
      },
    };
  }

  Map<String, dynamic> _withAndroidDialerResilience(
    Map<String, dynamic> entry, {
    required bool includeTcpKeepAlive,
  }) {
    return <String, dynamic>{
      ...entry,
      if (!entry.containsKey('connect_timeout')) 'connect_timeout': '10s',
      if (includeTcpKeepAlive) ...<String, dynamic>{
        if (!entry.containsKey('tcp_keep_alive')) 'tcp_keep_alive': '75s',
        if (!entry.containsKey('tcp_keep_alive_interval'))
          'tcp_keep_alive_interval': '20s',
      },
    };
  }

  Map<String, dynamic> _withWireguardKeepalive(Map<String, dynamic> endpoint) {
    final peers = endpoint['peers'];
    if (peers is! List) return endpoint;
    final updatedPeers = <Map<String, dynamic>>[
      for (final rawPeer in peers)
        if (rawPeer is Map<String, dynamic>)
          <String, dynamic>{
            ...rawPeer,
            if (!rawPeer.containsKey('persistent_keepalive_interval'))
              'persistent_keepalive_interval': 25,
          },
    ];
    if (updatedPeers.isEmpty) return endpoint;
    return <String, dynamic>{
      ...endpoint,
      'peers': updatedPeers,
    };
  }

  /// Builds a sing-box v1.14 configuration for Android's native TUN/libbox
  /// path. Unlike [buildFullConfig], this config has no local SOCKS/DNS
  /// inbounds and no `dns-in` route rule.
  Map<String, dynamic> buildAndroidLibboxConfig(
    ServerProfile profile, {
    SingboxRoutingOptions routingOptions = const SingboxRoutingOptions(),
    List<String> tunAddresses = const <String>[
      '172.19.0.1/30',
      'fdfe:dcba:9876::1/126',
    ],
    int mtu = 1400,
    String stack = 'gvisor',
  }) {
    final isWireguard = profile.protocol.toLowerCase() == 'wireguard';
    final outboundOrEndpoint = buildOutbound(
      profile,
      enableMux: routingOptions.enableMux,
    );
    final resilientProxy = isWireguard
        ? _withWireguardKeepalive(outboundOrEndpoint)
        : _withAndroidDialerResilience(
            outboundOrEndpoint,
            includeTcpKeepAlive: true,
          );
    final resilientDirect = _withAndroidDialerResilience(
      <String, dynamic>{
        'type': 'direct',
        'tag': 'direct',
      },
      includeTcpKeepAlive: true,
    );
    final routeRules = buildRoutingRules(routingOptions)
        .where((rule) => rule['inbound'] != 'dns-in')
        .toList(growable: false);

    return <String, dynamic>{
      'log': <String, dynamic>{
        'level': 'warn',
        'timestamp': false,
      },
      'dns': buildDnsConfig(routingOptions),
      if (isWireguard)
        'endpoints': <Map<String, dynamic>>[
          resilientProxy,
        ],
      'inbounds': <Map<String, dynamic>>[
        <String, dynamic>{
          'type': 'tun',
          'tag': 'tun-in',
          'address': tunAddresses,
          'mtu': mtu,
          'auto_route': true,
          'stack': stack,
          'dns_mode': 'hijack',
        },
      ],
      'outbounds': <Map<String, dynamic>>[
        if (!isWireguard) resilientProxy,
        resilientDirect,
      ],
      'route': <String, dynamic>{
        'rules': routeRules,
        'final': 'proxy',
        'auto_detect_interface': true,
        'default_domain_resolver': 'dns-direct',
      },
    };
  }

  static const Set<String> _muxSupportedProtocols = <String>{
    'vless',
    'vmess',
    'trojan',
    'shadowsocks',
  };

  Map<String, dynamic> buildOutbound(
    ServerProfile profile, {
    bool enableMux = false,
  }) {
    final normalizedHost = profile.serverAddress != null
        ? SafeProxyUri.normalizeHost(profile.serverAddress!)
        : null;
    final effectiveProfile =
        (normalizedHost != null && normalizedHost != profile.serverAddress)
            ? profile.copyWith(serverAddress: normalizedHost)
            : profile;

    final protocol = effectiveProfile.protocol.toLowerCase();
    final Map<String, dynamic> outbound;
    switch (protocol) {
      case 'vless':
        outbound = _buildVless(effectiveProfile);
      case 'vmess':
        outbound = _buildVmess(effectiveProfile);
      case 'trojan':
        outbound = _buildTrojan(effectiveProfile);
      case 'shadowsocks':
        outbound = _buildShadowsocks(effectiveProfile);
      case 'hysteria2':
        outbound = _buildHysteria2(effectiveProfile);
      case 'hysteria':
        outbound = _buildHysteria(effectiveProfile);
      case 'tuic':
        outbound = _buildTuic(effectiveProfile);
      case 'anytls':
        outbound = _buildAnyTls(effectiveProfile);
      case 'wireguard':
        outbound = _buildWireguardEndpoint(effectiveProfile);
      default:
        throw SingboxConvertException(
          'پروتکل $protocol توسط مبدل sing-box پشتیبانی نمی‌شود.',
        );
    }

    final flow = _nonEmptyString(profile.extraParams['flow']);
    final hasVisionFlow = flow != null && flow.toLowerCase().contains('vision');
    if (enableMux &&
        _muxSupportedProtocols.contains(protocol) &&
        !hasVisionFlow) {
      outbound['multiplex'] = <String, dynamic>{
        'enabled': true,
        'protocol': 'smux',
        'max_connections': 4,
        'padding': false,
      };
    }

    return outbound;
  }

  Map<String, dynamic> _buildVless(ServerProfile profile) {
    final extra = profile.extraParams;
    final security =
        (_nonEmptyString(extra['security']) ?? 'none').toLowerCase();

    final outbound = <String, dynamic>{
      'type': 'vless',
      'tag': 'proxy',
      'server': profile.serverAddress,
      'server_port': profile.serverPort ?? 443,
      'uuid': _nonEmptyString(extra['uuid']) ?? '',
      'packet_encoding': _nonEmptyString(extra['packetEncoding']) ?? 'xudp',
    };

    final flow = _nonEmptyString(extra['flow']);
    if (flow != null) {
      outbound['flow'] = flow;
    }

    // TLS or Reality
    if (security == 'reality') {
      outbound['tls'] = _buildRealityTls(profile, extra);
    } else if (security == 'tls') {
      outbound['tls'] = _buildStandardTls(profile, extra);
    }

    final transport = _buildV2RayTransport(extra);
    if (transport != null) {
      outbound['transport'] = transport;
      if (transport['type'] == 'quic' && !outbound.containsKey('tls')) {
        outbound['tls'] = _buildStandardTls(profile, extra);
      }
    }

    return outbound;
  }

  Map<String, dynamic> _buildVmess(ServerProfile profile) {
    final extra = profile.extraParams;
    final tlsVal = (_nonEmptyString(extra['tls']) ??
            _nonEmptyString(extra['security']) ??
            '')
        .toLowerCase();
    final isTls = tlsVal == 'tls';

    final outbound = <String, dynamic>{
      'type': 'vmess',
      'tag': 'proxy',
      'server': profile.serverAddress,
      'server_port': profile.serverPort ?? 443,
      'uuid': _nonEmptyString(extra['uuid']) ?? '',
      'security': _nonEmptyString(extra['scy']) ??
          (_nonEmptyString(extra['security']) != 'tls'
              ? (_nonEmptyString(extra['security']) ?? 'auto')
              : 'auto'),
      'alter_id': _parseInt(extra['alterId'] ?? extra['aid'], fallback: 0),
      'packet_encoding': _nonEmptyString(extra['packetEncoding']) ?? 'xudp',
    };

    if (isTls) {
      outbound['tls'] = _buildStandardTls(profile, extra);
    }

    final transport = _buildV2RayTransport(extra);
    if (transport != null) {
      outbound['transport'] = transport;
      if (transport['type'] == 'quic' && !outbound.containsKey('tls')) {
        outbound['tls'] = _buildStandardTls(profile, extra);
      }
    }

    return outbound;
  }

  Map<String, dynamic> _buildTrojan(ServerProfile profile) {
    final extra = profile.extraParams;
    final security =
        (_nonEmptyString(extra['security']) ?? 'tls').toLowerCase();
    final outbound = <String, dynamic>{
      'type': 'trojan',
      'tag': 'proxy',
      'server': profile.serverAddress,
      'server_port': profile.serverPort ?? 443,
      'password': _nonEmptyString(extra['password']) ?? '',
    };

    if (security == 'reality') {
      outbound['tls'] = _buildRealityTls(profile, extra);
    } else if (security != 'none') {
      outbound['tls'] = _buildStandardTls(profile, extra);
    }

    final transport = _buildV2RayTransport(extra);
    if (transport != null) {
      outbound['transport'] = transport;
      if (transport['type'] == 'quic' && !outbound.containsKey('tls')) {
        outbound['tls'] = _buildStandardTls(profile, extra);
      }
    }

    return outbound;
  }

  Map<String, dynamic> _buildShadowsocks(ServerProfile profile) {
    final extra = profile.extraParams;
    final outbound = <String, dynamic>{
      'type': 'shadowsocks',
      'tag': 'proxy',
      'server': profile.serverAddress,
      'server_port': profile.serverPort ?? 8388,
      'method': _nonEmptyString(extra['method']) ?? 'aes-256-gcm',
      'password': _nonEmptyString(extra['password']) ?? '',
    };

    final rawPlugin = _nonEmptyString(extra['plugin']);
    final explicitPluginOpts = _nonEmptyString(extra['pluginOpts']);
    if (rawPlugin != null) {
      String pluginName = rawPlugin;
      String? pluginOpts = explicitPluginOpts;
      if (rawPlugin.contains(';')) {
        final parts = rawPlugin.split(';');
        pluginName = parts.first.trim();
        pluginOpts = parts.sublist(1).join(';').trim();
      }
      if (pluginName == 'simple-obfs' || pluginName == 'obfs') {
        pluginName = 'obfs-local';
      }
      if (pluginName.isNotEmpty) {
        outbound['plugin'] = pluginName;
        if (pluginOpts != null && pluginOpts.isNotEmpty) {
          outbound['plugin_opts'] = pluginOpts;
        }
      }
    }

    if (extra['udpOverTcp'] == true ||
        extra['uot'] == true ||
        extra['uot'] == '1') {
      outbound['udp_over_tcp'] = true;
    }

    return outbound;
  }

  Map<String, dynamic> _buildHysteria2(ServerProfile profile) {
    final extra = profile.extraParams;
    final sni = _nonEmptyString(extra['sni']);
    final auth =
        _nonEmptyString(extra['auth']) ?? _nonEmptyString(extra['password']);
    final obfs = _nonEmptyString(extra['obfs']);
    final obfsPassword = _nonEmptyString(extra['obfsPassword']);
    final alpn = _alpnList(extra['alpn']);
    final upMbps = _parseInt(extra['upMbps'] ?? extra['up'], fallback: 0);
    final downMbps = _parseInt(extra['downMbps'] ?? extra['down'], fallback: 0);
    final serverPorts = _normalizeHysteriaServerPorts(extra['mport']);

    final outbound = <String, dynamic>{
      'type': 'hysteria2',
      'tag': 'proxy',
      'server': profile.serverAddress,
      'server_port': profile.serverPort ?? 443,
      if (serverPorts != null && serverPorts.isNotEmpty)
        'server_ports': serverPorts,
      if (upMbps > 0) 'up_mbps': upMbps,
      if (downMbps > 0) 'down_mbps': downMbps,
      if (auth != null) 'password': auth,
      'tls': <String, dynamic>{
        'enabled': true,
        if (sni != null) 'server_name': sni,
        if (alpn != null && alpn.isNotEmpty) 'alpn': alpn,
        'insecure': extra['insecure'] == true ||
            extra['insecure'] == '1' ||
            extra['allowInsecure'] == true ||
            extra['allowInsecure'] == '1',
      },
    };

    if (obfs != null) {
      outbound['obfs'] = <String, dynamic>{
        'type': obfs,
        if (obfsPassword != null) 'password': obfsPassword,
      };
    }

    return outbound;
  }

  Map<String, dynamic> _buildHysteria(ServerProfile profile) {
    final extra = profile.extraParams;
    final sni = _nonEmptyString(extra['sni']) ?? _nonEmptyString(extra['peer']);
    final auth =
        _nonEmptyString(extra['auth']) ?? _nonEmptyString(extra['auth_str']);
    final obfs = _nonEmptyString(extra['obfs']);
    final upMbps = _parseInt(extra['upMbps'] ?? extra['up'], fallback: 0);
    final downMbps = _parseInt(
      extra['downMbps'] ?? extra['down'],
      fallback: 0,
    );
    final alpn = _alpnList(extra['alpn']);
    final insecure = extra['insecure'] == true ||
        extra['insecure'] == '1' ||
        extra['allowInsecure'] == true ||
        extra['allowInsecure'] == '1';

    return <String, dynamic>{
      'type': 'hysteria',
      'tag': 'proxy',
      'server': profile.serverAddress,
      'server_port': profile.serverPort ?? 443,
      if (upMbps > 0) 'up_mbps': upMbps,
      if (downMbps > 0) 'down_mbps': downMbps,
      if (auth != null) 'auth_str': auth,
      if (obfs != null) 'obfs': obfs,
      'tls': <String, dynamic>{
        'enabled': true,
        if (sni != null) 'server_name': sni,
        if (alpn != null && alpn.isNotEmpty) 'alpn': alpn,
        if (insecure) 'insecure': true,
      },
    };
  }

  Map<String, dynamic> _buildTuic(ServerProfile profile) {
    final extra = profile.extraParams;
    final sni = _nonEmptyString(extra['sni']);
    final alpn = _alpnList(extra['alpn']) ?? const <String>['h3'];
    final congestionControl = _nonEmptyString(extra['congestionControl']) ??
        _nonEmptyString(extra['congestion_control']);
    final udpRelayMode = _nonEmptyString(extra['udpRelayMode']) ??
        _nonEmptyString(extra['udp_relay_mode']);
    final insecure = extra['insecure'] == true ||
        extra['insecure'] == '1' ||
        extra['allowInsecure'] == true ||
        extra['allowInsecure'] == '1';

    return <String, dynamic>{
      'type': 'tuic',
      'tag': 'proxy',
      'server': profile.serverAddress,
      'server_port': profile.serverPort ?? 443,
      'uuid': _nonEmptyString(extra['uuid']) ?? '',
      'password': _nonEmptyString(extra['password']) ?? '',
      if (congestionControl != null) 'congestion_control': congestionControl,
      if (udpRelayMode != null) 'udp_relay_mode': udpRelayMode,
      if (extra['udpOverStream'] == true) 'udp_over_stream': true,
      if (extra['zeroRttHandshake'] == true) 'zero_rtt_handshake': true,
      'tls': <String, dynamic>{
        'enabled': true,
        if (sni != null) 'server_name': sni,
        'alpn': alpn,
        if (insecure) 'insecure': true,
      },
    };
  }

  Map<String, dynamic> _buildAnyTls(ServerProfile profile) {
    final extra = profile.extraParams;
    final sni = _nonEmptyString(extra['sni']);
    final alpn = _alpnList(extra['alpn']);
    final insecure = extra['insecure'] == true ||
        extra['insecure'] == '1' ||
        extra['allowInsecure'] == true ||
        extra['allowInsecure'] == '1';

    return <String, dynamic>{
      'type': 'anytls',
      'tag': 'proxy',
      'server': profile.serverAddress,
      'server_port': profile.serverPort ?? 443,
      'password': _nonEmptyString(extra['password']) ?? '',
      'tls': <String, dynamic>{
        'enabled': true,
        if (sni != null) 'server_name': sni,
        if (alpn != null && alpn.isNotEmpty) 'alpn': alpn,
        if (insecure) 'insecure': true,
      },
    };
  }

  Map<String, dynamic> _buildWireguardEndpoint(ServerProfile profile) {
    final extra = profile.extraParams;
    final privateKey = _nonEmptyString(extra['privateKey']) ??
        _nonEmptyString(extra['private_key']) ??
        '';
    final publicKey = _nonEmptyString(extra['publicKey']) ??
        _nonEmptyString(extra['public_key']) ??
        _nonEmptyString(extra['peer_public_key']) ??
        '';
    final preSharedKey = _nonEmptyString(extra['preSharedKey']) ??
        _nonEmptyString(extra['pre_shared_key']) ??
        _nonEmptyString(extra['presharedKey']);
    final addresses = WireguardParser.normalizeAddressList(
      extra['localAddress'] ?? extra['address'] ?? '172.16.0.2/32',
    );
    final mtu = _parseInt(extra['mtu'], fallback: 1408);
    final reserved = WireguardParser.parseReserved(extra['reserved']);

    return <String, dynamic>{
      'type': 'wireguard',
      'tag': 'proxy',
      'address': addresses,
      'private_key': privateKey,
      'mtu': mtu > 0 ? mtu : 1408,
      'peers': <Map<String, dynamic>>[
        <String, dynamic>{
          'address': profile.serverAddress,
          'port': profile.serverPort ?? 51820,
          'public_key': publicKey,
          if (preSharedKey != null) 'pre_shared_key': preSharedKey,
          'allowed_ips': const <String>['0.0.0.0/0', '::/0'],
          if (reserved != null) 'reserved': reserved,
        },
      ],
    };
  }

  Map<String, dynamic> _buildRealityTls(
    ServerProfile profile,
    Map<String, dynamic> extra,
  ) {
    final rawSni = _nonEmptyString(extra['sni']) ??
        _nonEmptyString(extra['host']) ??
        profile.serverAddress;
    final sni = rawSni != null ? SafeProxyUri.normalizeHost(rawSni) : null;
    final fp = _nonEmptyString(extra['fingerprint']) ??
        _nonEmptyString(extra['fp']) ??
        'chrome';
    final sid = _nonEmptyString(extra['sid']);
    final rawPbk = _nonEmptyString(extra['pbk']) ?? '';
    final normalizedPbk = rawPbk
        .replaceAll('+', '-')
        .replaceAll('/', '_')
        .replaceAll(RegExp(r'=+$'), '');

    return <String, dynamic>{
      'enabled': true,
      'server_name': sni,
      'utls': <String, dynamic>{
        'enabled': true,
        'fingerprint': fp,
      },
      'reality': <String, dynamic>{
        'enabled': true,
        'public_key': normalizedPbk,
        if (sid != null) 'short_id': sid,
      },
    };
  }

  List<String>? _normalizeHysteriaServerPorts(dynamic raw) {
    final value = _nonEmptyString(raw);
    if (value == null) return null;
    final ports = <String>[];
    for (final part in value.split(',')) {
      final clean = part.trim().replaceAll('-', ':');
      if (RegExp(r'^\d+(?::\d+)?$').hasMatch(clean)) {
        ports.add(clean);
      }
    }
    return ports.isEmpty ? null : ports;
  }

  List<String>? _alpnList(dynamic raw) {
    final value = _nonEmptyString(raw);
    if (value == null) return null;
    final list = value
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return list.isEmpty ? null : list;
  }

  Map<String, dynamic> _buildStandardTls(
    ServerProfile profile,
    Map<String, dynamic> extra,
  ) {
    final rawSni = _nonEmptyString(extra['sni']) ??
        _nonEmptyString(extra['host']) ??
        profile.serverAddress;
    final sni = rawSni != null ? SafeProxyUri.normalizeHost(rawSni) : null;
    final fp =
        _nonEmptyString(extra['fingerprint']) ?? _nonEmptyString(extra['fp']);
    final alpnRaw = _nonEmptyString(extra['alpn']);
    final alpnList = alpnRaw
        ?.split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final insecure = extra['allowInsecure'] == true ||
        extra['allowInsecure'] == '1' ||
        extra['insecure'] == true ||
        extra['insecure'] == '1';

    return <String, dynamic>{
      'enabled': true,
      'server_name': sni,
      if (insecure) 'insecure': true,
      if (alpnList != null && alpnList.isNotEmpty) 'alpn': alpnList,
      if (fp != null)
        'utls': <String, dynamic>{
          'enabled': true,
          'fingerprint': fp,
        },
    };
  }

  Map<String, dynamic>? _buildV2RayTransport(Map<String, dynamic> extra) {
    final transportType =
        (_nonEmptyString(extra['transportType']) ?? 'tcp').toLowerCase();
    final headerType =
        (_nonEmptyString(extra['headerType']) ?? 'none').toLowerCase();
    final host = _nonEmptyString(extra['host']);
    final rawPath = _nonEmptyString(extra['path']);

    if (transportType == 'ws' || transportType == 'websocket') {
      var cleanPath = rawPath ?? '/';
      int? maxEarlyData;

      // Extract ?ed=2048 or &ed=2048 from WebSocket path if present
      final edMatch = RegExp(r'[?&]ed=(\d+)').firstMatch(cleanPath);
      if (edMatch != null) {
        maxEarlyData = int.tryParse(edMatch.group(1)!);
        cleanPath = cleanPath.replaceFirst(RegExp(r'[?&]ed=\d+'), '');
        if (cleanPath.isEmpty) {
          cleanPath = '/';
        }
      } else if (extra['ed'] != null) {
        maxEarlyData = _parseInt(extra['ed'], fallback: 0);
        if (maxEarlyData <= 0) {
          maxEarlyData = null;
        }
      }

      return <String, dynamic>{
        'type': 'ws',
        'path': cleanPath,
        if (host != null) 'headers': <String, String>{'Host': host},
        if (maxEarlyData != null && maxEarlyData > 0) ...<String, dynamic>{
          'max_early_data': maxEarlyData,
          'early_data_header_name': 'Sec-WebSocket-Protocol',
        },
      };
    }

    if (transportType == 'grpc') {
      final serviceName = _nonEmptyString(extra['serviceName']) ?? rawPath;
      return <String, dynamic>{
        'type': 'grpc',
        if (serviceName != null) 'service_name': serviceName,
      };
    }

    if (transportType == 'httpupgrade') {
      return <String, dynamic>{
        'type': 'httpupgrade',
        'path': rawPath ?? '/',
        if (host != null) 'host': host,
      };
    }

    if (transportType == 'quic') {
      return <String, dynamic>{
        'type': 'quic',
      };
    }

    if (transportType == 'http' ||
        transportType == 'h2' ||
        (transportType == 'tcp' && headerType == 'http')) {
      final hosts = host
          ?.split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      return <String, dynamic>{
        'type': 'http',
        'path': rawPath ?? '/',
        if (hosts != null && hosts.isNotEmpty) 'host': hosts,
      };
    }

    return null;
  }

  static String? _nonEmptyString(dynamic value) {
    if (value == null) return null;
    final str = value.toString().trim();
    return str.isEmpty ? null : str;
  }

  static int _parseInt(dynamic value, {required int fallback}) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value.trim()) ?? fallback;
    return fallback;
  }
}
