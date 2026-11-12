import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:meta/meta.dart';

import '../models/server_profile.dart';
import '../parsers/subscription_detector.dart';
import '../parsers/subscription_parser.dart';
import '../validators/profile_validator.dart';

/// Usage and expiry metadata reported by a subscription provider.
@immutable
class SubscriptionUserInfo {
  const SubscriptionUserInfo({
    this.uploadBytes,
    this.downloadBytes,
    this.consumedBytes,
    this.totalBytes,
    this.expiresAt,
  });

  final int? uploadBytes;
  final int? downloadBytes;
  final int? consumedBytes;
  final int? totalBytes;
  final DateTime? expiresAt;

  int? get usedBytes {
    if (uploadBytes != null || downloadBytes != null) {
      return (uploadBytes ?? 0) + (downloadBytes ?? 0);
    }
    return consumedBytes;
  }

  int? get remainingBytes {
    final total = totalBytes;
    final used = usedBytes;
    if (total == null || total <= 0 || used == null) return null;
    return (total - used).clamp(0, total).toInt();
  }

  double? get usedFraction {
    final total = totalBytes;
    final used = usedBytes;
    if (total == null || total <= 0 || used == null) return null;
    return (used / total).clamp(0.0, 1.0).toDouble();
  }

  int? remainingDays([DateTime? now]) {
    final expiry = expiresAt;
    if (expiry == null) return null;
    final diff = expiry.difference(now ?? DateTime.now());
    if (diff.inHours <= 0) return 0;
    return (diff.inHours / 24).ceil();
  }

