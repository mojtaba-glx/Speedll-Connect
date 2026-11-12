import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'application/localization/locale_controller.dart';
import 'application/theme/theme_controller.dart';
import 'presentation/home/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const ProviderScope(
      child: SpeedllConnectApp(),
    ),
  );
}

class SpeedllConnectApp extends ConsumerWidget {
  const SpeedllConnectApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(themePaletteProvider);
    final localeState = ref.watch(localeControllerProvider);

    return MaterialApp(
      title: 'Speedll Connect',
      debugShowCheckedModeBanner: false,
      themeMode: palette.isLight ? ThemeMode.light : ThemeMode.dark,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: palette.primaryAccent,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: palette.backgroundGradient.last,
        cardTheme: CardTheme(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: palette.primaryAccent,
          brightness: Brightness.dark,
          surface: palette.cardSurface,
          primary: palette.primaryAccentLight,
          secondary: palette.secondaryAccent,
        ),
        scaffoldBackgroundColor: palette.backgroundGradient.last,
        cardTheme: CardTheme(
          elevation: 0,
          color: palette.cardSurface.withOpacity(0.80),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
      ),
      builder: (context, child) {
        return Directionality(
          textDirection: localeState.language.textDirection,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const HomeScreen(),
    );
  }
}
