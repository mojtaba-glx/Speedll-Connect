import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/storage/secure_profile_storage.dart';
import '../connection/connection_controller.dart';

enum SpeedllThemePreset {
  royalPurple,
  midnightDark,
  cyberCyan,
  emeraldGreen,
  oceanBlue,
  cleanLight;

  static SpeedllThemePreset fromName(String? raw) {
    if (raw == null || raw.isEmpty) return SpeedllThemePreset.royalPurple;
    for (final preset in SpeedllThemePreset.values) {
      if (preset.name.toLowerCase() == raw.trim().toLowerCase()) {
        return preset;
      }
    }
    return SpeedllThemePreset.royalPurple;
  }

  String label(bool isFa) {
    return switch (this) {
      SpeedllThemePreset.royalPurple =>
        isFa ? 'بنفش نئونی (پیش‌فرض)' : 'Royal Purple',
      SpeedllThemePreset.midnightDark =>
        isFa ? 'دارک کلاسیک' : 'Midnight Dark',
      SpeedllThemePreset.cyberCyan =>
        isFa ? 'فیروزه‌ای نئونی' : 'Turquoise Cyan',
      SpeedllThemePreset.emeraldGreen =>
        isFa ? 'سبز زمردی' : 'Emerald Green',
      SpeedllThemePreset.oceanBlue =>
        isFa ? 'آبی اقیانوسی' : 'Ocean Blue',
      SpeedllThemePreset.cleanLight =>
        isFa ? 'لایت / روشن' : 'Clean Light',
    };
  }
}

class SpeedllThemePalette {
  const SpeedllThemePalette({
    required this.preset,
    required this.isLight,
    required this.backgroundGradient,
    required this.cardSurface,
    required this.dialogBackground,
    required this.primaryAccent,
    required this.primaryAccentLight,
    required this.secondaryAccent,
    required this.buttonCoreGradient,
    required this.textPrimary,
    required this.textSecondary,
    required this.borderColor,
  });

  final SpeedllThemePreset preset;
  final bool isLight;
  final List<Color> backgroundGradient;
  final Color cardSurface;
  final Color dialogBackground;
  final Color primaryAccent;
  final Color primaryAccentLight;
  final Color secondaryAccent;
  final List<Color> buttonCoreGradient;
  final Color textPrimary;
  final Color textSecondary;
  final Color borderColor;

