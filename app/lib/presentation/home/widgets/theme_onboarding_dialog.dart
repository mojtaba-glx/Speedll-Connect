import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../application/localization/locale_controller.dart';
import '../../../application/theme/theme_controller.dart';

/// First-launch modal prompting the user to select their default app theme
/// right after language selection, with live palette preview.
class ThemeOnboardingDialog extends ConsumerWidget {
  const ThemeOnboardingDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activePreset = ref.watch(themePresetProvider);
    final palette = ref.watch(themePaletteProvider);
    final strings = ref.watch(appStringsProvider);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 580),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              palette.dialogBackground,
              palette.cardSurface,
            ],
          ),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
            color: palette.borderColor,
            width: 1.4,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.35),
              blurRadius: 28,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      palette.primaryAccent,
                      palette.secondaryAccent,
                    ],
                  ),
                ),
                child: const Icon(
                  Icons.palette_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              strings.themeOnboardingTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 16.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              strings.themeOnboardingSubtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 12,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 14),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final preset in SpeedllThemePreset.values) ...[
                      _ThemePresetOptionCard(
                        preset: preset,
                        isSelected: preset == activePreset,
                        palette: palette,
                        isFa: strings.isFa,
                        onTap: () => ref
                            .read(themePresetProvider.notifier)
                            .setPreset(preset),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: palette.primaryAccent,
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                strings.confirmAndContinue,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 14.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemePresetOptionCard extends StatelessWidget {
  const _ThemePresetOptionCard({
    required this.preset,
    required this.isSelected,
    required this.palette,
    required this.isFa,
    required this.onTap,
  });

  final SpeedllThemePreset preset;
  final bool isSelected;
  final SpeedllThemePalette palette;
  final bool isFa;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final baseTileColor = palette.isLight
        ? Colors.black.withOpacity(isSelected ? 0.08 : 0.03)
        : Colors.white.withOpacity(isSelected ? 0.14 : 0.06);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: baseTileColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? palette.secondaryAccent
                  : palette.borderColor.withOpacity(0.55),
              width: isSelected ? 1.8 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: preset.previewColor,
                  border: Border.all(
                    color: palette.isLight ? Colors.black26 : Colors.white,
                    width: 2,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  preset.label(isFa),
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 13.5,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
              Icon(
                isSelected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_off_rounded,
                color: isSelected
                    ? palette.secondaryAccent
                    : palette.textSecondary.withOpacity(0.6),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
