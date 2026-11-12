import '../models/server_profile.dart';

class ParseResult {
  const ParseResult({
    required this.isSuccess,
    this.profiles = const <ServerProfile>[],
    this.warnings = const <String>[],
    this.errorMessage,
  });

  final bool isSuccess;
  final List<ServerProfile> profiles;
  final List<String> warnings;
  final String? errorMessage;

  factory ParseResult.failure(String message) {
    return ParseResult(
      isSuccess: false,
      errorMessage: message,
    );
  }

  factory ParseResult.success(
    List<ServerProfile> profiles, {
    List<String> warnings = const <String>[],
  }) {
    return ParseResult(
      isSuccess: true,
      profiles: profiles,
      warnings: warnings,
    );
  }
}

abstract interface class SubscriptionParser {
  String get parserName;

  bool canParse(String content);

  Future<ParseResult> parse(String content);
}

/// Safely splits and parses proxy URIs that may contain unencoded emojis, spaces,
/// brackets, pipes, or raw percent signs in the `#fragment` or query string.
class SafeProxyUri {
  const SafeProxyUri({
    required this.uri,
    required this.fragment,
    required this.rawInput,
  });

  final Uri uri;
  final String fragment;
  final String rawInput;

  static SafeProxyUri parse(String raw) {
    final cleaned = raw.replaceAll('\uFEFF', '').trim();
    final hashIndex = cleaned.indexOf('#');
    final beforeFragment =
        hashIndex >= 0 ? cleaned.substring(0, hashIndex).trim() : cleaned;
    final rawFragment =
        hashIndex >= 0 ? cleaned.substring(hashIndex + 1).trim() : '';

    final decodedFragment = decodeFragmentSafely(rawFragment);

    Uri? parsed = Uri.tryParse(beforeFragment);
    if (parsed == null) {
      // Encode characters that commonly appear unescaped in subscription query/path strings,
      // while preserving bracketed IPv6 host literals like `[2001:db8::1]` in the authority.
      final schemeEnd = beforeFragment.indexOf('://');
      final afterSchemeStart = schemeEnd >= 0 ? schemeEnd + 3 : 0;
      final pathOrQueryIdx = beforeFragment.indexOf(
        RegExp(r'[/?]'),
        afterSchemeStart,
      );
      final authorityPart = pathOrQueryIdx >= 0
          ? beforeFragment.substring(0, pathOrQueryIdx)
          : beforeFragment;
      final tailPart = pathOrQueryIdx >= 0
          ? beforeFragment.substring(pathOrQueryIdx)
          : '';
      final sanitizedTail = tailPart
          .replaceAll(' ', '%20')
          .replaceAll('|', '%7C')
          .replaceAll('[', '%5B')
          .replaceAll(']', '%5D');
      parsed = Uri.parse(
        '${authorityPart.replaceAll(' ', '%20')}$sanitizedTail',
      );
    }

    return SafeProxyUri(
      uri: parsed,
      fragment: decodedFragment,
      rawInput: cleaned,
    );
  }

  /// Trims [rawHost] and strips surrounding `[` `]` brackets when it represents
  /// a valid bracketed IPv6 literal (e.g. `[2001:db8::1]` -> `2001:db8::1`).
  static String normalizeHost(String rawHost) {
    final trimmed = rawHost.trim();
    if (trimmed.startsWith('[') && trimmed.endsWith(']') && trimmed.length > 2) {
      final inner = trimmed.substring(1, trimmed.length - 1).trim();
      try {
        Uri.parseIPv6Address(inner);
        return inner;
      } on FormatException {
        return trimmed;
      }
    }
    return trimmed;
  }

  static String decodeFragmentSafely(String rawFragment) {
    if (rawFragment.isEmpty) return '';
    try {
      return Uri.decodeComponent(rawFragment).trim();
    } catch (_) {
      // Handle stray '%' characters (e.g. "100%") without failing
      try {
        final escapedPercent = rawFragment.replaceAllMapped(
          RegExp(r'%(?![0-9a-fA-F]{2})'),
          (_) => '%25',
        );
        return Uri.decodeComponent(escapedPercent).trim();
      } catch (_) {
        return rawFragment.trim();
      }
    }
  }

  /// Computes a deterministic 8-hex-character FNV-1a hash so multiple configs
  /// sharing the same host/port/UUID in a subscription never collide on `profile.id`.
  static String stableHash(String input) {
    var hash = 0x811c9dc5;
    for (var i = 0; i < input.length; i++) {
      hash ^= input.codeUnitAt(i);
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  /// Detects whether a parsed server profile is a subscription metadata/info row
  /// (such as "Remaining Traffic: 45 GB" or "Days Left: 28" pointing to 127.0.0.1 / 0.0.0.0 / port 1).
  static bool isInfoMetadataProfile({
    required String host,
    required int port,
    required String displayName,
    String? uuid,
  }) {
    final lowerHost = host.trim().toLowerCase();
    if (lowerHost == '127.0.0.1' ||
        lowerHost == '0.0.0.0' ||
        lowerHost == 'localhost' ||
        lowerHost == '::1' ||
        lowerHost == '1.1.1.1' ||
        lowerHost == '8.8.8.8' ||
        lowerHost.endsWith('.invalid') ||
        lowerHost == 'invalid' ||
        lowerHost.startsWith('status.') ||
        lowerHost.startsWith('info.') ||
        lowerHost.startsWith('usage.') ||
        lowerHost.startsWith('traffic.') ||
        port <= 5) {
      return true;
    }
    if (uuid != null && uuid.trim() == '00000000-0000-0000-0000-000000000000') {
      return true;
    }

    final lowerName = displayName.trim().toLowerCase();
    final volumePair = RegExp(
      r'(\d+(?:[.,]\d+)?)\s*(?:gb|mb|tb|گیگ(?:ابایت)?|مگ(?:ابایت)?|ترابایت)?'
      r'\s*(?:/|از|of)\s*(\d+(?:[.,]\d+)?)\s*'
      r'(?:gb|mb|tb|گیگ(?:ابایت)?|مگ(?:ابایت)?|ترابایت)',
      caseSensitive: false,
    );
    final statusWord = RegExp(
      r'(remaining|used|usage|traffic|volume|expire|expiry|days?|'
      r'باقی|مصرف|حجم|انقضا|روز)',
      caseSensitive: false,
    );
    if (volumePair.hasMatch(lowerName) && statusWord.hasMatch(lowerName)) {
      return true;
    }
    return false;
  }
}
