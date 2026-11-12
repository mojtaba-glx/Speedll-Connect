import 'dart:convert';
import 'package:test/test.dart';
import 'package:speedll_subscription/speedll_subscription.dart';

void main() {
  group('Region-aware routing assets', () {
    const converter = SingboxConverter();

    test('China region embeds CN domains and CIDRs', () {
      final rules = converter.buildRoutingRules(
        const SingboxRoutingOptions(
          region: RoutingRegion.china,
          bypassLan: false,
        ),
      );
      final domains = rules
          .where((rule) => rule['domain_suffix'] is List)
          .expand((rule) => rule['domain_suffix'] as List)
          .toSet();
      final cidrs = rules
          .where((rule) => rule['ip_cidr'] is List)
          .expand((rule) => rule['ip_cidr'] as List)
          .toSet();

      expect(domains, contains('.cn'));
      expect(domains, contains('baidu.com'));
      expect(cidrs, contains('1.0.1.0/24'));
      expect(cidrs, isNot(contains('5.22.0.0/16')));
    });

    test('Russia region embeds RU domains and CIDRs', () {
      final rules = converter.buildRoutingRules(
        const SingboxRoutingOptions(
          region: RoutingRegion.russia,
          bypassLan: false,
        ),
      );
      final domains = rules
          .where((rule) => rule['domain_suffix'] is List)
          .expand((rule) => rule['domain_suffix'] as List)
          .toSet();
      final cidrs = rules
          .where((rule) => rule['ip_cidr'] is List)
          .expand((rule) => rule['ip_cidr'] as List)
          .toSet();

      expect(domains, contains('.ru'));
      expect(domains, contains('yandex.ru'));
      expect(cidrs, contains('2.56.24.0/22'));
    });

    test('Global region disables domestic rules and DNS bypass', () {
      final rules = converter.buildRoutingRules(
        const SingboxRoutingOptions(
          region: RoutingRegion.global,
          bypassLan: false,
        ),
      );
      final dns = converter.buildDnsConfig(
        const SingboxRoutingOptions(
          region: RoutingRegion.global,
          bypassLan: false,
        ),
      );

      expect(rules.any((rule) => rule['domain_suffix'] != null), isFalse);
      expect(rules.any((rule) => rule['ip_cidr'] != null), isFalse);
      expect(dns.containsKey('rules'), isFalse);
    });
  });

  group('Info-node detection and subscription usage', () {
    const sampleName = '📊 🖥 pc | ⏳ 28.2/50GB | 📅 12 روز';
    const sampleHost = 'status.hiddify-sellbot.invalid';

    test('Detects invalid/status hosts and usage names as metadata', () {
      expect(
        SafeProxyUri.isInfoMetadataProfile(
          host: sampleHost,
          port: 443,
          displayName: sampleName,
        ),
        isTrue,
      );
      expect(
        SafeProxyUri.isInfoMetadataProfile(
          host: '198.51.100.10',
          port: 443,
          displayName: 'DE-Reality-01',
        ),
        isFalse,
      );
    });

    test('Parses subscription-userinfo header bytes and expiry', () {
      final expirySeconds = DateTime.utc(2027, 1, 2).millisecondsSinceEpoch ~/
          Duration.millisecondsPerSecond;
      final info = SubscriptionUserInfo.parseHeader(<String, String>{
        'Content-Type': 'text/plain',
        'Subscription-Userinfo':
            'upload=1073741824; download=2147483648; total=53687091200; expire=$expirySeconds',
      });

      expect(info, isNotNull);
      expect(info!.usedBytes, 3 * 1024 * 1024 * 1024);
      expect(info.totalBytes, 50 * 1024 * 1024 * 1024);
      expect(info.remainingBytes, 47 * 1024 * 1024 * 1024);
      expect(info.usedFraction, closeTo(0.06, 0.001));
      expect(info.expiresAt, DateTime.utc(2027, 1, 2));
    });

    test('Parses Persian usage name fallback with days remaining', () {
      final now = DateTime.utc(2026, 11, 10);
      final info = SubscriptionUserInfo.parseInfoText(sampleName, now: now);

      expect(info, isNotNull);
      expect(info!.consumedBytes, closeTo(28.2 * 1024 * 1024 * 1024, 1));
      expect(info.totalBytes, 50 * 1024 * 1024 * 1024);
      expect(info.remainingDays(now), 12);
      expect(info.expiresAt, now.add(const Duration(days: 12)));
    });

    test('Filters status node and extracts usage in updater', () async {
      const infoLine =
          'trojan://1@status.hiddify-sellbot.invalid:443?security=tls&sni=status.hiddify-sellbot.invalid&insecure=0&allowInsecure=0&type=tcp&headerType=none#📊 🖥 pc | ⏳ 28.2/50GB | 📅 12 روز';
      const serverLine =
          'vless://00000000-0000-0000-0000-000000000001@198.51.100.10:443?type=tcp&security=reality&pbk=1111111111111111111111111111111111111111111=&fp=chrome#DE-Real';
      final body = base64Encode(utf8.encode('$infoLine\n$serverLine'));

      final updater = SubscriptionUpdater(
        httpClient: _FakeHttpClient((uri) async {
          return SubscriptionHttpResponse(statusCode: 200, body: body);
        }),
      );
      final result =
          await updater.fetchAndValidate('https://sub.speedll-sample.test/sub');

      expect(result.isSuccess, isTrue);
      expect(result.profiles, hasLength(1));
      expect(result.profiles.single.displayName, 'DE-Real');
      expect(result.profiles.single.extraParams['isInfoNode'], isNot(true));
      expect(result.userInfo, isNotNull);
      expect(result.userInfo!.consumedBytes,
          closeTo(28.2 * 1024 * 1024 * 1024, 1));
      expect(result.userInfo!.totalBytes, 50 * 1024 * 1024 * 1024);
    });

    test('Parses subscription-userinfo comment metadata', () {
      final info = SubscriptionUserInfo.parseBodyMetadata('''
#profile-title: Test
#subscription-userinfo: upload=0; download=1048576; total=10485760; expire=0
vless://00000000-0000-0000-0000-000000000001@198.51.100.10:443
''');
      expect(info, isNotNull);
      expect(info!.usedBytes, 1024 * 1024);
      expect(info.totalBytes, 10 * 1024 * 1024);
    });

    test('SubscriptionSource persists usage metadata', () {
      final source = SubscriptionSource(
        id: 'sub-test',
        name: 'Test',
        url: 'https://sub.speedll-sample.test/sub',
        userInfo: SubscriptionUserInfo(
          consumedBytes: 5 * 1024 * 1024 * 1024,
          totalBytes: 50 * 1024 * 1024 * 1024,
          expiresAt: DateTime.utc(2027, 1, 2),
        ),
      );
      final restored = SubscriptionSource.fromJson(source.toJson());

      expect(restored.userInfo, isNotNull);
      expect(restored.userInfo!.usedBytes, 5 * 1024 * 1024 * 1024);
      expect(restored.userInfo!.totalBytes, 50 * 1024 * 1024 * 1024);
      expect(restored.userInfo!.expiresAt, DateTime.utc(2027, 1, 2));
    });

    test('Prefers subscription-userinfo header over info-node name', () async {
      const infoLine =
          'trojan://1@status.invalid:443?security=tls&sni=status.invalid#📊 28.2/50GB | 📅 12 روز';
      const serverLine =
          'vless://00000000-0000-0000-0000-000000000001@198.51.100.10:443?type=tcp&security=reality&pbk=1111111111111111111111111111111111111111111=&fp=chrome#DE-Real';
      final body = base64Encode(utf8.encode('$infoLine\n$serverLine'));

      final updater = SubscriptionUpdater(
        httpClient: _FakeHttpClient((uri) async {
          return SubscriptionHttpResponse(
            statusCode: 200,
            body: body,
            headers: const <String, String>{
              'subscription-userinfo':
                  'upload=0; download=1073741824; total=10737418240; expire=0',
            },
          );
        }),
      );
      final result =
          await updater.fetchAndValidate('https://sub.speedll-sample.test/sub');

      expect(result.isSuccess, isTrue);
      expect(result.userInfo!.usedBytes, 1024 * 1024 * 1024);
      expect(result.userInfo!.totalBytes, 10 * 1024 * 1024 * 1024);
    });

    test('Extracts subscriber name from Trojan configs and info nodes', () {
      final nameFromInfo = SubscriptionSource.extractSubscriberName(
        url: 'https://panel.example.com/sub/user_token_abc',
        profiles: [
          const ServerProfile(
            id: 'info-1',
            displayName: '📊 👤 علی | ⏳ 28.2/50GB | 📅 12 روز',
            protocol: 'trojan',
            source: ProfileSource.subscription,
            extraParams: {'isInfoNode': true},
          ),
          const ServerProfile(
            id: 'tr-1',
            displayName: 'آلمان ۱',
            protocol: 'trojan',
            source: ProfileSource.subscription,
            extraParams: {'password': 'ali'},
          ),
        ],
      );
      expect(nameFromInfo, equals('علی'));

      final nameFromTrojanPass = SubscriptionSource.extractSubscriberName(
        url: 'https://panel.example.com/sub/token123',
        profiles: [
          const ServerProfile(
            id: 'tr-2',
            displayName: 'آلمان ۱',
            protocol: 'trojan',
            source: ProfileSource.subscription,
            extraParams: {'password': 'reza'},
          ),
        ],
      );
      expect(nameFromTrojanPass, equals('reza'));

      const subSource = SubscriptionSource(
        id: 'sub-1',
        name: 'اشتراک 4 (sub.example.com)',
        url: 'https://panel.example.com/sub/token123#ali',
      );
      expect(subSource.displayUserName, equals('اشتراک ali'));

      // Test Sample 1: 📊 🖥 pc | ⏳ 33.1/50GB | 📅 11 روز
      final nameFromPcSample = SubscriptionSource.extractSubscriberName(
        url: 'https://panel.example.com/sub/11112222-3333-4444-8555-666677778888/all.txt',
        profiles: [
          const ServerProfile(
            id: 'info-hiddify',
            displayName: '📊 🖥 pc | ⏳ 33.1/50GB | 📅 11 روز',
            protocol: 'trojan',
            source: ProfileSource.subscription,
            extraParams: {'isInfoNode': true},
          ),
        ],
      );
      expect(nameFromPcSample, equals('pc'));

      // Test base64 name decoding: base64:bW9qdGFiYQ== -> mojtaba
      const subBase64 = SubscriptionSource(
        id: 'sub-b64',
        name: 'base64:bW9qdGFiYQ==',
        url: 'https://panel.example.com/sub/user_mojtaba',
      );
      expect(subBase64.displayUserName, equals('اشتراک mojtaba'));

      // Test Sample 2 fallback: no name in fragment, uses smart fallback with short UUID
      final nameFromSample2 = SubscriptionSource.extractSubscriberName(
        url: 'https://panel.example.com/sub/11112222-3333-4444-8555-666677778888/all.txt',
        profiles: [
          const ServerProfile(
            id: 'info-time',
            displayName: '⏳ 20.553/50GB 📅 11 روز',
            protocol: 'trojan',
            source: ProfileSource.subscription,
            extraParams: {'isInfoNode': true},
          ),
        ],
      );
      expect(nameFromSample2, isNotNull);
      expect(nameFromSample2, contains('1111'));
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
