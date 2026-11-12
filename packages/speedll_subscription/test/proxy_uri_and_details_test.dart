import 'package:speedll_subscription/speedll_subscription.dart';
import 'package:test/test.dart';

void main() {
  group('ProxyUriSerializer', () {
    test('round-trips VLESS REALITY Vision including IPv6 host and Unicode remark', () async {
      const uri =
          'vless://11111111-1111-1111-1111-111111111111@[2001:db8::1]:443'
          '?security=reality&type=tcp&flow=xtls-rprx-vision&sni=example.com'
          '&fp=chrome&pbk=PubKey123&sid=ab12#%D8%A2%D9%84%D9%85%D8%A7%D9%86%20%F0%9F%87%A9%F0%9F%87%AA';
      final parsed = await const VlessParser().parse(uri);
      expect(parsed.isSuccess, isTrue);

      final exported = ProxyUriSerializer.serialize(parsed.profiles.first);
      expect(exported, isNotNull);
      expect(exported!, contains('[2001:db8::1]:443'));

      final reparsed = await const VlessParser().parse(exported);
      expect(reparsed.isSuccess, isTrue);
      final p = reparsed.profiles.first;
      expect(p.serverAddress, '2001:db8::1');
      expect(p.serverPort, 443);
      expect(p.displayName, 'آلمان 🇩🇪');
      expect(p.extraParams['uuid'], '11111111-1111-1111-1111-111111111111');
      expect(p.extraParams['security'], 'reality');
      expect(p.extraParams['flow'], 'xtls-rprx-vision');
      expect(p.extraParams['pbk'], 'PubKey123');
      expect(p.extraParams['sid'], 'ab12');
    });

    test('round-trips VMess TLS WebSocket config', () async {
      const profile = ServerProfile(
        id: 'vm1',
        displayName: 'NL VMess WS',
        protocol: 'vmess',
        source: ProfileSource.subscription,
        serverAddress: 'nl.example.com',
        serverPort: 443,
        extraParams: <String, dynamic>{
          'uuid': '22222222-2222-2222-2222-222222222222',
          'alterId': 0,
          'scy': 'chacha20-poly1305',
          'transportType': 'ws',
          'path': '/ws-path',
          'host': 'cdn.example.com',
          'tls': 'tls',
          'sni': 'cdn.example.com',
          'fingerprint': 'firefox',
        },
      );

      final exported = ProxyUriSerializer.serialize(profile);
      expect(exported, startsWith('vmess://'));

      final reparsed = await const VmessParser().parse(exported!);
      expect(reparsed.isSuccess, isTrue);
      final p = reparsed.profiles.first;
      expect(p.serverAddress, 'nl.example.com');
      expect(p.extraParams['transportType'], 'ws');
      expect(p.extraParams['path'], '/ws-path');
      expect(p.extraParams['host'], 'cdn.example.com');
      expect(p.extraParams['tls'], 'tls');
      expect(p.extraParams['fingerprint'], 'firefox');
    });

    test('round-trips Trojan, Shadowsocks, Hysteria2, Hysteria, TUIC, AnyTLS, WireGuard', () async {
      final cases = <(String, SubscriptionParser)>[
        (
          'trojan://secret@de.example.com:443?security=tls&type=grpc&serviceName=grpcSvc&sni=de.example.com#TrojanNode',
          const TrojanParser(),
        ),
        (
          'ss://YWVzLTI1Ni1nY206c2VjcmV0@1.2.3.4:8388#SSNode',
          const ShadowsocksParser(),
        ),
        (
          'hysteria2://hy2pass@hy.example.com:8443?sni=hy.example.com&obfs=salamander&obfs-password=obfspass&insecure=1#Hy2Node',
          const Hysteria2Parser(),
        ),
        (
          'hysteria://1.2.3.4:443?auth=hy1pass&peer=sni.test&upmbps=50&downmbps=100#Hy1Node',
          const HysteriaParser(),
        ),
        (
          'tuic://33333333-3333-3333-3333-333333333333:tuicpass@tuic.example.com:443?sni=tuic.example.com&congestion_control=bbr#TuicNode',
          const TuicParser(),
        ),
        (
          'anytls://anypass@any.example.com:443?sni=any.example.com#AnyNode',
          const AnyTlsParser(),
        ),
        (
          'wireguard://privKeyBase64@wg.example.com:51820?publickey=pubKeyBase64&address=10.0.0.2/32&mtu=1280&reserved=1,2,3#WGNode',
          const WireguardParser(),
        ),
      ];

      for (final (rawUri, parser) in cases) {
        final first = await parser.parse(rawUri);
        expect(first.isSuccess, isTrue, reason: 'initial parse failed: $rawUri');
        final exported = ProxyUriSerializer.serialize(first.profiles.first);
        expect(exported, isNotNull, reason: 'serialize returned null: $rawUri');
        final second = await parser.parse(exported!);
        expect(second.isSuccess, isTrue, reason: 'round-trip parse failed: $exported');
        expect(second.profiles.first.displayName, first.profiles.first.displayName);
        expect(second.profiles.first.serverAddress, first.profiles.first.serverAddress);
        expect(second.profiles.first.serverPort, first.profiles.first.serverPort);
      }
    });

    test('returns null for metadata info placeholders', () {
      const infoProfile = ServerProfile(
        id: 'info1',
        displayName: 'Remaining: 40 GB',
        protocol: 'vless',
        source: ProfileSource.subscription,
        serverAddress: '127.0.0.1',
        serverPort: 443,
        extraParams: <String, dynamic>{'uuid': '0000', 'isInfoNode': true},
      );
      expect(ProxyUriSerializer.serialize(infoProfile), isNull);
    });
  });

  group('ProtocolDetailsFormatter', () {
    test('builds full protocol model for VLESS REALITY Vision', () {
      const profile = ServerProfile(
        id: 'v1',
        displayName: 'Germany',
        protocol: 'vless',
        source: ProfileSource.manual,
        serverAddress: 'de.example.com',
        serverPort: 443,
        extraParams: <String, dynamic>{
          'uuid': 'u',
          'security': 'reality',
          'flow': 'xtls-rprx-vision',
          'transportType': 'tcp',
          'fingerprint': 'chrome',
          'alpn': 'h2',
        },
      );

      final details = ProtocolDetailsFormatter.inspect(profile);
      expect(details.headlineModel, 'VLESS · REALITY · Vision · TCP');
      expect(details.secondarySpecs, containsAll(['uTLS: chrome', 'ALPN: h2']));
    });

    test('builds full protocol model for Hysteria2, Shadowsocks AEAD-2022, WireGuard', () {
      const hy2 = ServerProfile(
        id: 'h1',
        displayName: 'Hy2',
        protocol: 'hysteria2',
        source: ProfileSource.subscription,
        serverAddress: 'h.example.com',
        serverPort: 443,
        extraParams: <String, dynamic>{'obfs': 'salamander'},
      );
      expect(
        ProtocolDetailsFormatter.inspect(hy2).headlineModel,
        'Hysteria2 · TLS · Salamander · QUIC',
      );

      const ss2022 = ServerProfile(
        id: 's1',
        displayName: 'SS',
        protocol: 'shadowsocks',
        source: ProfileSource.manual,
        serverAddress: 's.example.com',
        serverPort: 8388,
        extraParams: <String, dynamic>{
          'method': '2022-blake3-aes-256-gcm',
          'udpOverTcp': true,
        },
      );
      expect(
        ProtocolDetailsFormatter.inspect(ss2022).headlineModel,
        'Shadowsocks · AEAD-2022 · UoT · 2022-blake3-aes-256-gcm · TCP/UDP',
      );

      const wg = ServerProfile(
        id: 'w1',
        displayName: 'WG',
        protocol: 'wireguard',
        source: ProfileSource.manual,
        serverAddress: 'w.example.com',
        serverPort: 51820,
        extraParams: <String, dynamic>{'mtu': 1280},
      );
      final wgDetails = ProtocolDetailsFormatter.inspect(wg);
      expect(wgDetails.headlineModel, 'WireGuard · Noise · UDP');
      expect(wgDetails.secondarySpecs, contains('MTU: 1280'));
    });
  });
}
