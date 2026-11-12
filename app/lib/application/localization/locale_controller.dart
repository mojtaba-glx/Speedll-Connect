import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/storage/secure_profile_storage.dart';
import '../connection/connection_controller.dart';
import 'app_strings.dart';

class LocaleState {
  const LocaleState({
    required this.language,
    required this.detectedDeviceLanguage,
    this.needsOnboarding = false,
    this.isLoaded = false,
  });

  final AppLanguage language;
  final AppLanguage detectedDeviceLanguage;
  final bool needsOnboarding;
  final bool isLoaded;

  LocaleState copyWith({
    AppLanguage? language,
    AppLanguage? detectedDeviceLanguage,
    bool? needsOnboarding,
    bool? isLoaded,
  }) {
    return LocaleState(
      language: language ?? this.language,
      detectedDeviceLanguage:
          detectedDeviceLanguage ?? this.detectedDeviceLanguage,
      needsOnboarding: needsOnboarding ?? this.needsOnboarding,
      isLoaded: isLoaded ?? this.isLoaded,
    );
  }
}

final localeControllerProvider =
    StateNotifierProvider<LocaleController, LocaleState>((ref) {
  final storage = ref.watch(secureProfileStorageProvider);
  return LocaleController(storage: storage);
});

final appStringsProvider = Provider<AppStrings>((ref) {
  final localeState = ref.watch(localeControllerProvider);
  return AppStrings(localeState.language);
});

class LocaleController extends StateNotifier<LocaleState> {
  LocaleController({
    required this.storage,
    bool? isTestOverride,
  })  : _isTest = isTestOverride ?? Platform.environment.containsKey('FLUTTER_TEST'),
        super(
          LocaleState(
            language: _detectDeviceLanguage(
              isTest: isTestOverride ?? Platform.environment.containsKey('FLUTTER_TEST'),
            ),
            detectedDeviceLanguage: _detectDeviceLanguage(
              isTest: isTestOverride ?? Platform.environment.containsKey('FLUTTER_TEST'),
            ),
          ),
        ) {
    _loadSavedLanguage();
  }

  final SecureProfileStorage storage;
  final bool _isTest;

  static AppLanguage _detectDeviceLanguage({required bool isTest}) {
    if (isTest) {
      return AppLanguage.fa;
    }
    try {
      final sysCode =
          ui.PlatformDispatcher.instance.locale.languageCode.toLowerCase();
      return sysCode.startsWith('fa') ? AppLanguage.fa : AppLanguage.en;
    } catch (_) {
      return AppLanguage.fa;
    }
  }

  Future<void> _loadSavedLanguage() async {
    final savedCode = await storage.loadAppLanguageCode();
    final onboarded = await storage.loadHasCompletedLanguageOnboarding();
    final detected = _detectDeviceLanguage(isTest: _isTest);

    if (!mounted) return;

    if (savedCode != null) {
      final resolved = AppLanguage.fromCode(savedCode, fallback: detected);
      state = state.copyWith(
        language: resolved,
        detectedDeviceLanguage: detected,
        needsOnboarding: !_isTest && !onboarded,
        isLoaded: true,
      );
    } else {
      state = state.copyWith(
        language: detected,
        detectedDeviceLanguage: detected,
        needsOnboarding: !_isTest && !onboarded,
        isLoaded: true,
      );
    }
  }

  Future<void> setLanguage(AppLanguage language, {bool markOnboarded = true}) async {
    state = state.copyWith(
      language: language,
      needsOnboarding: markOnboarded ? false : state.needsOnboarding,
      isLoaded: true,
    );
    await storage.saveAppLanguageCode(language.code);
    if (markOnboarded) {
      await storage.saveHasCompletedLanguageOnboarding(true);
    }
  }

  Future<void> completeOnboarding(AppLanguage chosenLanguage) async {
    await setLanguage(chosenLanguage, markOnboarded: true);
  }
}