  bool get hasAnyValue =>
      uploadBytes != null ||
      downloadBytes != null ||
      consumedBytes != null ||
      totalBytes != null ||
      expiresAt != null;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      if (uploadBytes != null) 'uploadBytes': uploadBytes,
      if (downloadBytes != null) 'downloadBytes': downloadBytes,
      if (consumedBytes != null) 'consumedBytes': consumedBytes,
      if (totalBytes != null) 'totalBytes': totalBytes,
      if (expiresAt != null) 'expiresAt': expiresAt!.toUtc().toIso8601String(),
    };
  }

  factory SubscriptionUserInfo.fromJson(Map<String, dynamic> json) {
    final rawExpiry = json['expiresAt'] as String?;
    return SubscriptionUserInfo(
      uploadBytes: _asInt(json['uploadBytes']),
      downloadBytes: _asInt(json['downloadBytes']),
      consumedBytes: _asInt(json['consumedBytes']),
      totalBytes: _asInt(json['totalBytes']),
      expiresAt: rawExpiry != null ? DateTime.tryParse(rawExpiry) : null,
    );
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  /// Formats byte counts into human-readable Persian/English volume strings (e.g. "32.4 GB").
  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var index = 0;
    while (value >= 1024 && index < units.length - 1) {
      value /= 1024;
      index++;
    }
    final formatted = value >= 100
        ? value.toStringAsFixed(0)
        : value >= 10
            ? value.toStringAsFixed(1)
            : value.toStringAsFixed(2);
    return '$formatted ${units[index]}';
  }

  static SubscriptionUserInfo? parseHeader(Map<String, String> headers) {
    String? raw;
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == 'subscription-userinfo') {
        raw = entry.value;
        break;
      }
    }
    if (raw == null || raw.trim().isEmpty) return null;

    final values = <String, String>{};
    for (final part in raw.split(';')) {
      final separator = part.indexOf('=');
      if (separator <= 0) continue;
      values[part.substring(0, separator).trim().toLowerCase()] =
          part.substring(separator + 1).trim().replaceAll('"', '');
    }
    if (values.isEmpty) return null;

    final total = _asInt(values['total'] ?? values['totl']);
    final upload = _asInt(values['upload']);
    final download = _asInt(values['download']);
    final expiresAt = _parseExpire(values['expire']);

    final info = SubscriptionUserInfo(
      uploadBytes: upload,
      downloadBytes: download,
      totalBytes: total == null || total <= 0 ? null : total,
      expiresAt: expiresAt,
    );
    return info.hasAnyValue ? info : null;
  }

  static SubscriptionUserInfo? parseBodyMetadata(String body) {
    final match = RegExp(
      r'^\s*(?:#|//)?\s*subscription-userinfo\s*:\s*(.+)$',
      caseSensitive: false,
      multiLine: true,
    ).firstMatch(body);
    if (match == null) return null;
    return parseHeader(<String, String>{
      'subscription-userinfo': match.group(1)!.trim(),
    });
  }

  static SubscriptionUserInfo? parseInfoText(String text, {DateTime? now}) {
    final normalized = _toAsciiDigits(text);
    final pair = RegExp(
      r'(\d+(?:[.,]\d+)?)\s*'
      r'(GB|MB|TB|گیگابایت|گیگ|مگابایت|مگ|ترابایت|ترا)?\s*'
      r'(?:/|از|of)\s*'
      r'(\d+(?:[.,]\d+)?)\s*'
      r'(GB|MB|TB|گیگابایت|گیگ|مگابایت|مگ|ترابایت|ترا)',
      caseSensitive: false,
    ).firstMatch(normalized);

    int? consumed;
    int? total;
    if (pair != null) {
      final unit = _unitBytes(pair.group(4));
      final first = _asDouble(pair.group(1));
      final second = _asDouble(pair.group(3));
      if (unit != null && first != null && second != null) {
        var a = first;
        var b = second;
        if (a > b) {
          final swap = a;
          a = b;
          b = swap;
        }
        total = (b * unit).round();
        final remainingHint = normalized.contains('باقی') ||
            normalized.toLowerCase().contains('remaining');
        consumed =
            remainingHint ? (total - (a * unit).round()) : (a * unit).round();
        consumed = consumed.clamp(0, total).toInt();
      }
    }

    DateTime? expiresAt;
    final dateMatch =
        RegExp(r'(20\d{2})[-/](\d{1,2})[-/](\d{1,2})').firstMatch(normalized);
    if (dateMatch != null) {
      expiresAt = DateTime.tryParse(
        '${dateMatch.group(1)}-${dateMatch.group(2)!.padLeft(2, '0')}-'
        '${dateMatch.group(3)!.padLeft(2, '0')}',
      )?.toUtc();
    }
    expiresAt ??= _expiryFromDays(normalized, now: now);

    final info = SubscriptionUserInfo(
      consumedBytes: consumed,
      totalBytes: total,
      expiresAt: expiresAt,
    );
    return info.hasAnyValue ? info : null;
  }

  static SubscriptionUserInfo merge(
    SubscriptionUserInfo? primary,
    SubscriptionUserInfo? fallback,
  ) {
    if (primary == null) return fallback ?? const SubscriptionUserInfo();
    if (fallback == null) return primary;
    return SubscriptionUserInfo(
      uploadBytes: primary.uploadBytes ?? fallback.uploadBytes,
      downloadBytes: primary.downloadBytes ?? fallback.downloadBytes,
      consumedBytes: primary.consumedBytes ?? fallback.consumedBytes,
      totalBytes: primary.totalBytes ?? fallback.totalBytes,
      expiresAt: primary.expiresAt ?? fallback.expiresAt,
    );
  }

  static DateTime? _expiryFromDays(String text, {DateTime? now}) {
    final match = RegExp(r'(\d+)\s*(?:روز|days?|روز دیگر)').firstMatch(text);
    if (match == null) return null;
    final days = int.tryParse(match.group(1) ?? '');
    if (days == null) return null;
    return (now ?? DateTime.now()).toUtc().add(Duration(days: days));
  }

  static DateTime? _parseExpire(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final numeric = int.tryParse(raw.trim());
    if (numeric != null) {
      if (numeric <= 0) return null;
      final millis = numeric > 100000000000 ? numeric : numeric * 1000;
      return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
    }
    return DateTime.tryParse(raw.trim())?.toUtc();
  }

  static String _toAsciiDigits(String input) {
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      final char = String.fromCharCode(rune);
      final pi = persian.indexOf(char);
      final ai = arabic.indexOf(char);
      if (pi >= 0) {
        buffer.write(pi);
      } else if (ai >= 0) {
        buffer.write(ai);
      } else {
        buffer.write(char);
      }
    }
    return buffer.toString();
  }

  static double? _asDouble(String? value) {
    if (value == null) return null;
    return double.tryParse(value.replaceAll(',', '.'));
  }

  static int? _unitBytes(String? unit) {
    switch (unit?.toUpperCase()) {
      case 'TB':
      case 'ترابایت':
      case 'ترا':
        return 1024 * 1024 * 1024 * 1024;
      case 'GB':
      case 'گیگابایت':
      case 'گیگ':
        return 1024 * 1024 * 1024;
      case 'MB':
      case 'مگابایت':
      case 'مگ':
        return 1024 * 1024;
      default:
        return null;
    }
  }
}

/// Represents a saved subscription link metadata entry.
@immutable
class SubscriptionSource {
  const SubscriptionSource({
    required this.id,
    required this.name,
    required this.url,
    this.autoUpdate = true,
    this.updateIntervalMinutes = 360,
    this.lastUpdatedAt,
    this.lastStatusMessage,
    this.userInfo,
    this.subscriberName,
  });

  final String id;
  final String name;
  final String url;
  final bool autoUpdate;
  final int updateIntervalMinutes;
  final DateTime? lastUpdatedAt;
  final String? lastStatusMessage;
  final SubscriptionUserInfo? userInfo;
  final String? subscriberName;

  static bool _isValidSubscriberName(String candidate) {
    if (candidate.isEmpty || candidate.length > 28) return false;
    final lower = candidate.toLowerCase();
    if (lower == 'status' ||
        lower == 'traffic' ||
        lower == 'volume' ||
        lower == 'gb' ||
        lower == 'mb' ||
        lower == 'tb') {
      return false;
    }
    if (RegExp(r'^\d+(?:\.\d+)?$').hasMatch(candidate)) return false;
    if (candidate.contains('.') &&
        (candidate.endsWith('.ir') ||
            candidate.endsWith('.com') ||
            candidate.endsWith('.net') ||
            candidate.endsWith('.org') ||
            candidate.endsWith('.invalid'))) {
      return false;
    }
    return true;
  }

