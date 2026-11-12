import 'package:flutter/material.dart';
import 'server_profile.dart';

class CountryLocationInfo {
  const CountryLocationInfo({
    required this.countryCode,
    required this.flagEmoji,
    required this.nameFa,
    required this.nameEn,
    required this.primaryColor,
    required this.secondaryColor,
    this.tertiaryColor,
  });

  final String countryCode;
  final String flagEmoji;
  final String nameFa;
  final String nameEn;
  final Color primaryColor;
  final Color secondaryColor;
  final Color? tertiaryColor;

  String localizedName(bool isFa) => isFa ? nameFa : nameEn;
}

/// Detects the country/location flag and localized country name from a [ServerProfile]'s
/// displayName (emoji flags, Persian/English country names, or ISO codes) and serverAddress.
class CountryFlagResolver {
  const CountryFlagResolver._();

  static const List<_CountryPattern> _patterns = <_CountryPattern>[
    _CountryPattern(
      code: 'DE',
      emoji: '🇩🇪',
      nameFa: 'آلمان',
      nameEn: 'Germany',
      keywords: ['🇩🇪', 'آلمان', 'المان', 'germany', 'frankfurt', 'falkenstein', 'hetzner', 'de-', '-de', '.de'],
      c1: Color(0xFF1A1A1A),
      c2: Color(0xFFDD0000),
      c3: Color(0xFFFFCE00),
    ),
    _CountryPattern(
      code: 'TR',
      emoji: '🇹🇷',
      nameFa: 'ترکیه',
      nameEn: 'Turkey',
      keywords: ['🇹🇷', 'ترکیه', 'استانبول', 'turkey', 'istanbul', 'tr-', '-tr', '.tr'],
      c1: Color(0xFFE30A17),
      c2: Color(0xFFFFFFFF),
      c3: Color(0xFFE30A17),
    ),
    _CountryPattern(
      code: 'FR',
      emoji: '🇫🇷',
      nameFa: 'فرانسه',
      nameEn: 'France',
      keywords: ['🇫🇷', 'فرانسه', 'پاریس', 'france', 'paris', 'fr-', '-fr', '.fr'],
      c1: Color(0xFF0055A4),
      c2: Color(0xFFFFFFFF),
      c3: Color(0xFFEF4135),
    ),
    _CountryPattern(
      code: 'NL',
      emoji: '🇳🇱',
      nameFa: 'هلند',
      nameEn: 'Netherlands',
      keywords: ['🇳🇱', 'هلند', 'آمستردام', 'netherlands', 'holland', 'amsterdam', 'nl-', '-nl', '.nl'],
      c1: Color(0xFFAE1C28),
      c2: Color(0xFFFFFFFF),
      c3: Color(0xFF21468B),
    ),
    _CountryPattern(
      code: 'GB',
      emoji: '🇬🇧',
      nameFa: 'انگلیس',
      nameEn: 'England',
      keywords: ['🇬🇧', 'انگلیس', 'لندن', 'بریتانیا', 'england', 'uk', 'london', 'britain', 'gb-', '-gb', '-uk'],
      c1: Color(0xFF012169),
      c2: Color(0xFFC8102E),
      c3: Color(0xFFFFFFFF),
    ),
    _CountryPattern(
      code: 'US',
      emoji: '🇺🇸',
      nameFa: 'آمریکا',
      nameEn: 'United States',
      keywords: ['🇺🇸', 'آمریکا', 'امریکا', 'usa', 'united states', 'america', 'new york', 'dallas', 'us-', '-us'],
      c1: Color(0xFF3C3B6E),
      c2: Color(0xFFB22234),
      c3: Color(0xFFFFFFFF),
    ),
    _CountryPattern(
      code: 'CA',
      emoji: '🇨🇦',
      nameFa: 'کانادا',
      nameEn: 'Canada',
      keywords: ['🇨🇦', 'کانادا', 'تورنتو', 'canada', 'toronto', 'montreal', 'ca-', '-ca'],
      c1: Color(0xFFFF0000),
      c2: Color(0xFFFFFFFF),
      c3: Color(0xFFFF0000),
    ),
    _CountryPattern(
      code: 'AU',
      emoji: '🇦🇺',
      nameFa: 'استرالیا',
      nameEn: 'Australia',
      keywords: ['🇦🇺', 'استرالیا', 'سیدنی', 'australia', 'sydney', 'au-', '-au'],
      c1: Color(0xFF00008B),
      c2: Color(0xFFFF0000),
      c3: Color(0xFFFFFFFF),
    ),
    _CountryPattern(
      code: 'FI',
      emoji: '🇫🇮',
      nameFa: 'فنلاند',
      nameEn: 'Finland',
      keywords: ['🇫🇮', 'فنلاند', 'هلسینکی', 'finland', 'helsinki', 'fi-', '-fi'],
      c1: Color(0xFFFFFFFF),
      c2: Color(0xFF003580),
      c3: Color(0xFFFFFFFF),
    ),
    _CountryPattern(
      code: 'AE',
      emoji: '🇦🇪',
      nameFa: 'امارات',
      nameEn: 'UAE',
      keywords: ['🇦🇪', 'امارات', 'دبی', 'uae', 'dubai', 'ae-', '-ae'],
      c1: Color(0xFF00732F),
      c2: Color(0xFFFFFFFF),
      c3: Color(0xFFFF0000),
    ),
    _CountryPattern(
      code: 'HK',
      emoji: '🇭🇰',
      nameFa: 'هنگ‌کنگ',
      nameEn: 'Hongkong',
      keywords: ['🇭🇰', 'هنگ کنگ', 'هنگ‌کنگ', 'hongkong', 'hong kong', 'hk-', '-hk'],
      c1: Color(0xFFDE2910),
      c2: Color(0xFFFFFFFF),
      c3: Color(0xFFDE2910),
    ),
    _CountryPattern(
      code: 'KR',
      emoji: '🇰🇷',
      nameFa: 'کره جنوبی',
      nameEn: 'South Korea',
      keywords: ['🇰🇷', 'کره', 'سئول', 'korea', 'seoul', 'kr-', '-kr'],
      c1: Color(0xFFFFFFFF),
      c2: Color(0xFFCD2E3A),
      c3: Color(0xFF0047A0),
    ),
    _CountryPattern(
      code: 'SG',
      emoji: '🇸🇬',
      nameFa: 'سنگاپور',
      nameEn: 'Singapore',
      keywords: ['🇸🇬', 'سنگاپور', 'singapore', 'sg-', '-sg'],
      c1: Color(0xFFEF3340),
      c2: Color(0xFFFFFFFF),
      c3: Color(0xFFEF3340),
    ),
    _CountryPattern(
      code: 'JP',
      emoji: '🇯🇵',
      nameFa: 'ژاپن',
      nameEn: 'Japan',
      keywords: ['🇯🇵', 'ژاپن', 'توکیو', 'japan', 'tokyo', 'jp-', '-jp'],
      c1: Color(0xFFFFFFFF),
      c2: Color(0xFFBC002D),
      c3: Color(0xFFFFFFFF),
    ),
    _CountryPattern(
      code: 'SE',
      emoji: '🇸🇪',
      nameFa: 'سوئد',
      nameEn: 'Sweden',
      keywords: ['🇸🇪', 'سوئد', 'استکهلم', 'sweden', 'stockholm', 'se-', '-se'],
      c1: Color(0xFF006AA7),
      c2: Color(0xFFFECC02),
      c3: Color(0xFF006AA7),
    ),
    _CountryPattern(
      code: 'CH',
      emoji: '🇨🇭',
      nameFa: 'سوئیس',
      nameEn: 'Switzerland',
      keywords: ['🇨🇭', 'سوئیس', 'زوریخ', 'switzerland', 'zurich', 'ch-', '-ch'],
      c1: Color(0xFFFF0000),
      c2: Color(0xFFFFFFFF),
      c3: Color(0xFFFF0000),
    ),
  ];

