import 'dart:convert';
import 'package:test/test.dart';
import 'package:speedll_subscription/speedll_subscription.dart';

void main() {
  group('Iran bypass and mux behavior', () {
    const converter = SingboxConverter();

    test('Only the .ir suffix is bypassed (not bare "ir")', () {
      final rules = converter.buildRoutingRules(
        const SingboxRoutingOptions(bypassIranDomains: true),
      );
      final irRule = rules.firstWhere(
        (rule) =>
            rule['domain_suffix'] is List &&
            (rule['domain_suffix'] as List).contains('.ir'),
      );
      final suffixes = (irRule['domain_suffix'] as List).cast<String>();
      expect(suffixes, contains('.ir'));
      expect(suffixes, isNot(contains('ir')));
    });

    test('Mux is emitted in outbound only when enabled', () {
      const profile = ServerProfile(
        id: 'p1',
        displayName: 'Mux Test',
        protocol: 'vless',
        source: ProfileSource.manual,
        serverAddress: '198.51.100.10',
        serverPort: 443,
        extraParams: <String, dynamic>{
          'uuid': '00000000-0000-0000-0000-000000000001',
          'security': 'none',
        },
      );

      final disabled = converter.buildFullConfig(profile);
      final disabledProxy = (disabled['outbounds'] as List).first
          as Map<String, dynamic>;
      expect(disabledProxy.containsKey('multiplex'), isFalse);

      final enabled = converter.buildFullConfig(
        profile,
        routingOptions: const SingboxRoutingOptions(enableMux: true),
      );
      final enabledProxy = (enabled['outbounds'] as List).first
          as Map<String, dynamic>;
      final multiplex = enabledProxy['multiplex'] as Map<String, dynamic>;
      expect(multiplex['enabled'], isTrue);
      expect(multiplex['protocol'], equals('smux'));
    });
  });

  group('New protocol parsers and outbound conversion', () {
    const converter = SingboxConverter();

    test('Parses TUIC URI and builds a valid outbound', () async {
      const uri =
          'tuic://00000000-0000-0000-0000-000000000002:sample_pass@198.51.100.60:443?congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=tuic.example.com&allow_insecure=1#TUIC-Test';
      const parser = TuicParser();
      expect(parser.canParse(uri), isTrue);

      final result = await parser.parse(uri);
      expect(result.isSuccess, isTrue);
      final profile = result.profiles.first;
      expect(profile.protocol, equals('tuic'));
      expect(profile.extraParams['uuid'],
          equals('00000000-0000-0000-0000-000000000002'));

      final outbound = converter.buildOutbound(profile);
      expect(outbound['type'], equals('tuic'));
      expect(outbound['password'], equals('sample_pass'));
      expect((outbound['tls'] as Map)['enabled'], isTrue);
      expect((outbound['tls'] as Map)['insecure'], isTrue);
    });

    test('Parses AnyTLS URI and builds a valid outbound', () async {
      const uri =
          'anytls://sample_password@198.51.100.70:443?sni=anytls.example.com&insecure=1#AnyTLS-Test';
      const parser = AnyTlsParser();
      expect(parser.canParse(uri), isTrue);

      final result = await parser.parse(uri);
      expect(result.isSuccess, isTrue);
      final profile = result.profiles.first;
      expect(profile.protocol, equals('anytls'));

      final outbound = converter.buildOutbound(profile);
      expect(outbound['type'], equals('anytls'));
      expect(outbound['password'], equals('sample_password'));
      expect((outbound['tls'] as Map)['server_name'],
          equals('anytls.example.com'));
    });

    test('Parses Hysteria v1 URI and builds a valid outbound', () async {
      const uri =
          'hysteria://198.51.100.80:443?auth=sample_auth&peer=hy.example.com&insecure=1&upmbps=50&downmbps=100&obfs=xplus&obfsParam=obfs_pass#Hysteria-Test';
      const parser = HysteriaParser();
      expect(parser.canParse(uri), isTrue);

      final result = await parser.parse(uri);
      expect(result.isSuccess, isTrue);
      final profile = result.profiles.first;
      expect(profile.protocol, equals('hysteria'));

      final outbound = converter.buildOutbound(profile);
      expect(outbound['type'], equals('hysteria'));
      expect(outbound['auth_str'], equals('sample_auth'));
      expect(outbound['up_mbps'], equals(50));
      expect(outbound['down_mbps'], equals(100));
      expect(outbound['obfs'], equals('xplus'));
    });

    test('Rejects malformed TUIC and AnyTLS links gracefully', () async {
      final tuic = await const TuicParser().parse('tuic://@:443');
      expect(tuic.isSuccess, isFalse);

      final anytls = await const AnyTlsParser().parse('anytls://@:443');
      expect(anytls.isSuccess, isFalse);

      final hysteria = await const HysteriaParser().parse('hysteria://');
      expect(hysteria.isSuccess, isFalse);
    });
  });

  group('Clash YAML and sing-box JSON subscriptions', () {
    const detector = SubscriptionDetector();

    test('Detects and parses Clash YAML proxies', () async {
      const yaml = '''
proxies:
  - name: "Clash VLESS"
    type: vless
    server: 198.51.100.90
    port: 443
    uuid: 00000000-0000-0000-0000-000000000003
    tls: true
    servername: clash.example.com
    network: ws
    ws-opts:
      path: /ws
      headers:
        Host: cdn.example.com
    reality-opts:
      public-key: 1111111111111111111111111111111111111111111=
      short-id: abcd
    client-fingerprint: chrome
  - name: "Clash Hy2"
    type: hysteria2
    server: 198.51.100.91
    port: 8443
    password: sample_hy2_pass
    sni: hy2.example.com
    skip-cert-verify: true
  - name: "Unsupported SSR"
    type: ssr
    server: 198.51.100.92
    port: 9000
''';

      final result = await detector.detectAndParse(yaml);
      expect(result.isSuccess, isTrue);
      expect(result.profiles.length, equals(2));

      final vless = result.profiles.firstWhere((p) => p.protocol == 'vless');
      expect(vless.extraParams['security'], equals('reality'));
      expect(vless.extraParams['transportType'], equals('ws'));
      expect(vless.extraParams['path'], equals('/ws'));
      expect(vless.extraParams['host'], equals('cdn.example.com'));
      expect(vless.extraParams['pbk'], isNotEmpty);

      final hy2 = result.profiles.firstWhere((p) => p.protocol == 'hysteria2');
      expect(hy2.extraParams['auth'], equals('sample_hy2_pass'));
      expect(hy2.extraParams['insecure'], isTrue);
      expect(result.warnings, isNotEmpty);
    });

    test('Detects and parses sing-box JSON outbounds', () async {
      final json = jsonEncode(<String, dynamic>{
        'outbounds': <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'vless',
            'tag': 'JSON VLESS',
            'server': '198.51.100.93',
            'server_port': 443,
            'uuid': '00000000-0000-0000-0000-000000000004',
            'tls': <String, dynamic>{
              'enabled': true,
              'server_name': 'json.example.com',
              'utls': <String, dynamic>{'enabled': true, 'fingerprint': 'chrome'},
            },
            'transport': <String, dynamic>{
              'type': 'grpc',
              'service_name': 'grpc-svc',
            },
          },
          <String, dynamic>{
            'type': 'tuic',
            'tag': 'JSON TUIC',
            'server': '198.51.100.94',
            'server_port': 443,
            'uuid': '00000000-0000-0000-0000-000000000005',
            'password': 'sample_tuic_pass',
            'tls': <String, dynamic>{
              'enabled': true,
              'server_name': 'tuic.example.com',
              'alpn': <String>['h3'],
            },
          },
          <String, dynamic>{'type': 'direct', 'tag': 'direct'},
          <String, dynamic>{'type': 'block', 'tag': 'block'},
        ],
      });

      final result = await detector.detectAndParse(json);
      expect(result.isSuccess, isTrue);
      expect(result.profiles.length, equals(2));

      final vless = result.profiles.firstWhere((p) => p.protocol == 'vless');
      expect(vless.extraParams['transportType'], equals('grpc'));
      expect(vless.extraParams['serviceName'], equals('grpc-svc'));
      expect(vless.extraParams['security'], equals('tls'));

      final tuic = result.profiles.firstWhere((p) => p.protocol == 'tuic');
      expect(tuic.extraParams['password'], equals('sample_tuic_pass'));
      expect(tuic.extraParams['alpn'], equals('h3'));
    });

    test('Rejects invalid YAML/JSON documents without throwing', () async {
      final brokenYaml = await detector.detectAndParse('proxies: [oops');
      expect(brokenYaml.isSuccess, isFalse);

      final brokenJson = await detector.detectAndParse('{"outbounds": [}');
      expect(brokenJson.isSuccess, isFalse);
    });

    test('Parses WireGuard URI, .conf, and generates sing-box 1.14 endpoints', () async {
      const converter = SingboxConverter();
      const wgUri =
          'wireguard://cHJpdmF0ZV9rZXlfYmFzZTY0X3Rlc3RfMTIzNDU2Nzg=@198.51.100.120:51820?publickey=cHVibGljX2tleV9iYXNlNjRfdGVzdF8xMjM0NTY3OA==&address=10.0.0.2/32&mtu=1400&reserved=1,2,3#WG-Test';
      final result = await detector.detectAndParse(wgUri);
      expect(result.isSuccess, isTrue);
      final profile = result.profiles.first;
      expect(profile.protocol, equals('wireguard'));
      expect(profile.serverPort, equals(51820));
      expect(profile.extraParams['mtu'], equals(1400));
      expect(profile.extraParams['reserved'], equals(<int>[1, 2, 3]));

      final fullConfig = converter.buildFullConfig(profile);
      expect(fullConfig.containsKey('endpoints'), isTrue);
      final endpoints = fullConfig['endpoints'] as List;
      expect(endpoints.length, equals(1));
      final ep = endpoints.first as Map<String, dynamic>;
      expect(ep['type'], equals('wireguard'));
      expect(ep['tag'], equals('proxy'));
      expect((ep['peers'] as List).first['reserved'], equals(<int>[1, 2, 3]));

      const wgConf = '''
[Interface]
PrivateKey = cHJpdmF0ZV9rZXlfYmFzZTY0X3Rlc3RfMTIzNDU2Nzg=
Address = 10.66.66.2/32
MTU = 1380

[Peer]
PublicKey = cHVibGljX2tleV9iYXNlNjRfdGVzdF8xMjM0NTY3OA==
Endpoint = 198.51.100.121:51820
AllowedIPs = 0.0.0.0/0
''';
      final confResult = await detector.detectAndParse(wgConf);
      expect(confResult.isSuccess, isTrue);
      expect(confResult.profiles.first.protocol, equals('wireguard'));
      expect(confResult.profiles.first.serverAddress, equals('198.51.100.121'));
    });

    test('Parses VMess URI format, Trojan Reality, and QUIC transport', () async {
      const converter = SingboxConverter();
      const vmessUri =
          'vmess://00000000-0000-0000-0000-000000000009@198.51.100.130:443?type=quic&security=tls&sni=vmess.example.com&fp=chrome#VMess-QUIC';
      final vmessRes = await detector.detectAndParse(vmessUri);
      expect(vmessRes.isSuccess, isTrue);
      final vmessOutbound = converter.buildOutbound(vmessRes.profiles.first);
      expect((vmessOutbound['transport'] as Map)['type'], equals('quic'));
      expect((vmessOutbound['tls'] as Map)['enabled'], isTrue);

      const trojanRealityUri =
          'trojan://secret_pass@198.51.100.131:443?security=reality&sni=www.microsoft.com&pbk=1111111111111111111111111111111111111111111=&sid=a1b2&fp=chrome&type=grpc&serviceName=tr-grpc#Trojan-Reality';
      final trojanRes = await detector.detectAndParse(trojanRealityUri);
      expect(trojanRes.isSuccess, isTrue);
      final trojanOutbound = converter.buildOutbound(trojanRes.profiles.first);
      final tls = trojanOutbound['tls'] as Map<String, dynamic>;
      expect((tls['reality'] as Map)['enabled'], isTrue);
      expect((trojanOutbound['transport'] as Map)['type'], equals('grpc'));
    });
  });
}