  static String? _extractNameFromDisplayName(String rawName) {
    final name = rawName.trim();
    if (name.isEmpty) return null;

    // Pattern 1: 📊 [emojis/symbols/spaces] <name> [| or ⏳ or 📅 or end]
    // Handles: "📊 🖥 pc | ⏳ 33.1/50GB", "📊 📱 ali | ...", "📊 reza | ...", "📊 👤 user123"
    final statusMatch = RegExp(
      r'📊[^\w\u0600-\u06FF]*([a-zA-Z0-9_\u0600-\u06FF\-\.\s]+?)(?:\s*(?:\||⏳|📅|\n|$))',
      unicode: true,
    ).firstMatch(name);
    if (statusMatch != null) {
      final cand = statusMatch.group(1)!.trim();
      if (_isValidSubscriberName(cand)) return cand;
    }

    // Pattern 2: 👤, 🧑, 👨, 👩 <name>
    final personMatch = RegExp(
      r'[👤🧑👨👩]\s*([a-zA-Z0-9_\u0600-\u06FF\-\.\s]+?)(?:\s*(?:\||⏳|📅|\n|$))',
      unicode: true,
    ).firstMatch(name);
    if (personMatch != null) {
      final cand = personMatch.group(1)!.trim();
      if (_isValidSubscriberName(cand)) return cand;
    }

    // Pattern 3: کاربر: <name> or User: <name> or account: <name>
    final labelMatch = RegExp(
      r'(?:کاربر|user|client|account|subscriber)\s*[:：]\s*([a-zA-Z0-9_\u0600-\u06FF\-\.\s]+?)(?:\s*(?:\||⏳|📅|\n|$))',
      caseSensitive: false,
    ).firstMatch(name);
    if (labelMatch != null) {
      final cand = labelMatch.group(1)!.trim();
      if (_isValidSubscriberName(cand)) return cand;
    }

    return null;
  }

  static String? tryDecodeBase64(String raw) {
    var s = raw.trim();
    if (s.startsWith('base64:')) {
      s = s.substring(7).trim();
    }
    if (s.isEmpty) return null;
    try {
      var padded = s.replaceAll('-', '+').replaceAll('_', '/');
      while (padded.length % 4 != 0) {
        padded += '=';
      }
      final decoded = utf8.decode(base64Decode(padded));
      if (decoded.isNotEmpty && !decoded.contains('\x00')) {
        return decoded.trim();
      }
    } catch (_) {}
    return null;
  }

  /// Generates a pleasant, deterministic, human-friendly subscriber name from
  /// URL hash and short UUID tokens when no explicit name is provided in the subscription.
  static String generateSmartFallbackName(String url) {
    const titles = <String>[
      'کاربر ویژه',
      'کاربر طلایی',
      'کاربر VIP',
      'کاربر الماس',
      'کاربر پیشتاز',
      'کاربر برتر',
      'کاربر ستاره',
    ];
    final uuidMatch = RegExp(
      r'[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}',
      caseSensitive: false,
    ).firstMatch(url);
    final shortId = uuidMatch?.group(0)?.substring(0, 4);
    final index = url.hashCode.abs() % titles.length;
    final title = titles[index];
    return shortId != null ? '$title ($shortId)' : title;
  }

