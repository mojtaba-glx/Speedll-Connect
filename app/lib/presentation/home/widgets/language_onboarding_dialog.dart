import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../application/localization/app_strings.dart';
import '../../../application/localization/locale_controller.dart';

/// First-launch language selection dialog that pre-selects the phone's detected
/// system language (Persian or English) and lets the user confirm or switch.
class LanguageOnboardingDialog extends ConsumerStatefulWidget {
  const LanguageOnboardingDialog({super.key});

  @override
  ConsumerState<LanguageOnboardingDialog> createState() =>
      _LanguageOnboardingDialogState();
}

class _LanguageOnboardingDialogState
    extends ConsumerState<LanguageOnboardingDialog> {
  late AppLanguage _selected;

  @override
  void initState() {
    super.initState();
    _selected = ref.read(localeControllerProvider).detectedDeviceLanguage;
  }

  @override
  Widget build(BuildContext context) {
    final localeState = ref.watch(localeControllerProvider);
    final strings = AppStrings(_selected);

    return Dialog(
      backgroundColor: const Color(0xFF281046),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(
              Icons.translate_rounded,
              color: Color(0xFF4ADE80),
              size: 40,
            ),
            const SizedBox(height: 12),
            Text(
              strings.onboardingTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              strings.onboardingSubtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.78),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 18),
            _LanguageCardOption(
              title: 'فارسی (Persian)',
              flag: '🇮🇷',
              isSelected: _selected == AppLanguage.fa,
              isDetectedDefault:
                  localeState.detectedDeviceLanguage == AppLanguage.fa,
              detectedLabel: 'پیش‌فرض گوشی شما',
              onTap: () => setState(() => _selected = AppLanguage.fa),
            ),
            const SizedBox(height: 10),
            _LanguageCardOption(
              title: 'English',
              flag: '🇬🇧',
              isSelected: _selected == AppLanguage.en,
              isDetectedDefault:
                  localeState.detectedDeviceLanguage == AppLanguage.en,
              detectedLabel: 'Device Default',
              onTap: () => setState(() => _selected = AppLanguage.en),
            ),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF9333EA),
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: () async {
                await ref
                    .read(localeControllerProvider.notifier)
                    .completeOnboarding(_selected);
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              },
              child: Text(
                strings.confirmAndContinue,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguageCardOption extends StatelessWidget {
  const _LanguageCardOption({
    required this.title,
    required this.flag,
    required this.isSelected,
    required this.isDetectedDefault,
    required this.detectedLabel,
    required this.onTap,
  });

  final String title;
  final String flag;
  final bool isSelected;
  final bool isDetectedDefault;
  final String detectedLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF6B21A8).withOpacity(0.85)
                : Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF4ADE80)
                  : Colors.white.withOpacity(0.18),
              width: isSelected ? 1.8 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Text(flag, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                      ),
                    ),
                    if (isDetectedDefault)
                      Text(
                        detectedLabel,
                        style: const TextStyle(
                          color: Color(0xFF4ADE80),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
              Icon(
                isSelected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: isSelected ? const Color(0xFF4ADE80) : Colors.white54,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
