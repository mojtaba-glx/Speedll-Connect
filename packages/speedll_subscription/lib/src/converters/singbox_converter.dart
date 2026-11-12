import '../models/server_profile.dart';
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
    this.enableTrafficSniffing = true,
    this.enableMux = false,
    this.killSwitch = false,
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
      if (options.enableTrafficSniffing)
        <String, dynamic>{
          'action': 'sniff',
        },
      <String, dynamic>{
        'inbound': 'dns-in',
        'action': 'hijack-dns',
      },
      <String, dynamic>{
        'protocol': 'dns',
        'action': 'hijack-dns',
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

    return <String, dynamic>{
      'servers': <Map<String, dynamic>>[
        <String, dynamic>{
          'type': 'tcp',
          'tag': 'dns-remote',
          'server': options.remoteDnsServer.trim().isNotEmpty
              ? options.remoteDnsServer.trim()
              : '1.1.1.1',
          'server_port': 53,
          'detour': 'proxy',
        },
        <String, dynamic>{
          'type': 'udp',
          'tag': 'dns-direct',
          'server': options.directDnsServer.trim().isNotEmpty
              ? options.directDnsServer.trim()
              : '178.22.122.100',
          'server_port': 53,
        },
      ],
      if (directDnsDomains.isNotEmpty)
        'rules': <Map<String, dynamic>>[
          <String, dynamic>{
            'domain_suffix': directDnsDomains,
            'server': 'dns-direct',
          },
        ],
      'strategy': 'ipv4_only',
      'final': 'dns-remote',
    };
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
    int mtu = 9000,
    String stack = 'mixed',
  }) {
    final isWireguard = profile.protocol.toLowerCase() == 'wireguard';
    final outboundOrEndpoint = buildOutbound(
      profile,
      enableMux: routingOptions.enableMux,
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
          outboundOrEndpoint,
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
        if (!isWireguard) outboundOrEndpoint,
        <String, dynamic>{
          'type': 'direct',
          'tag': 'direct',
        },
      ],
      'route': <String, dynamic>{
        'rules': routeRules,
        'final': 'proxy',
        'auto_detect_interface': true,
        'default_domain_resolver': 'dns-direct',
        'override_android_vpn': true,
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
    final protocol = profile.protocol.toLowerCase();
    final Map<String, dynamic> outbound;
    switch (protocol) {
      case 'vless':
        outbound = _buildVless(profile);
      case 'vmess':
        outbound = _buildVmess(profile);
      case 'trojan':
        outbound = _buildTrojan(profile);
      case 'shadowsocks':
        outbound = _buildShadowsocks(profile);
      case 'hysteria2':
        outbound = _buildHysteria2(profile);
      case 'hysteria':
        outbound = _buildHysteria(profile);
      case 'tuic':
        outbound = _buildTuic(profile);
      case 'anytls':
        outbound = _buildAnyTls(profile);
      case 'wireguard':
        outbound = _buildWireguardEndpoint(profile);
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
    final sni = _nonEmptyString(extra['sni']) ??
        _nonEmptyString(extra['host']) ??
        profile.serverAddress;
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
    final sni = _nonEmptyString(extra['sni']) ??
        _nonEmptyString(extra['host']) ??
        profile.serverAddress;
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