  /// Extracts the human-readable subscriber name using all available clues:
  /// response headers, body metadata, profile display names (e.g. Trojan status
  /// nodes or prefixes), Trojan credentials/extraParams, or URL fragments/queries.
  static String? extractSubscriberName({
    required String url,
    List<ServerProfile>? profiles,
    String? responseBody,
    Map<String, String>? responseHeaders,
  }) {
    // 0. Check base64 encoded URL or input
    if (url.startsWith('base64:')) {
      final decoded = tryDecodeBase64(url);
      if (decoded != null && _isValidSubscriberName(decoded)) {
        return decoded;
      }
    }

    // 1. From response headers (e.g. profile-title or content-disposition)
    if (responseHeaders != null) {
      for (final entry in responseHeaders.entries) {
        final k = entry.key.toLowerCase();
        if (k == 'profile-title' || k == 'x-profile-title') {
          final title = entry.value.trim();
          if (title.isNotEmpty && !title.contains('.')) return title;
        }
        if (k == 'content-disposition') {
          final fnMatch = RegExp(r'filename\*?=(?:UTF-8'')?"?([^";\n\r]+)"?')
              .firstMatch(entry.value);
          if (fnMatch != null) {
            var rawFn = fnMatch.group(1)?.trim() ?? '';
            rawFn = rawFn
                .replaceAll(RegExp(r'\.(txt|yaml|yml|json|conf)$'), '')
                .trim();
            if (rawFn.isNotEmpty && !rawFn.contains('.') && rawFn.length <= 28) {
              return Uri.decodeComponent(rawFn);
            }
          }
        }
      }
    }

    // 2. From response body metadata (#profile-title: ...)
    if (responseBody != null) {
      final bodyTitleMatch = RegExp(
        r'^\s*(?:#|//)\s*profile-title\s*:\s*(.+)$',
        caseSensitive: false,
        multiLine: true,
      ).firstMatch(responseBody);
      if (bodyTitleMatch != null) {
        final val = bodyTitleMatch.group(1)!.trim();
        if (val.isNotEmpty && !val.contains('.')) {
          return val;
        }
      }
    }

    // 3. From profiles (Info nodes, Trojan configs, remark patterns)
    if (profiles != null && profiles.isNotEmpty) {
      // Prioritize info nodes first (like status nodes, hiddify sellbot, trojan info)
      for (final p in profiles) {
        final name = p.displayName.trim();
        final extracted = _extractNameFromDisplayName(name);
        if (extracted != null && extracted.isNotEmpty) {
          return extracted;
        }
      }

      // Check Trojan configs specifically: password/userinfo or extraParams['username']
      for (final p in profiles) {
        if (p.protocol.toLowerCase() == 'trojan') {
          for (final key in [
            'user',
            'username',
            'name',
            'client',
            'remark',
            'title',
          ]) {
            final val = p.extraParams[key]?.toString().trim();
            if (val != null &&
                val.isNotEmpty &&
                !val.contains('.') &&
                val.length <= 28) {
              return val;
            }
          }
          final pass = p.extraParams['password']?.toString().trim() ?? '';
          final isUuid = RegExp(
            r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$',
            caseSensitive: false,
          ).hasMatch(pass);
          final isHexHash =
              RegExp(r'^[a-f0-9]{30,}$', caseSensitive: false).hasMatch(pass);
          if (pass.isNotEmpty &&
              !isUuid &&
              !isHexHash &&
              pass.length >= 3 &&
              pass.length <= 20 &&
              !pass.contains('.') &&
              !RegExp(r'^\d+$').hasMatch(pass)) {
            return pass;
          }
        }
      }

      // Check common bracketed tag across profiles: [Ali] DE-1, [Ali] TR-1
      final bracketCounts = <String, int>{};
      for (final p in profiles.take(20)) {
        final bMatch = RegExp(r'\[([^\]]+)\]').firstMatch(p.displayName);
        if (bMatch != null) {
          final tag = bMatch.group(1)!.trim();
          if (tag.isNotEmpty && tag.length <= 24 && !tag.contains('.')) {
            bracketCounts[tag] = (bracketCounts[tag] ?? 0) + 1;
          }
        }
      }
      for (final entry in bracketCounts.entries) {
        if (entry.value >= 2) {
          return entry.key;
        }
      }
    }

    // 4. From URL query, fragment, or path
    final uri = Uri.tryParse(url);
    if (uri != null) {
      if (uri.fragment.trim().isNotEmpty) {
        final frag = Uri.decodeComponent(uri.fragment.trim());
        if (frag.isNotEmpty && !frag.contains('.') && frag.length <= 28) {
          if (frag.startsWith('base64:')) {
            final decoded = tryDecodeBase64(frag);
            if (decoded != null && _isValidSubscriberName(decoded)) {
              return decoded;
            }
          } else {
            return frag;
          }
        }
      }
      for (final key in [
        'name',
        'user',
        'username',
        'remark',
        'title',
        'client',
      ]) {
        final val = uri.queryParameters[key]?.trim();
        if (val != null && val.isNotEmpty && !val.contains('.')) {
          return Uri.decodeComponent(val);
        }
      }
      final segments =
          uri.pathSegments.where((s) => s.trim().isNotEmpty).toList();
      if (segments.isNotEmpty) {
        final subIdx = segments.indexWhere((s) => s.toLowerCase() == 'sub');
        if (subIdx >= 0 && subIdx + 1 < segments.length) {
          final candidate = segments[subIdx + 1].trim();
          if (candidate.isNotEmpty &&
              !candidate.contains('.') &&
              candidate.length <= 28 &&
              !RegExp(r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$', caseSensitive: false).hasMatch(candidate)) {
            return Uri.decodeComponent(candidate);
          }
        }
        final last = segments.last.trim();
        if (!last.contains('.') &&
            last.length <= 24 &&
            !RegExp(r'^[a-f0-9]{30,}$').hasMatch(last)) {
          return Uri.decodeComponent(last);
        }
      }
    }

    // 5. Smart fallback based on URL/hash
    if (url.trim().isNotEmpty) {
      return generateSmartFallbackName(url);
    }

    return null;
  }

  /// Returns the human-readable user name associated with this subscription,
  /// preferring custom user names, URL fragments (#ali), or query/path parameters
  /// over raw domain names (e.g. 'panel.example.com').
  String get displayUserName {
    if (subscriberName != null && subscriberName!.trim().isNotEmpty) {
      final s = subscriberName!.trim();
      return s.startsWith('اشتراک ') ? s : 'اشتراک $s';
    }

    final trimmedName = name.trim();

    // If name is base64 encoded (e.g. "base64:bW9qdGFiYQ=="), decode it!
    if (trimmedName.startsWith('base64:')) {
      final decoded = tryDecodeBase64(trimmedName);
      if (decoded != null && _isValidSubscriberName(decoded)) {
        return decoded.startsWith('اشتراک ') ? decoded : 'اشتراک $decoded';
      }
    }

    final isDomainLike = trimmedName.contains('.') &&
        (trimmedName.endsWith('.ir') ||
            trimmedName.endsWith('.com') ||
            trimmedName.endsWith('.net') ||
            trimmedName.endsWith('.org') ||
            trimmedName.endsWith('.xyz') ||
            trimmedName.endsWith('.site') ||
            trimmedName.endsWith('.top') ||
            trimmedName.startsWith('http://') ||
            trimmedName.startsWith('https://'));

    final hasDomainInParentheses =
        RegExp(r'\([a-zA-Z0-9.-]+\.[a-zA-Z]{2,}\)').hasMatch(trimmedName);

    if (!isDomainLike &&
        !hasDomainInParentheses &&
        trimmedName.isNotEmpty &&
        !trimmedName.startsWith('sub_') &&
        !trimmedName.startsWith('base64:') &&
        !RegExp(r'^اشتراک\s*\d+$').hasMatch(trimmedName)) {
      return trimmedName.startsWith('اشتراک ')
          ? trimmedName
          : 'اشتراک $trimmedName';
    }

    final fromUrl = extractSubscriberName(url: url);
    if (fromUrl != null && fromUrl.isNotEmpty) {
      return fromUrl.startsWith('اشتراک ') ? fromUrl : 'اشتراک $fromUrl';
    }

    // Strip domain if name was like "اشتراک 4 (sub.example.com)"
    final cleanDefault =
        trimmedName.replaceAll(RegExp(r'\s*\([^\)]+\)'), '').trim();
    if (cleanDefault.isNotEmpty &&
        !cleanDefault.contains('.') &&
        !cleanDefault.startsWith('base64:')) {
      return cleanDefault;
    }

    return 'اشتراک ${generateSmartFallbackName(url)}';
  }

  SubscriptionSource copyWith({
    String? id,
    String? name,
    String? url,
    bool? autoUpdate,
    int? updateIntervalMinutes,
    DateTime? lastUpdatedAt,
    String? lastStatusMessage,
    SubscriptionUserInfo? userInfo,
    String? subscriberName,
  }) {
    return SubscriptionSource(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      autoUpdate: autoUpdate ?? this.autoUpdate,
      updateIntervalMinutes:
          updateIntervalMinutes ?? this.updateIntervalMinutes,
      lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
      lastStatusMessage: lastStatusMessage ?? this.lastStatusMessage,
      userInfo: userInfo ?? this.userInfo,
      subscriberName: subscriberName ?? this.subscriberName,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'url': url,
      'autoUpdate': autoUpdate,
      'updateIntervalMinutes': updateIntervalMinutes,
      if (lastUpdatedAt != null)
        'lastUpdatedAt': lastUpdatedAt!.toIso8601String(),
      if (lastStatusMessage != null) 'lastStatusMessage': lastStatusMessage,
      if (userInfo != null) 'userInfo': userInfo!.toJson(),
      if (subscriberName != null) 'subscriberName': subscriberName,
    };
  }

  factory SubscriptionSource.fromJson(Map<String, dynamic> json) {
    final rawUpdated = json['lastUpdatedAt'] as String?;
    return SubscriptionSource(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'اشتراک',
      url: json['url'] as String? ?? '',
      autoUpdate: json['autoUpdate'] as bool? ?? true,
      updateIntervalMinutes: json['updateIntervalMinutes'] as int? ?? 360,
      lastUpdatedAt: rawUpdated != null ? DateTime.tryParse(rawUpdated) : null,
      lastStatusMessage: json['lastStatusMessage'] as String?,
      userInfo: json['userInfo'] is Map
          ? SubscriptionUserInfo.fromJson(
              Map<String, dynamic>.from(json['userInfo'] as Map),
            )
          : null,
      subscriberName: json['subscriberName'] as String?,
    );
  }
}

@immutable
class SubscriptionHttpResponse {
  const SubscriptionHttpResponse({
    required this.statusCode,
    required this.body,
    this.headers = const <String, String>{},
    this.redirectLocation,
  });

