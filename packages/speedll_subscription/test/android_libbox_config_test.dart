import 'package:test/test.dart';
import 'package:speedll_subscription/speedll_subscription.dart';

void main() {
  group('Android libbox TUN configuration', () {
    const converter = SingboxConverter();

    const profile = ServerProfile(
      id: 'android-libbox-test',
      displayName: 'Android libbox test',
      protocol: 'vless',
      source: ProfileSource.manual,
      serverAddress: '198.51.100.10',
      serverPort: 443,
      extraParams: <String, dynamic>{
        'uuid': '00000000-0000-0000-0000-000000000001',
        'security': 'reality',
        'pbk': '1111111111111111111111111111111111111111111=',
      },
    );

    test('emits a single native TUN inbound', () {
      final config = converter.buildAndroidLibboxConfig(profile);
      final inbounds = config['inbounds'] as List<Map<String, dynamic>>;

      expect(inbounds, hasLength(1));
      final tun = inbounds.single;
      expect(tun['type'], equals('tun'));
      expect(tun['tag'], equals('tun-in'));
      expect(
        tun['address'],
        equals(<String>['172.19.0.1/30', 'fdfe:dcba:9876::1/126']),
      );
      expect(tun['mtu'], equals(1400));
      expect(tun['auto_route'], isTrue);
      expect(tun.containsKey('auto_redirect'), isFalse);
      expect(tun['stack'], equals('gvisor'));
      expect(tun['dns_mode'], equals('hijack'));

      final outbounds = config['outbounds'] as List<Map<String, dynamic>>;
      final proxyOutbound = outbounds.firstWhere((o) => o['tag'] == 'proxy');
      final directOutbound = outbounds.firstWhere((o) => o['tag'] == 'direct');
      expect(proxyOutbound['connect_timeout'], equals('10s'));
      expect(proxyOutbound['tcp_keep_alive'], equals('75s'));
      expect(proxyOutbound['tcp_keep_alive_interval'], equals('20s'));
      expect(directOutbound['connect_timeout'], equals('10s'));
      expect(directOutbound['tcp_keep_alive'], equals('75s'));
      expect(directOutbound['tcp_keep_alive_interval'], equals('20s'));
      expect(
        inbounds.any((inbound) => inbound['type'] == 'mixed'),
        isFalse,
      );
      expect(
        inbounds.any((inbound) => inbound['tag'] == 'dns-in'),
        isFalse,
      );
    });

    test('keeps DNS hijack and routing without a dns-in inbound rule', () {
      final config = converter.buildAndroidLibboxConfig(
        profile,
        routingOptions: const SingboxRoutingOptions(
          bypassLan: true,
          bypassIranDomains: true,
          customDirectDomains: <String>['bank.test.ir'],
        ),
      );
      final route = config['route'] as Map<String, dynamic>;
      final rules = route['rules'] as List<Map<String, dynamic>>;

      expect(route['final'], equals('proxy'));
      expect(route['auto_detect_interface'], isTrue);
      expect(route['default_domain_resolver'], equals('dns-direct'));
      expect(route.containsKey('override_android_vpn'), isFalse);
      expect(rules.any((rule) => rule['action'] == 'sniff'), isFalse);
      expect(
        rules.any(
          (rule) =>
              rule['port'] is List &&
              (rule['port'] as List).contains(53) &&
              rule['action'] == 'hijack-dns',
        ),
        isTrue,
      );
      expect(
        rules.any(
          (rule) => rule['protocol'] == 'dns' && rule['action'] == 'hijack-dns',
        ),
        isTrue,
      );
      expect(
        rules.any((rule) => rule['inbound'] == 'dns-in'),
        isFalse,
      );
      expect(
        rules.any(
          (rule) =>
              rule['domain_suffix'] is List &&
              (rule['domain_suffix'] as List).contains('.ir') &&
              rule['outbound'] == 'direct',
        ),
        isTrue,
      );
    });

    test('uses low-noise logging by default', () {
      final config = converter.buildAndroidLibboxConfig(profile);
      final log = config['log'] as Map<String, dynamic>;

      expect(log['level'], equals('warn'));
      expect(log['timestamp'], isFalse);
    });

    test('supports WireGuard endpoints and configurable TUN settings', () {
      const wireguardProfile = ServerProfile(
        id: 'android-libbox-wireguard',
        displayName: 'Android libbox WireGuard',
        protocol: 'wireguard',
        source: ProfileSource.manual,
        serverAddress: '198.51.100.120',
        serverPort: 51820,
        extraParams: <String, dynamic>{
          'privateKey': 'cHJpdmF0ZV9rZXlfYmFzZTY0X3Rlc3RfMTIzNDU2Nzg=',
          'publicKey': 'cHVibGljX2tleV9iYXNlNjRfdGVzdF8xMjM0NTY3OA==',
          'address': '10.0.0.2/32',
        },
      );

      final config = converter.buildAndroidLibboxConfig(
        wireguardProfile,
        tunAddresses: const <String>['172.20.0.1/30'],
        mtu: 1380,
        stack: 'gvisor',
      );
      final tun = (config['inbounds'] as List).single as Map<String, dynamic>;

      expect(tun['address'], equals(<String>['172.20.0.1/30']));
      expect(tun['mtu'], equals(1380));
      expect(tun['stack'], equals('gvisor'));
      expect(config.containsKey('endpoints'), isTrue);
      final endpoints = config['endpoints'] as List<Map<String, dynamic>>;
      final peers = endpoints.first['peers'] as List<Map<String, dynamic>>;
      expect(peers.first['persistent_keepalive_interval'], equals(25));
      expect(
        (config['outbounds'] as List)
            .where((outbound) => (outbound as Map)['tag'] == 'proxy'),
        isEmpty,
      );
    });

    test('configures multiplex with padding=false and no min_streams', () {
      final config = converter.buildAndroidLibboxConfig(
        profile,
        routingOptions: const SingboxRoutingOptions(enableMux: true),
      );
      final proxy =
          (config['outbounds'] as List).first as Map<String, dynamic>;
      final multiplex = proxy['multiplex'] as Map<String, dynamic>;

      expect(multiplex['enabled'], isTrue);
      expect(multiplex['protocol'], equals('smux'));
      expect(multiplex['max_connections'], equals(4));
      expect(multiplex['padding'], isFalse);
      expect(multiplex.containsKey('min_streams'), isFalse);
    });

    test(
      'places hijack-dns before scoped sniff rule when traffic sniffing is enabled',
      () {
        final config = converter.buildAndroidLibboxConfig(
          profile,
          routingOptions: const SingboxRoutingOptions(
            enableTrafficSniffing: true,
          ),
        );
        final route = config['route'] as Map<String, dynamic>;
        final rules = route['rules'] as List<Map<String, dynamic>>;

        final port53Idx = rules.indexWhere(
          (r) =>
              r['port'] is List &&
              (r['port'] as List).contains(53) &&
              r['action'] == 'hijack-dns',
        );
        final protocolDnsIdx = rules.indexWhere(
          (r) => r['protocol'] == 'dns' && r['action'] == 'hijack-dns',
        );
        final sniffIdx = rules.indexWhere((r) => r['action'] == 'sniff');

        expect(port53Idx, greaterThanOrEqualTo(0));
        expect(protocolDnsIdx, greaterThanOrEqualTo(0));
        expect(sniffIdx, greaterThan(port53Idx));
        expect(sniffIdx, greaterThan(protocolDnsIdx));
        expect(
          rules[sniffIdx]['sniffer'],
          equals(<String>['tls', 'http', 'quic']),
        );
        expect(rules[sniffIdx]['timeout'], equals('100ms'));
      },
    );

    test(
      'never emits detour:direct on dns-local or custom dns-direct servers',
      () {
        for (final directDns in const <String>[
          '178.22.122.100',
          '8.8.8.8',
          '1.1.1.1',
          '185.51.200.2',
          '10.202.10.202',
          '10.202.10.11',
          'local',
          'tls://dns.google',
          'https://dns.google/dns-query',
        ]) {
          final config = converter.buildAndroidLibboxConfig(
            profile,
            routingOptions: SingboxRoutingOptions(
              remoteDnsServer: '8.8.8.8',
              directDnsServer: directDns,
            ),
          );
          final dns = config['dns'] as Map<String, dynamic>;
          final servers = dns['servers'] as List<Map<String, dynamic>>;
          final remote = servers.firstWhere((s) => s['tag'] == 'dns-remote');
          final local = servers.firstWhere((s) => s['tag'] == 'dns-local');
          final direct = servers.firstWhere((s) => s['tag'] == 'dns-direct');

          expect(remote['detour'], equals('proxy'), reason: directDns);
          expect(local.containsKey('detour'), isFalse, reason: directDns);
          expect(direct.containsKey('detour'), isFalse, reason: directDns);
        }
      },
    );

    test(
      'sets dns strategy to ipv4_only when enableIpv6 is false and prefer_ipv6 when true',
      () {
        final v4OnlyConfig = converter.buildAndroidLibboxConfig(
          profile,
          routingOptions: const SingboxRoutingOptions(enableIpv6: false),
        );
        expect(
          (v4OnlyConfig['dns'] as Map<String, dynamic>)['strategy'],
          equals('ipv4_only'),
        );

        final v6EnabledConfig = converter.buildAndroidLibboxConfig(
          profile,
          routingOptions: const SingboxRoutingOptions(
            enableIpv6: true,
            remoteDnsServer: '2606:4700:4700::1111',
            directDnsServer: '2001:4860:4860::8888',
          ),
        );
        final v6Dns = v6EnabledConfig['dns'] as Map<String, dynamic>;
        expect(v6Dns['strategy'], equals('prefer_ipv6'));

        final servers = v6Dns['servers'] as List<Map<String, dynamic>>;
        final remote = servers.firstWhere((s) => s['tag'] == 'dns-remote');
        final direct = servers.firstWhere((s) => s['tag'] == 'dns-direct');
        expect(remote['server'], equals('2606:4700:4700::1111'));
        expect(direct['server'], equals('2001:4860:4860::8888'));

        final inbounds = v6EnabledConfig['inbounds'] as List<Map<String, dynamic>>;
        final tun = inbounds.firstWhere((i) => i['type'] == 'tun');
        expect(
          tun['address'],
          equals(const <String>['172.19.0.1/30', 'fdfe:dcba:9876::1/126']),
        );
      },
    );

    test('strips IPv6 brackets from outbound and WireGuard endpoint addresses', () {
      const ipv6Vless = ServerProfile(
        id: 'ipv6-vless-1',
        protocol: 'vless',
        source: ProfileSource.manual,
        displayName: 'v6',
        serverAddress: '[2001:db8::42]',
        serverPort: 443,
        extraParams: <String, dynamic>{
          'uuid': '11111111-1111-1111-1111-111111111111',
          'security': 'tls',
          'sni': '[2001:db8::42]',
        },
      );
      final vlessOut = converter.buildOutbound(ipv6Vless);
      expect(vlessOut['server'], equals('2001:db8::42'));
      expect(
        (vlessOut['tls'] as Map<String, dynamic>)['server_name'],
        equals('2001:db8::42'),
      );

      const ipv6Wg = ServerProfile(
        id: 'ipv6-wg-1',
        protocol: 'wireguard',
        source: ProfileSource.manual,
        displayName: 'wg-v6',
        serverAddress: '[2001:db8::99]',
        serverPort: 51820,
        extraParams: <String, dynamic>{
          'privateKey': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
          'publicKey': 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=',
          'localAddress': '10.0.0.2/32, fd00::2/128',
        },
      );
      final wgConfig = converter.buildAndroidLibboxConfig(ipv6Wg);
      final endpoints = wgConfig['endpoints'] as List<Map<String, dynamic>>;
      final peers = endpoints.first['peers'] as List<Map<String, dynamic>>;
      expect(peers.first['address'], equals('2001:db8::99'));
      expect(
        endpoints.first['address'],
        equals(const <String>['10.0.0.2/32', 'fd00::2/128']),
      );
    });
  });
}