  static SpeedllThemePalette of(SpeedllThemePreset preset) {
    return switch (preset) {
      SpeedllThemePreset.royalPurple => const SpeedllThemePalette(
          preset: SpeedllThemePreset.royalPurple,
          isLight: false,
          backgroundGradient: [
            Color(0xFF3B1564),
            Color(0xFF280E47),
            Color(0xFF19072E),
          ],
          cardSurface: Color(0xFF341658),
          dialogBackground: Color(0xFF281046),
          primaryAccent: Color(0xFF9333EA),
          primaryAccentLight: Color(0xFFC084FC),
          secondaryAccent: Color(0xFF4ADE80),
          buttonCoreGradient: [
            Color(0xFFC084FC),
            Color(0xFF9333EA),
            Color(0xFF6B21A8),
          ],
          textPrimary: Colors.white,
          textSecondary: Color(0xFFD8B4FE),
          borderColor: Color(0x52C084FC),
        ),
      SpeedllThemePreset.midnightDark => const SpeedllThemePalette(
          preset: SpeedllThemePreset.midnightDark,
          isLight: false,
          backgroundGradient: [
            Color(0xFF1E293B),
            Color(0xFF0F172A),
            Color(0xFF020617),
          ],
          cardSurface: Color(0xFF1E293B),
          dialogBackground: Color(0xFF0F172A),
          primaryAccent: Color(0xFF0EA5E9),
          primaryAccentLight: Color(0xFF7DD3FC),
          secondaryAccent: Color(0xFF4ADE80),
          buttonCoreGradient: [
            Color(0xFF38BDF8),
            Color(0xFF0284C7),
            Color(0xFF0369A1),
          ],
          textPrimary: Colors.white,
          textSecondary: Color(0xFFBAE6FD),
          borderColor: Color(0x4D38BDF8),
        ),
      SpeedllThemePreset.cyberCyan => const SpeedllThemePalette(
          preset: SpeedllThemePreset.cyberCyan,
          isLight: false,
          backgroundGradient: [
            Color(0xFF155E75),
            Color(0xFF083344),
            Color(0xFF041C24),
          ],
          cardSurface: Color(0xFF0E4558),
          dialogBackground: Color(0xFF083344),
          primaryAccent: Color(0xFF06B6D4),
          primaryAccentLight: Color(0xFF67E8F9),
          secondaryAccent: Color(0xFF2DD4BF),
          buttonCoreGradient: [
            Color(0xFF22D3EE),
            Color(0xFF0891B2),
            Color(0xFF155E75),
          ],
          textPrimary: Colors.white,
          textSecondary: Color(0xFFA5F3FC),
          borderColor: Color(0x5222D3EE),
        ),
      SpeedllThemePreset.emeraldGreen => const SpeedllThemePalette(
          preset: SpeedllThemePreset.emeraldGreen,
          isLight: false,
          backgroundGradient: [
            Color(0xFF065F46),
            Color(0xFF064E3B),
            Color(0xFF022C22),
          ],
          cardSurface: Color(0xFF064E3B),
          dialogBackground: Color(0xFF043927),
          primaryAccent: Color(0xFF10B981),
          primaryAccentLight: Color(0xFF6EE7B7),
          secondaryAccent: Color(0xFF4ADE80),
          buttonCoreGradient: [
            Color(0xFF34D399),
            Color(0xFF059669),
            Color(0xFF065F46),
          ],
          textPrimary: Colors.white,
          textSecondary: Color(0xFFA7F3D0),
          borderColor: Color(0x5234D399),
        ),
      SpeedllThemePreset.oceanBlue => const SpeedllThemePalette(
          preset: SpeedllThemePreset.oceanBlue,
          isLight: false,
          backgroundGradient: [
            Color(0xFF1E3A8A),
            Color(0xFF172554),
            Color(0xFF090D16),
          ],
          cardSurface: Color(0xFF1E3A8A),
          dialogBackground: Color(0xFF172554),
          primaryAccent: Color(0xFF3B82F6),
          primaryAccentLight: Color(0xFF93C5FD),
          secondaryAccent: Color(0xFF38BDF8),
          buttonCoreGradient: [
            Color(0xFF60A5FA),
            Color(0xFF2563EB),
            Color(0xFF1D4ED8),
          ],
          textPrimary: Colors.white,
          textSecondary: Color(0xFFBFDBFE),
          borderColor: Color(0x5260A5FA),
        ),
      SpeedllThemePreset.cleanLight => const SpeedllThemePalette(
          preset: SpeedllThemePreset.cleanLight,
          isLight: true,
          backgroundGradient: [
            Color(0xFFDDD6FE),
            Color(0xFFEDE9FE),
            Color(0xFFF8FAFC),
          ],
          cardSurface: Color(0xFFFFFFFF),
          dialogBackground: Color(0xFFF5F3FF),
          primaryAccent: Color(0xFF7E22CE),
          primaryAccentLight: Color(0xFF6B21A8),
          secondaryAccent: Color(0xFF16A34A),
          buttonCoreGradient: [
            Color(0xFFA855F7),
            Color(0xFF7E22CE),
            Color(0xFF581C87),
          ],
          textPrimary: Color(0xFF1E1B4B),
          textSecondary: Color(0xFF581C87),
          borderColor: Color(0x66C084FC),
        ),
    };
  }
}

final themePresetProvider =
    StateNotifierProvider<ThemePresetController, SpeedllThemePreset>((ref) {
  final storage = ref.watch(secureProfileStorageProvider);
  return ThemePresetController(storage: storage);
});

final themePaletteProvider = Provider<SpeedllThemePalette>((ref) {
  final preset = ref.watch(themePresetProvider);
  return SpeedllThemePalette.of(preset);
});

class ThemePresetController extends StateNotifier<SpeedllThemePreset> {
  ThemePresetController({required this.storage})
      : super(SpeedllThemePreset.royalPurple) {
    _loadInitial();
  }

  final SecureProfileStorage storage;

  Future<void> _loadInitial() async {
    final saved = await storage.loadThemePresetName();
    if (mounted && saved != null) {
      state = SpeedllThemePreset.fromName(saved);
    }
  }

  Future<void> setPreset(SpeedllThemePreset preset) async {
    state = preset;
    await storage.saveThemePresetName(preset.name);
  }
}

final themeModeProvider =
    StateNotifierProvider<ThemeController, ThemeMode>((ref) {
  final preset = ref.watch(themePresetProvider);
  return ThemeController(
    preset == SpeedllThemePreset.cleanLight ? ThemeMode.light : ThemeMode.dark,
  );
});

class ThemeController extends StateNotifier<ThemeMode> {
  ThemeController([super.initialMode = ThemeMode.dark]);

  void cycleTheme() {
    state = switch (state) {
      ThemeMode.dark => ThemeMode.light,
      ThemeMode.light => ThemeMode.system,
      ThemeMode.system => ThemeMode.dark,
    };
  }

  void setTheme(ThemeMode mode) {
    state = mode;
  }
}