  final int statusCode;
  final String body;
  final Map<String, String> headers;
  final String? redirectLocation;
}

/// Abstract HTTP client interface to allow deterministic offline testing.
abstract interface class SubscriptionHttpClient {
  Future<SubscriptionHttpResponse> get(
    Uri uri, {
    required Duration timeout,
    required int maxBytes,
  });
}

/// Default pure Dart HTTP client with strict size cap, manual redirect control, and timeout.
class DartIoSubscriptionHttpClient implements SubscriptionHttpClient {
  const DartIoSubscriptionHttpClient();

  @override
  Future<SubscriptionHttpResponse> get(
    Uri uri, {
    required Duration timeout,
    required int maxBytes,
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      request.followRedirects = false;
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'v2rayNG/1.8.23 SpeedllConnect/1.1 (sing-box)',
      );
      request.headers.set(HttpHeaders.acceptHeader, 'text/plain, */*');

      final response = await request.close().timeout(timeout);
      final headers = <String, String>{};
      response.headers.forEach((name, values) {
        if (values.isNotEmpty) {
          headers[name.toLowerCase()] = values.join(', ');
        }
      });

      final redirectLocation =
          response.headers.value(HttpHeaders.locationHeader);

      if (response.isRedirect ||
          (response.statusCode >= 300 && response.statusCode < 400)) {
        return SubscriptionHttpResponse(
          statusCode: response.statusCode,
          body: '',
          headers: headers,
          redirectLocation: redirectLocation,
        );
      }

      if (response.contentLength > maxBytes) {
        throw FormatException(
          'حجم پاسخ سرور (${response.contentLength} بایت) بیش از سقف مجاز ($maxBytes بایت) است.',
        );
      }

      final bytesBuilder = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(timeout)) {
        if (bytesBuilder.length + chunk.length > maxBytes) {
          throw FormatException(
            'حجم جریان دریافتی از سقف مجاز ($maxBytes بایت) فراتر رفت.',
          );
        }
        bytesBuilder.add(chunk);
      }

