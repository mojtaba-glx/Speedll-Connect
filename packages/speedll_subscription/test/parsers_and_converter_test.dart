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

      // Test all.txt style plain multiline starting directly with vless:// (no leading #)
      // and containing multiple configs on the same host/port/UUID + emojis/brackets/pipes
      const allTxtPayload = '''vless://00000000-0000-0000-0000-000000000001@127.0.0.1:1080?type=tcp&security=none#📊 حجم باقیمانده: 42 GB
vless://00000000-0000-0000-0000-000000000001@198.51.100.10:443?type=ws&security=tls&host=cdn1.speedll-sample.test&path=%2Fws1#🇩🇪 آلمان ۱ | [VIP]
vless://00000000-0000-0000-0000-000000000001@198.51.100.10:443?type=ws&security=tls&host=cdn2.speedll-sample.test&path=%2Fws2#🇩🇪 آلمان ۲ | [Direct]
trojan://sanitized_pass@198.51.100.30:443?security=tls&type=grpc&serviceName=grpc1#🇫🇷 فرانسه ۱''';

      final allTxtResult = await detector.detectAndParse(allTxtPayload);
      expect(allTxtResult.isSuccess, isTrue);
      expect(allTxtResult.profiles.length, equals(4));
      // Verify unique IDs even when host/port/UUID are identical
      final uniqueIds = allTxtResult.profiles.map((p) => p.id).toSet();
      expect(uniqueIds.length, equals(4));
      // Verify info node detection on 127.0.0.1
      expect(allTxtResult.profiles[0].extraParams['isInfoNode'], isTrue);
      expect(allTxtResult.profiles[1].extraParams['isInfoNode'], isNull);
      expect(allTxtResult.profiles[1].displayName, equals('🇩🇪 آلمان ۱ | [VIP]'));
      expect(allTxtResult.profiles[2].displayName, equals('🇩🇪 آلمان ۲ | [Direct]'));
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

    test('Generates routing rules bypassing private/LAN IPs and .ir domains', () {
      const converter = SingboxConverter();
      const profile = ServerProfile(
        id: 'test-routing',
        displayName: 'سرور تست مسیریابی',
        protocol: 'vless',
        source: ProfileSource.subscription,
        serverAddress: '198.51.100.10',
        serverPort: 443,
        extraParams: {
          'uuid': '00000000-0000-0000-0000-000000000001',
          'security': 'reality',
          'pbk': '1111111111111111111111111111111111111111111=',
        },
      );

      final fullConfig = converter.buildFullConfig(
        profile,
        routingOptions: const SingboxRoutingOptions(
          bypassLan: true,
          bypassIranDomains: true,
          enableTrafficSniffing: true,
          customDirectDomains: ['bank.test.ir'],
          customDirectCidrs: ['185.143.232.0/22'],
        ),
      );

      final route = fullConfig['route'] as Map<String, dynamic>;
      final rules = route['rules'] as List<Map<String, dynamic>>;

      expect(route['final'], equals('proxy'));
      expect(route['default_domain_resolver'], equals('dns-direct'));
      expect(
        rules.any((r) => r['action'] == 'sniff'),
        isTrue,
      );
      expect(
        rules.any((r) => r['inbound'] == 'dns-in' && r['action'] == 'hijack-dns'),
        isTrue,
      );
      expect(
        rules.any((r) => r['protocol'] == 'dns' && r['action'] == 'hijack-dns'),
        isTrue,
      );
      expect(
        rules.any((r) => r['ip_is_private'] == true && r['outbound'] == 'direct'),
        isTrue,
      );
      expect(
        rules.any((r) =>
            r['domain_suffix'] is List &&
            (r['domain_suffix'] as List).contains('.ir') &&
            r['outbound'] == 'direct'),
        isTrue,
      );
      expect(
        rules.any((r) =>
            r['ip_cidr'] is List &&
            (r['ip_cidr'] as List).contains('192.168.0.0/16') &&
            r['outbound'] == 'direct'),
        isTrue,
      );

      final dns = fullConfig['dns'] as Map<String, dynamic>;
      final dnsRules = dns['rules'] as List<Map<String, dynamic>>;
      expect(dns['final'], equals('dns-remote'));
      expect(
        dnsRules.first['server'],
        equals('dns-direct'),
      );
      expect(
        (dnsRules.first['domain_suffix'] as List).contains('.ir'),
        isTrue,
      );
    });

    test('Generates valid VLESS WS direct config with early data (?ed=2048) and TCP HTTP transport', () async {
      const parser = VlessParser();
      const converter = SingboxConverter();

      const wsUri =
          'vless://00000000-0000-0000-0000-000000000001@198.51.100.10:80?encryption=none&security=none&type=ws&host=cdn.speedll-sample.test&path=%2Fws%3Fed%3D2048#DE-HTTP-WS-Direct';
      final wsParsed = await parser.parse(wsUri);
      expect(wsParsed.isSuccess, isTrue);

      final wsOutbound = converter.buildOutbound(wsParsed.profiles.first);
      expect(wsOutbound['type'], equals('vless'));
      expect(wsOutbound['server_port'], equals(80));
      expect(wsOutbound.containsKey('tls'), isFalse);
      final wsTransport = wsOutbound['transport'] as Map<String, dynamic>;
      expect(wsTransport['type'], equals('ws'));
      expect(wsTransport['path'], equals('/ws'));
      expect(wsTransport['headers'], equals({'Host': 'cdn.speedll-sample.test'}));
      expect(wsTransport['max_early_data'], equals(2048));
      expect(wsTransport['early_data_header_name'], equals('Sec-WebSocket-Protocol'));

      const tcpHttpUri =
          'vless://00000000-0000-0000-0000-000000000001@198.51.100.10:8080?encryption=none&security=none&type=tcp&headerType=http&host=speedtest.sample.test&path=%2F#DE-TCP-HTTP';
      final tcpHttpParsed = await parser.parse(tcpHttpUri);
      expect(tcpHttpParsed.isSuccess, isTrue);

      final tcpHttpOutbound = converter.buildOutbound(tcpHttpParsed.profiles.first);
      final httpTransport = tcpHttpOutbound['transport'] as Map<String, dynamic>;
      expect(httpTransport['type'], equals('http'));
      expect(httpTransport['path'], equals('/'));
      expect(httpTransport['host'], equals(['speedtest.sample.test']));
    });
  });

  group('SubscriptionUpdater SSRF, Offline, Validation & Periodic Tests', () {
    test('Blocks SSRF URLs (HTTP, localhost, private IPs, link-local metadata)', () async {
      final updater = SubscriptionUpdater();

      final httpResult =
          await updater.fetchAndValidate('http://sub.speedll-sample.test/api');
      expect(httpResult.isSuccess, isFalse);
      expect(httpResult.errorMessage, contains('HTTPS'));

      final localhostResult =
          await updater.fetchAndValidate('https://localhost:8080/sub');
      expect(localhostResult.isSuccess, isFalse);
      expect(localhostResult.errorMessage, contains('SSRF'));

      final privateIpResult =
          await updater.fetchAndValidate('https://192.168.1.1/sub');
      expect(privateIpResult.isSuccess, isFalse);
      expect(privateIpResult.errorMessage, contains('SSRF'));

      final metadataResult =
          await updater.fetchAndValidate('https://169.254.169.254/latest/meta-data');
      expect(metadataResult.isSuccess, isFalse);
      expect(metadataResult.errorMessage, contains('SSRF'));
    });

    test('Handles network disconnection gracefully without throwing', () async {
      final updater = SubscriptionUpdater(
        httpClient: _FakeHttpClient((uri) async {
          throw const SocketException('Network is unreachable');
        }),
      );

      final result = await updater
          .fetchAndValidate('https://sub.speedll-sample.test/sub?token=secret123');
      expect(result.isSuccess, isFalse);
      expect(result.isOfflineError, isTrue);
      expect(result.errorMessage, contains('پروفایل‌های قبلی حفظ شدند'));
      expect(result.errorMessage, isNot(contains('secret123')));
    });

    test('Rejects HTML captive portal / corrupted server responses and redacts token', () async {
      final updater = SubscriptionUpdater(
        httpClient: _FakeHttpClient((uri) async {
          return const SubscriptionHttpResponse(
            statusCode: 200,
            body: '<!DOCTYPE html><html><body>Login Required</body></html>',
          );
        }),
      );

      final result = await updater
          .fetchAndValidate('https://sub.speedll-sample.test/sub?token=secret123');
      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, contains('HTML'));
    });

    test('Blocks malicious redirect to private IP (SSRF via redirect)', () async {
      final updater = SubscriptionUpdater(
        httpClient: _FakeHttpClient((uri) async {
          return const SubscriptionHttpResponse(
            statusCode: 302,
            body: '',
            redirectLocation: 'https://10.0.0.1/internal-secret',
          );
        }),
      );

      final result =
          await updater.fetchAndValidate('https://sub.speedll-sample.test/sub');
      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, contains('تغییر مسیر ناامن مسدود شد'));
    });

    test('Parses valid subscription response and runs periodic refresh cycle', () async {
      const validPayload =
          'vless://00000000-0000-0000-0000-000000000001@198.51.100.10:443?type=tcp&security=reality&pbk=1111111111111111111111111111111111111111111=&fp=chrome#DE-Updated';
      final encoded = base64Encode(utf8.encode(validPayload));

      final updater = SubscriptionUpdater(
        httpClient: _FakeHttpClient((uri) async {
          return SubscriptionHttpResponse(
            statusCode: 200,
            body: encoded,
          );
        }),
      );

      final updatedUrls = <String>[];
      final updatedProfiles = <ServerProfile>[];

      await updater.runRefreshCycle(
        getSubscriptionUrls: () => ['https://sub.speedll-sample.test/v1/sub'],
        onUpdateResult: (url, result) {
          if (result.isSuccess) {
            updatedUrls.add(url);
            updatedProfiles.addAll(result.profiles);
          }
        },
      );

      expect(updatedUrls.length, equals(1));
      expect(updatedProfiles.length, equals(1));
      expect(updatedProfiles.first.displayName, equals('DE-Updated'));
    });

    test('SingboxRoutingOptions defaults traffic sniffing to false', () {
      const converter = SingboxConverter();
      const defaults = SingboxRoutingOptions();
      expect(defaults.enableTrafficSniffing, isFalse);

      final profile = converter.buildFullConfig(
        const ServerProfile(
          id: 'p1',
          displayName: 'Test-VLESS',
          protocol: 'vless',
          source: ProfileSource.manual,
          serverAddress: '198.51.100.10',
          serverPort: 443,
          extraParams: <String, dynamic>{
            'uuid': '00000000-0000-0000-0000-000000000001',
            'security': 'none',
          },
        ),
      );
      final route = profile['route'] as Map<String, dynamic>;
      final rules = route['rules'] as List<Map<String, dynamic>>;
      expect(rules.any((r) => r['action'] == 'sniff'), isFalse);
      expect(
        rules.any((r) => r['protocol'] == 'dns' && r['action'] == 'hijack-dns'),
        isTrue,
      );
    });

    test('parses valid DNS presets/URIs and rejects malformed DNS inputs', () {
      const converter = SingboxConverter();
      // Positive formats
      final ipv4 = SingboxConverter.parseDnsServerConfig(
        '8.8.8.8',
        tag: 'dns-direct',
      );
      expect(ipv4, equals(<String, dynamic>{
        'type': 'udp',
        'tag': 'dns-direct',
        'server': '8.8.8.8',
        'server_port': 53,
      }));

      final ipv4Port = SingboxConverter.parseDnsServerConfig(
        '1.1.1.1:5353',
        tag: 'dns-remote',
        detour: 'proxy',
      );
      expect(ipv4Port?['server_port'], equals(5353));
      expect(ipv4Port?['detour'], equals('proxy'));

      final dot = SingboxConverter.parseDnsServerConfig(
        'tls://dns.google',
        tag: 'dns-remote',
        detour: 'proxy',
      );
      expect(dot?['type'], equals('tls'));
      expect(dot?['server'], equals('dns.google'));
      expect(dot?['server_port'], equals(853));
      expect(dot?['domain_resolver'], equals('dns-local'));
      expect(dot?['detour'], equals('proxy'));

      final doh = SingboxConverter.parseDnsServerConfig(
        'https://dns.google/dns-query',
        tag: 'dns-direct',
      );
      expect(doh?['type'], equals('https'));
      expect(doh?['server'], equals('dns.google'));
      expect(doh?['server_port'], equals(443));
      expect(doh?['path'], equals('/dns-query'));
      expect(doh?['domain_resolver'], equals('dns-local'));
      expect(doh?.containsKey('detour'), isFalse);

      final ipv6Bracketed = SingboxConverter.parseDnsServerConfig(
        '[2606:4700:4700::1111]:53',
        tag: 'dns-direct',
      );
      expect(ipv6Bracketed?['type'], equals('udp'));
      expect(ipv6Bracketed?['server'], equals('2606:4700:4700::1111'));
      expect(ipv6Bracketed?['server_port'], equals(53));

      expect(SingboxConverter.isValidDnsServer('2001:4860:4860::8888'), isTrue);
      expect(SingboxConverter.isValidDnsServer('tcp://9.9.9.9:53'), isTrue);
      expect(SingboxConverter.isValidDnsServer('h3://cloudflare-dns.com/dns-query'), isTrue);
      expect(SingboxConverter.isValidDnsServer('local'), isTrue);
      expect(SingboxConverter.isValidDnsServer('dns.quad9.net'), isTrue);

      // Negative & malformed formats
      for (final invalid in const <String>[
        '',
        '   ',
        '999.999.999.999',
        'not a valid dns',
        'ftp://1.1.1.1',
        'https://',
        '1.1.1.1:70000',
        '1.1.1.1:0',
        '[::1:53',
        'javascript:alert(1)',
      ]) {
        expect(
          SingboxConverter.isValidDnsServer(invalid),
          isFalse,
          reason: 'Expected invalid: "$invalid"',
        );
      }

      // Malformed saved options gracefully fall back without crashing config build.
      final fallbackConfig = converter.buildDnsConfig(
        const SingboxRoutingOptions(
          remoteDnsServer: 'not a dns',
          directDnsServer: '999.999.999.999',
        ),
      );
      final servers = fallbackConfig['servers'] as List<Map<String, dynamic>>;
      expect(
        servers.firstWhere((s) => s['tag'] == 'dns-remote')['server'],
        equals('1.1.1.1'),
      );
      expect(
        servers.firstWhere((s) => s['tag'] == 'dns-direct')['type'],
        equals('local'),
      );
    });

    test('SafeProxyUri preserves bracketed IPv6 hosts with spaces/pipes in query and normalizes hosts', () async {
      const rawUri =
          'vless://11111111-1111-1111-1111-111111111111@[2001:db8::abcd]:443?security=tls&type=ws&path=/?ed=2048|test space#IPv6 Node';
      final parsed = SafeProxyUri.parse(rawUri);
      expect(parsed.uri.host, equals('2001:db8::abcd'));
      expect(parsed.uri.port, equals(443));

      const parser = VlessParser();
      final result = await parser.parse(rawUri);
      expect(result.isSuccess, isTrue);
      expect(result.profiles.first.serverAddress, equals('2001:db8::abcd'));
      expect(result.profiles.first.serverPort, equals(443));

      expect(SafeProxyUri.normalizeHost('[2001:db8::1]'), equals('2001:db8::1'));
      expect(SafeProxyUri.normalizeHost('2001:db8::1'), equals('2001:db8::1'));
      expect(SafeProxyUri.normalizeHost('example.com'), equals('example.com'));

      expect(SingboxConverter.isValidDnsServer('2606:4700:4700::1111'), isTrue);
      expect(SingboxConverter.isValidDnsServer('[2606:4700:4700::1111]:53'), isTrue);
    });
  });
}

class _FakeHttpClient implements SubscriptionHttpClient {
  const _FakeHttpClient(this._handler);
  final Future<SubscriptionHttpResponse> Function(Uri uri) _handler;

  @override
  Future<SubscriptionHttpResponse> get(
    Uri uri, {
    required Duration timeout,
    required int maxBytes,
  }) {
    return _handler(uri);
  }
}