  static CountryLocationInfo resolve(ServerProfile? profile) {
    if (profile == null) {
      return const CountryLocationInfo(
        countryCode: 'AUTO',
        flagEmoji: '🌐',
        nameFa: 'جهانی',
        nameEn: 'Global',
        primaryColor: Color(0xFF7C3AED),
        secondaryColor: Color(0xFFC084FC),
      );
    }

    final haystack =
        '${profile.displayName} ${profile.serverAddress ?? ''} ${profile.id}'
            .toLowerCase();

    for (final pattern in _patterns) {
      for (final kw in pattern.keywords) {
        if (haystack.contains(kw)) {
          return CountryLocationInfo(
            countryCode: pattern.code,
            flagEmoji: pattern.emoji,
            nameFa: pattern.nameFa,
            nameEn: pattern.nameEn,
            primaryColor: pattern.c1,
            secondaryColor: pattern.c2,
            tertiaryColor: pattern.c3,
          );
        }
      }
    }

    // Check if displayName contains any regional indicator flag emoji pair
    final flagMatch = RegExp(
      r'[\u{1F1E6}-\u{1F1FF}]{2}',
      unicode: true,
    ).firstMatch(profile.displayName);
    if (flagMatch != null) {
      final emoji = flagMatch.group(0)!;
      return CountryLocationInfo(
        countryCode: 'LOC',
        flagEmoji: emoji,
        nameFa: profile.displayName,
        nameEn: profile.displayName,
        primaryColor: const Color(0xFF6366F1),
        secondaryColor: const Color(0xFFA855F7),
      );
    }

    return const CountryLocationInfo(
      countryCode: 'GLB',
      flagEmoji: '🌍',
      nameFa: 'سرور بین‌الملل',
      nameEn: 'International',
      primaryColor: Color(0xFF7C3AED),
      secondaryColor: Color(0xFF38BDF8),
    );
  }
}

class _CountryPattern {
  const _CountryPattern({
    required this.code,
    required this.emoji,
    required this.nameFa,
    required this.nameEn,
    required this.keywords,
    required this.c1,
    required this.c2,
    this.c3,
  });

  final String code;
  final String emoji;
  final String nameFa;
  final String nameEn;
  final List<String> keywords;
  final Color c1;
  final Color c2;
  final Color? c3;
}