      final body = utf8.decode(bytesBuilder.takeBytes(), allowMalformed: true);
      return SubscriptionHttpResponse(
        statusCode: response.statusCode,
        body: body,
        headers: headers,
      );
    } finally {
      client.close(force: true);
    }
  }
}

@immutable
class SubscriptionUpdateResult {
  const SubscriptionUpdateResult({
    required this.isSuccess,
    this.profiles = const <ServerProfile>[],
    this.warnings = const <String>[],
    this.errorMessage,
    this.isOfflineError = false,
    this.userInfo,
    this.subscriberName,
  });

  final bool isSuccess;
  final List<ServerProfile> profiles;
  final List<String> warnings;
  final String? errorMessage;
  final bool isOfflineError;
  final SubscriptionUserInfo? userInfo;
  final String? subscriberName;
}

/// Handles secure fetching, SSRF protection, response validation, and periodic background updates for subscriptions.
class SubscriptionUpdater {
  SubscriptionUpdater({
    SubscriptionHttpClient? httpClient,
    SubscriptionDetector? detector,
    ProfileValidator? validator,
    this.timeout = const Duration(seconds: 15),
    this.maxPayloadSizeBytes = 2 * 1024 * 1024,
    this.maxRedirects = 3,
    this.allowInsecureHttp = false,
  })  : _httpClient = httpClient ?? const DartIoSubscriptionHttpClient(),
        _detector = detector ??
            SubscriptionDetector(maxPayloadSizeBytes: maxPayloadSizeBytes),
        _validator = validator ?? const ProfileValidator();

  final SubscriptionHttpClient _httpClient;
  final SubscriptionDetector _detector;
  final ProfileValidator _validator;
  final Duration timeout;
  final int maxPayloadSizeBytes;
  final int maxRedirects;
  final bool allowInsecureHttp;

  Timer? _periodicTimer;
  bool _isRefreshing = false;

  bool get isPeriodicActive => _periodicTimer?.isActive ?? false;
  bool get isRefreshing => _isRefreshing;

