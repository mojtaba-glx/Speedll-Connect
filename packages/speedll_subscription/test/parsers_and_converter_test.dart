import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:speedll_subscription/speedll_subscription.dart';

void main() {
  group('Sanitized Fixtures & Parsers Tests', () {
    late Map<String, dynamic> fixturesJson;

    setUpAll(() {
      final file = File('test/fixtures/samples.json');
      fixturesJson = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    });

    test('Parses HDF-DE-01 (VLESS Reality) accurately', () async {
      final sample = (fixturesJson['samples'] as List)
          .firstWhere((s) => s['id'] == 'HDF-DE-01');

      const parser = VlessParser();
      expect(parser.canParse(sample['uri']), isTrue);

      final result = await parser.parse(sample['uri']);
      expect(result.isSuccess, isTrue);
      expect(result.profiles.length, equals(1));

      final profile = result.profiles.first;
      expect(profile.protocol, equals('vless'));
      expect(profile.serverAddress, equals('198.51.100.10'));
      expect(profile.serverPort, equals(443));
      expect(profile.displayName, equals('HDF-DE-Reality'));
      expect(profile.extraParams['security'], equals('reality'));
      expect(profile.extraParams['flow'], equals('xtls-rprx-vision'));
      expect(profile.extraParams['pbk'], equals('1111111111111111111111111111111111111111111='));
    });

    test('Parses HDF-TR-01 (VMess WS TLS) accurately', () async {
      final sample = (fixturesJson['samples'] as List)
          .firstWhere((s) => s['id'] == 'HDF-TR-01');

      const parser = VmessParser();
      expect(parser.canParse(sample['uri']), isTrue);

      final result = await parser.parse(sample['uri']);
      expect(result.isSuccess, isTrue);

      final profile = result.profiles.first;
      expect(profile.protocol, equals('vmess'));
      expect(profile.serverAddress, equals('198.51.100.20'));
      expect(profile.serverPort, equals(443));
      expect(profile.displayName, equals('HDF-TR-VMess'));
      expect(profile.extraParams['transportType'], equals('ws'));
      expect(profile.extraParams['path'], equals('/speedll_ws'));
    });

    test('Parses SAN-FR-01 (Trojan gRPC) accurately', () async {
      final sample = (fixturesJson['samples'] as List)
          .firstWhere((s) => s['id'] == 'SAN-FR-01');

      const parser = TrojanParser();
      expect(parser.canParse(sample['uri']), isTrue);

      final result = await parser.parse(sample['uri']);
      expect(result.isSuccess, isTrue);

      final profile = result.profiles.first;
      expect(profile.protocol, equals('trojan'));
      expect(profile.serverAddress, equals('198.51.100.30'));
      expect(profile.serverPort, equals(443));
      expect(profile.displayName, equals('SAN-FR-Trojan'));
      expect(profile.extraParams['transportType'], equals('grpc'));
      expect(profile.extraParams['serviceName'], equals('speedll-grpc'));
    });

    test('Parses XNET-FR-01 (Hysteria2) accurately', () async {
      final sample = (fixturesJson['samples'] as List)
          .firstWhere((s) => s['id'] == 'XNET-FR-01');

      const parser = Hysteria2Parser();
      expect(parser.canParse(sample['uri']), isTrue);

      final result = await parser.parse(sample['uri']);
      expect(result.isSuccess, isTrue);

      final profile = result.profiles.first;
      expect(profile.protocol, equals('hysteria2'));
      expect(profile.serverAddress, equals('198.51.100.40'));
      expect(profile.serverPort, equals(443));
      expect(profile.displayName, equals('XNET-FR-Hy2'));
      expect(profile.extraParams['obfs'], equals('salamander'));
      expect(profile.extraParams['obfsPassword'], equals('sample_obfs_pass'));
      expect(profile.extraParams['mport'], equals('20000-30000'));
    });

    test('Parses SS-NL-01 (Shadowsocks SIP002) accurately', () async {
      final sample = (fixturesJson['samples'] as List)
          .firstWhere((s) => s['id'] == 'SS-NL-01');

      const parser = ShadowsocksParser();
      expect(parser.canParse(sample['uri']), isTrue);

      final result = await parser.parse(sample['uri']);
      expect(result.isSuccess, isTrue);

      final profile = result.profiles.first;
      expect(profile.protocol, equals('shadowsocks'));
      expect(profile.serverAddress, equals('198.51.100.50'));
      expect(profile.serverPort, equals(8388));
      expect(profile.displayName, equals('SS-NL-Standard'));
      expect(profile.extraParams['method'], equals('aes-256-gcm'));
      expect(profile.extraParams['password'], equals('sanitized_password_123'));
    });
  });

  group('SubscriptionDetector & Negative / DoS Tests', () {
    test('SubscriptionDetector parses multi-line and base64 payloads', () async {
      const detector = SubscriptionDetector();

      const multiline = '''
# Comments should be ignored
vless://00000000-0000-0000-0000-000000000001@198.51.100.10:443?type=tcp&security=reality&pbk=1111111111111111111111111111111111111111111=&fp=chrome#DE-1
hysteria2://user_pass@198.51.100.40:443#FR-1
''';

      final result = await detector.detectAndParse(multiline);
      expect(result.isSuccess, isTrue);
      expect(result.profiles.length, equals(2));

      // Test Base64 encoded payload
      final encoded = base64Encode(utf8.encode(multiline));
      final b64Result = await detector.detectAndParse(encoded);
      expect(b64Result.isSuccess, isTrue);
      expect(b64Result.profiles.length, equals(2));
    });

    test('SubscriptionDetector rejects oversized payload to prevent DoS', () async {
      const detector = SubscriptionDetector(maxPayloadSizeBytes: 100);
      final hugeInput = 'A' * 200;

      final result = await detector.detectAndParse(hugeInput);
      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, contains('حد مجاز'));
    });

    test('Handles malformed URIs gracefully without crashing', () async {
      const vlessParser = VlessParser();
      final malformed = await vlessParser.parse('vless://invalid-url-with-no-host');
      expect(malformed.isSuccess, isFalse);

      const vmessParser = VmessParser();
      final badBase64 = await vmessParser.parse('vmess://not_base_64_json_content!!!');
      expect(badBase64.isSuccess, isFalse);
    });
  });

  group('SingboxConverter Deterministic Generation Tests', () {
    test('Generates valid VLESS Reality outbound config', () {
      const converter = SingboxConverter();

      const profile = ServerProfile(
        id: 'test-vless',
        displayName: 'آلمان ریالیتی',
        protocol: 'vless',
        source: ProfileSource.subscription,
        serverAddress: '198.51.100.10',
        serverPort: 443,
        extraParams: {
          'uuid': '00000000-0000-0000-0000-000000000001',
          'security': 'reality',
          'flow': 'xtls-rprx-vision',
          'sni': 'de.speedll-sample.test',
          'pbk': 'sample_pbk_key',
          'fingerprint': 'chrome',
        },
      );

      final outbound = converter.buildOutbound(profile);
      expect(outbound['type'], equals('vless'));
      expect(outbound['server'], equals('198.51.100.10'));
      expect(outbound['server_port'], equals(443));
      expect(outbound['flow'], equals('xtls-rprx-vision'));
      expect(outbound['tls']['reality']['enabled'], isTrue);
      expect(outbound['tls']['reality']['public_key'], equals('sample_pbk_key'));
    });

    test('Generates valid Hysteria2 outbound config with obfs', () {
      const converter = SingboxConverter();

      const profile = ServerProfile(
        id: 'test-hy2',
        displayName: 'فرانسه هیستریا',
        protocol: 'hysteria2',
        source: ProfileSource.subscription,
        serverAddress: '198.51.100.40',
        serverPort: 443,
        extraParams: {
          'auth': 'secret_auth',
          'sni': 'fr.test.speedll',
          'obfs': 'salamander',
          'obfsPassword': 'test_obfs_pass',
        },
      );

      final outbound = converter.buildOutbound(profile);
      expect(outbound['type'], equals('hysteria2'));
      expect(outbound['password'], equals('secret_auth'));
      expect(outbound['tls']['server_name'], equals('fr.test.speedll'));
      expect(outbound['obfs']['type'], equals('salamander'));
      expect(outbound['obfs']['password'], equals('test_obfs_pass'));
    });
  });
}
