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
      expect(tun['mtu'], equals(9000));
      expect(tun['auto_route'], isTrue);
      expect(tun.containsKey('auto_redirect'), isFalse);
      expect(tun['stack'], equals('mixed'));
      expect(tun['dns_mode'], equals('hijack'));
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
      expect(route['override_android_vpn'], isTrue);
      expect(rules.any((rule) => rule['action'] == 'sniff'), isTrue);
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
  });
}
