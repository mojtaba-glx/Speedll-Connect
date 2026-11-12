import 'dart:convert';
import '../models/server_profile.dart';
import 'anytls_parser.dart';
import 'clash_parser.dart';
import 'hysteria2_parser.dart';
import 'hysteria_parser.dart';
import 'shadowsocks_parser.dart';
import 'singbox_json_parser.dart';
import 'subscription_parser.dart';
import 'trojan_parser.dart';
import 'tuic_parser.dart';
import 'vless_parser.dart';
import 'vmess_parser.dart';
import 'wireguard_parser.dart';

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
    HysteriaParser(),
    TuicParser(),
    AnyTlsParser(),
    WireguardParser(),
  ];

  static const List<SubscriptionParser> documentParsers = <SubscriptionParser>[
    ClashYamlParser(),
    SingboxJsonParser(),
    WireguardParser(),
  ];

  Future<ParseResult> detectAndParse(String rawInput) async {
    final trimmed = rawInput.replaceAll('\uFEFF', '').trim();
    if (trimmed.isEmpty) {
      return ParseResult.failure('محتوای ورودی خالی است.');
    }

    if (trimmed.length > maxPayloadSizeBytes) {
      return ParseResult.failure(
        'اندازه ورودی (${trimmed.length} بایت) از حد مجاز ($maxPayloadSizeBytes بایت) فراتر است.',
      );
    }

    // Step 1: Check if content is a single-line direct URI
    if (!trimmed.contains('\n') && !trimmed.contains('\r')) {
      for (final parser in defaultParsers) {
        if (parser.canParse(trimmed)) {
          return parser.parse(trimmed);
        }
      }
    }

    // Step 2: Strip comment/metadata lines (# or //) and try Base64 decoding if no scheme (://) is present
    String decodedContent = trimmed;
    final initialLines = trimmed
        .split(RegExp(r'[\r\n]+'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !l.startsWith('#') && !l.startsWith('//'))
        .toList();

    final joinedNonComments = initialLines.join('');
    if (joinedNonComments.isNotEmpty && !joinedNonComments.contains('://')) {
      try {
        var normalized = joinedNonComments
            .replaceAll('-', '+')
            .replaceAll('_', '/')
            .replaceAll(RegExp(r'\s+'), '');
        while (normalized.length % 4 != 0) {
          normalized += '=';
        }
        final bytes = base64Decode(normalized);
        decodedContent = utf8.decode(bytes, allowMalformed: true);
      } catch (_) {
        // Not valid base64, proceed with original text
      }
    }

    // Step 3: Try whole-document formats (Clash YAML, sing-box JSON)
    for (final parser in documentParsers) {
      if (parser.canParse(decodedContent)) {
        final result = await parser.parse(decodedContent);
        if (result.isSuccess && result.profiles.isNotEmpty) {
          return result;
        }
      }
    }

    // Step 4: Parse multiline subscription content line by line
    final lines = decodedContent.split(RegExp(r'[\r\n]+'));
    final profiles = <ServerProfile>[];
    final allWarnings = <String>[];

    for (final line in lines) {
      final cleanLine = line.replaceAll('\uFEFF', '').trim();
      if (cleanLine.isEmpty ||
          cleanLine.startsWith('#') ||
          cleanLine.startsWith('//')) {
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
        allWarnings.add(
          'پروتکل ناشناخته یا فرمت نامعتبر: ${cleanLine.substring(0, cleanLine.length > 20 ? 20 : cleanLine.length)}...',
        );
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
