import 'dart:convert';
import '../models/server_profile.dart';
import 'hysteria2_parser.dart';
import 'shadowsocks_parser.dart';
import 'subscription_parser.dart';
import 'trojan_parser.dart';
import 'vless_parser.dart';
import 'vmess_parser.dart';

class SubscriptionDetector {
  const SubscriptionDetector({
    this.maxPayloadSizeBytes = 2 * 1024 * 1024, // 2 MB safety cap (DoS protection)
  });

  final int maxPayloadSizeBytes;

  static const List<SubscriptionParser> defaultParsers = <SubscriptionParser>[
    VlessParser(),
    VmessParser(),
    TrojanParser(),
    ShadowsocksParser(),
    Hysteria2Parser(),
  ];

  Future<ParseResult> detectAndParse(String rawInput) async {
    final trimmed = rawInput.trim();
    if (trimmed.isEmpty) {
      return ParseResult.failure('محتوای ورودی خالی است.');
    }

    if (trimmed.length > maxPayloadSizeBytes) {
      return ParseResult.failure(
        'اندازه ورودی (${trimmed.length} بایت) از حد مجاز ($maxPayloadSizeBytes بایت) فراتر است.',
      );
    }

    // Step 1: Check if content is a single direct URI
    for (final parser in defaultParsers) {
      if (parser.canParse(trimmed)) {
        return parser.parse(trimmed);
      }
    }

    // Step 2: Try decoding Base64 if it does not look like plain multiline text
    String decodedContent = trimmed;
    if (!trimmed.contains('\n') && !trimmed.contains('://')) {
      try {
        var normalized = trimmed.replaceAll('-', '+').replaceAll('_', '/').replaceAll(RegExp(r'\s+'), '');
        while (normalized.length % 4 != 0) {
          normalized += '=';
        }
        final bytes = base64Decode(normalized);
        decodedContent = utf8.decode(bytes);
      } catch (_) {
        // Not valid base64, proceed with original text
      }
    }

    // Step 3: Parse multiline subscription content
    final lines = decodedContent.split(RegExp(r'[\r\n]+'));
    final profiles = <ServerProfile>[];
    final allWarnings = <String>[];

    for (final line in lines) {
      final cleanLine = line.trim();
      if (cleanLine.isEmpty || cleanLine.startsWith('#')) {
        continue;
      }

      var parsed = false;
      for (final parser in defaultParsers) {
        if (parser.canParse(cleanLine)) {
          final result = await parser.parse(cleanLine);
          if (result.isSuccess) {
            profiles.addAll(result.profiles);
            allWarnings.addAll(result.warnings);
          } else if (result.errorMessage != null) {
            allWarnings.add('خطا در تحلیل ردیف: ${result.errorMessage}');
          }
          parsed = true;
          break;
        }
      }

      if (!parsed) {
        allWarnings.add('پروتکل ناشناخته یا فرمت نامعتبر: ${cleanLine.substring(0, cleanLine.length > 20 ? 20 : cleanLine.length)}...');
      }
    }

    if (profiles.isEmpty) {
      return ParseResult(
        isSuccess: false,
        errorMessage: 'هیچ کانفیگ معتبری در محتوای اشتراک یافت نشد.',
        warnings: allWarnings,
      );
    }

    return ParseResult.success(profiles, warnings: allWarnings);
  }
}
