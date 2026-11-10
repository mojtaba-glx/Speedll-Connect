import 'package:test/test.dart';
import 'package:speedll_subscription/speedll_subscription.dart';

void main() {
  group('ServerProfile & Migration Tests', () {
    test('ServerProfile serialize and deserialize accurately', () {
      const profile = ServerProfile(
        id: 'srv-1',
        displayName: 'آلمان ۱',
        protocol: 'vless',
        source: ProfileSource.subscription,
        serverAddress: '198.51.100.1',
        serverPort: 443,
      );

      final json = profile.toJson();
      expect(json['schemaVersion'], equals(1));
      expect(json['id'], equals('srv-1'));
      expect(json['displayName'], equals('آلمان ۱'));
      expect(json['protocol'], equals('vless'));
      expect(json['source'], equals('subscription'));

      final restored = ServerProfile.fromJson(json);
      expect(restored.id, equals(profile.id));
      expect(restored.displayName, equals(profile.displayName));
      expect(restored.serverPort, equals(443));
      expect(restored.schemaVersion, equals(1));
    });

    test('ProfileMigrator upgrades legacy v0 unversioned profile to v1', () {
      final legacyJson = <String, dynamic>{
        'id': 'legacy-99',
        'displayName': 'سرور قدیمی',
        'protocol': 'VMESS',
        'source': 'manual',
      };

      const migrator = ProfileMigrator();
      final migratedJson = migrator.migrateRawJson(legacyJson);

      expect(migratedJson['schemaVersion'], equals(1));
      expect(migratedJson['protocol'], equals('vmess'));
      expect(migratedJson['createdAt'], isNotNull);

      final profile = ServerProfile.fromJson(migratedJson);
      expect(profile.schemaVersion, equals(1));
      expect(profile.id, equals('legacy-99'));
    });

    test('ProfileValidator detects invalid port or missing id', () {
      const validator = ProfileValidator();

      const invalidProfile = ServerProfile(
        id: '',
        displayName: 'بدون آیدی',
        protocol: 'unknown_proto',
        source: ProfileSource.manual,
        serverPort: 70000,
      );

      final result = validator.validate(invalidProfile);
      expect(result.isValid, isFalse);
      expect(result.errors.length, greaterThanOrEqualTo(2));

      const validProfile = ServerProfile(
        id: 'srv-ok',
        displayName: 'سرور معتبر',
        protocol: 'vless',
        source: ProfileSource.subscription,
        serverPort: 443,
      );

      final validResult = validator.validate(validProfile);
      expect(validResult.isValid, isTrue);
    });
  });
}