  /// Redacts query parameters, userinfo, and path tokens so secrets never leak in logs or UI errors.
  static String redactUrl(String rawUrl) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || uri.host.isEmpty) {
      return '[REDACTED_URL]';
    }
    return '${uri.scheme}://${uri.host}${uri.hasPort ? ":${uri.port}" : ""}/***';
  }

  /// Validates a subscription URL against SSRF, private IP ranges, loopback, and disallowed schemes.
  String? validateSubscriptionUrl(Uri? uri) {
    if (uri == null || !uri.hasScheme || uri.host.trim().isEmpty) {
      return 'آدرس لینک اشتراک نامعتبر است.';
    }

    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'https' && !(allowInsecureHttp && scheme == 'http')) {
      return 'فقط پروتکل امن HTTPS برای دریافت لینک اشتراک مجاز است.';
    }

    if (uri.userInfo.isNotEmpty) {
      return 'وجود اطلاعات کاربری در آدرس اشتراک مجاز نیست.';
    }

    final host = uri.host.toLowerCase().trim();
    if (host == 'localhost' ||
        host.endsWith('.localhost') ||
        host.endsWith('.local') ||
        host.endsWith('.internal') ||
        host.endsWith('.lan') ||
        host == 'metadata.google.internal') {
      return 'دسترسی به میزبان‌های محلی یا داخلی (SSRF) مسدود است.';
    }

    // Strip IPv6 brackets if present
    final cleanHost = host.startsWith('[') && host.endsWith(']')
        ? host.substring(1, host.length - 1)
        : host;

    final ip = InternetAddress.tryParse(cleanHost);
    if (ip != null) {
      if (_isPrivateOrReservedIp(ip)) {
        return 'آدرس IP خصوصی یا رزروشده در لینک اشتراک مجاز نیست (محافظت SSRF).';
      }
    }

    return null;
  }

  bool _isPrivateOrReservedIp(InternetAddress ip) {
    if (ip.isLoopback || ip.isLinkLocal || ip.isMulticast) {
      return true;
    }

    final raw = ip.rawAddress;
    if (ip.type == InternetAddressType.IPv4 && raw.length == 4) {
      final b0 = raw[0];
      final b1 = raw[1];
      // 0.0.0.0/8, 10.0.0.0/8, 127.0.0.0/8
      if (b0 == 0 || b0 == 10 || b0 == 127) return true;
      // 100.64.0.0/10 (CGNAT)
      if (b0 == 100 && (b1 >= 64 && b1 <= 127)) return true;
      // 169.254.0.0/16 (Link-local / Cloud metadata 169.254.169.254)
      if (b0 == 169 && b1 == 254) return true;
      // 172.16.0.0/12
      if (b0 == 172 && (b1 >= 16 && b1 <= 31)) return true;
      // 192.168.0.0/16
      if (b0 == 192 && b1 == 168) return true;
      // 224.0.0.0/4+
      if (b0 >= 224) return true;
    } else if (ip.type == InternetAddressType.IPv6 && raw.length == 16) {
      // Unspecified ::
      final allZero = raw.every((b) => b == 0);
      if (allZero) return true;
      // Unique local fc00::/7 (0xfc or 0xfd)
      if ((raw[0] & 0xfe) == 0xfc) return true;
      // IPv4-mapped IPv6 ::ffff:x.x.x.x
      final isV4Mapped = raw.sublist(0, 10).every((b) => b == 0) &&
          raw[10] == 0xff &&
          raw[11] == 0xff;
      if (isV4Mapped) {
        final v4 = InternetAddress.fromRawAddress(raw.sublist(12, 16));
        return _isPrivateOrReservedIp(v4);
      }
    }

    return false;
  }

  /// Fetches and validates a subscription URL with redirect protection, offline handling, and response sanitization.
  Future<SubscriptionUpdateResult> fetchAndValidate(String rawUrl) async {
    var currentUri = Uri.tryParse(rawUrl.trim());
    final initialValidationError = validateSubscriptionUrl(currentUri);
    if (initialValidationError != null) {
      return SubscriptionUpdateResult(
        isSuccess: false,
        errorMessage: initialValidationError,
      );
    }

    try {
      var redirectCount = 0;
      SubscriptionHttpResponse? response;

      while (true) {
        response = await _httpClient.get(
          currentUri!,
          timeout: timeout,
          maxBytes: maxPayloadSizeBytes,
        );

        if (response.statusCode >= 300 && response.statusCode < 400) {
          redirectCount++;
          if (redirectCount > maxRedirects) {
            return const SubscriptionUpdateResult(
              isSuccess: false,
              errorMessage:
                  'تعداد تغییر مسیرهای (Redirect) لینک اشتراک بیش از حد مجاز است.',
            );
          }

          final location = response.redirectLocation;
          if (location == null || location.trim().isEmpty) {
            return const SubscriptionUpdateResult(
              isSuccess: false,
              errorMessage: 'پاسخ تغییر مسیر سرور فاقد آدرس مقصد معتبر است.',
            );
          }

          final nextUri = currentUri.resolve(location.trim());
          final redirectValidationError = validateSubscriptionUrl(nextUri);
          if (redirectValidationError != null) {
            return SubscriptionUpdateResult(
              isSuccess: false,
              errorMessage:
                  'تغییر مسیر ناامن مسدود شد: $redirectValidationError',
            );
          }

          currentUri = nextUri;
          continue;
        }
        break;
      }

      if (response.statusCode != 200) {
        return SubscriptionUpdateResult(
          isSuccess: false,
          errorMessage:
              'سرور اشتراک(${redactUrl(rawUrl)}) کد وضعیت نامعتبر ${response.statusCode} برگرداند.',
        );
      }

      final trimmedBody = response.body.trim();
      if (trimmedBody.isEmpty) {
        return const SubscriptionUpdateResult(
          isSuccess: false,
          errorMessage: 'پاسخ دریافت‌شده از سرور اشتراک خالی است.',
        );
      }

      // Reject HTML pages (e.g., captive portals, ISP block pages, or error pages)
      final lowerPrefix = trimmedBody
          .substring(0, trimmedBody.length > 200 ? 200 : trimmedBody.length)
          .toLowerCase();
      if (lowerPrefix.startsWith('<!doctype html') ||
          lowerPrefix.startsWith('<html') ||
          lowerPrefix.contains('<head>') ||
          lowerPrefix.contains('<body>')) {
        return const SubscriptionUpdateResult(
          isSuccess: false,
          errorMessage:
              'پاسخ سرور اشتراک یک صفحه وب (HTML) است و حاوی کانفیگ معتبر نیست.',
        );
      }

      final parseResult = await _detector.detectAndParse(trimmedBody);
      if (!parseResult.isSuccess || parseResult.profiles.isEmpty) {
        return SubscriptionUpdateResult(
          isSuccess: false,
          errorMessage: parseResult.errorMessage ??
              'هیچ کانفیگ معتبری در پاسخ سرور اشتراک یافت نشد.',
          warnings: parseResult.warnings,
        );
      }

      final infoNodes = parseResult.profiles.where(_isInfoNode).toList();
      SubscriptionUserInfo? infoFromName;
      for (final node in infoNodes) {
        final parsedInfo = SubscriptionUserInfo.parseInfoText(node.displayName);
        if (parsedInfo != null) {
          infoFromName = infoFromName == null
              ? parsedInfo
              : SubscriptionUserInfo.merge(infoFromName, parsedInfo);
        }
      }
      final subscriptionUserInfo = SubscriptionUserInfo.merge(
        SubscriptionUserInfo.merge(
          SubscriptionUserInfo.parseHeader(response.headers),
          SubscriptionUserInfo.parseBodyMetadata(response.body),
        ),
        infoFromName,
      );

      final connectableProfiles =
          parseResult.profiles.where((profile) => !_isInfoNode(profile));
      final validProfiles = <ServerProfile>[];
      final warnings = <String>[...parseResult.warnings];

      for (final profile in connectableProfiles) {
        final validation = _validator.validate(profile);
        if (validation.isValid) {
          validProfiles.add(profile);
        } else {
          warnings.add(
            'پروفایل "${profile.displayName}" به دلیل نامعتبر بودن نادیده گرفته شد: ${validation.errors.join(", ")}',
          );
        }
      }

      final subscriberName = SubscriptionSource.extractSubscriberName(
        url: rawUrl,
        profiles: parseResult.profiles,
        responseBody: response.body,
        responseHeaders: response.headers,
      );

      if (validProfiles.isEmpty) {
        return SubscriptionUpdateResult(
          isSuccess: false,
          errorMessage: infoNodes.isNotEmpty
              ? 'اشتراک فقط شامل ردیف اطلاعات وضعیت است و کانفیگ قابل اتصال ندارد.'
              : 'هیچ‌یک از کانفیگ‌های دریافتی اعتبارسنجی امنیتی را نگذراندند.',
          warnings: warnings,
          userInfo: subscriptionUserInfo,
          subscriberName: subscriberName,
        );
      }

      return SubscriptionUpdateResult(
        isSuccess: true,
        profiles: validProfiles,
        warnings: warnings,
        userInfo:
            subscriptionUserInfo.hasAnyValue ? subscriptionUserInfo : null,
        subscriberName: subscriberName,
      );
    } on SocketException {
      return const SubscriptionUpdateResult(
        isSuccess: false,
        isOfflineError: true,
        errorMessage:
            'عدم دسترسی به اینترنت یا سرور اشتراک. پروفایل‌های قبلی حفظ شدند.',
      );
    } on TimeoutException {
      return const SubscriptionUpdateResult(
        isSuccess: false,
        isOfflineError: true,
        errorMessage:
            'مهلت زمانی اتصال به سرور اشتراک به پایان رسید. پروفایل‌های قبلی حفظ شدند.',
      );
    } on HandshakeException {
      return const SubscriptionUpdateResult(
        isSuccess: false,
        isOfflineError: false,
        errorMessage:
            'خطای امنیتی گواهی TLS در ارتباط با سرور اشتراک. اتصال رد شد.',
      );
    } on FormatException catch (e) {
      return SubscriptionUpdateResult(
        isSuccess: false,
        errorMessage: e.message,
      );
    } catch (_) {
      return SubscriptionUpdateResult(
        isSuccess: false,
        errorMessage:
            'خطای غیرمنتظره هنگام به‌روزرسانی لینک اشتراک (${redactUrl(rawUrl)}).',
      );
    }
  }

  bool _isInfoNode(ServerProfile profile) {
    if (profile.extraParams['isInfoNode'] == true) return true;
    final host = profile.serverAddress?.trim() ?? '';
    if (host.isEmpty) return false;
    return SafeProxyUri.isInfoMetadataProfile(
      host: host,
      port: profile.serverPort ?? 443,
      displayName: profile.displayName,
      uuid: profile.extraParams['uuid']?.toString(),
    );
  }

  /// Starts periodic background updates for registered subscription URLs.
  void startPeriodicRefresh({
    required Duration interval,
    required FutureOr<List<String>> Function() getSubscriptionUrls,
    required void Function(String url, SubscriptionUpdateResult result)
        onUpdateResult,
  }) {
    stopPeriodicRefresh();
    _periodicTimer = Timer.periodic(interval, (_) async {
      await runRefreshCycle(
        getSubscriptionUrls: getSubscriptionUrls,
        onUpdateResult: onUpdateResult,
      );
    });
  }

  /// Executes a single background refresh cycle across all subscription URLs safely.
  Future<void> runRefreshCycle({
    required FutureOr<List<String>> Function() getSubscriptionUrls,
    required void Function(String url, SubscriptionUpdateResult result)
        onUpdateResult,
  }) async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    try {
      final urls = await getSubscriptionUrls();
      for (final url in urls) {
        final trimmed = url.trim();
        if (trimmed.isEmpty) continue;
        final result = await fetchAndValidate(trimmed);
        onUpdateResult(trimmed, result);
      }
    } finally {
      _isRefreshing = false;
    }
  }

  void stopPeriodicRefresh() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }
}
