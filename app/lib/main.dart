import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SpeedllConnectApp());
}

class SpeedllConnectApp extends StatefulWidget {
  const SpeedllConnectApp({super.key});

  @override
  State<SpeedllConnectApp> createState() => _SpeedllConnectAppState();
}

class _SpeedllConnectAppState extends State<SpeedllConnectApp> {
  ThemeMode _themeMode = ThemeMode.system;

  void _cycleTheme() {
    setState(() {
      _themeMode = switch (_themeMode) {
        ThemeMode.system => ThemeMode.light,
        ThemeMode.light => ThemeMode.dark,
        ThemeMode.dark => ThemeMode.system,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    const seedColor = Color(0xFF1769E0);

    return MaterialApp(
      title: 'Speedll Connect',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F7FB),
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.dark,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
      ),
      home: HomeScreen(
        themeMode: _themeMode,
        onThemePressed: _cycleTheme,
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    required this.themeMode,
    required this.onThemePressed,
    super.key,
  });

  final ThemeMode themeMode;
  final VoidCallback onThemePressed;

  String get _themeLabel => switch (themeMode) {
        ThemeMode.system => 'خودکار',
        ThemeMode.light => 'روشن',
        ThemeMode.dark => 'تاریک',
      };

  IconData get _themeIcon => switch (themeMode) {
        ThemeMode.system => Icons.brightness_auto_rounded,
        ThemeMode.light => Icons.light_mode_rounded,
        ThemeMode.dark => Icons.dark_mode_rounded,
      };

  void _showNotReadyMessage(BuildContext context) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'این نسخه فقط پیش‌نمایش رابط کاربری است؛ موتور اتصال هنوز پیاده‌سازی نشده است.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 20,
          title: const Text(
            'Speedll Connect',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          actions: [
            IconButton(
              tooltip: 'تغییر پوسته: $_themeLabel',
              onPressed: onThemePressed,
              icon: Icon(_themeIcon),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 12),
                        Text(
                          'اتصال شما',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'قطع شده',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 28),
                        Center(
                          child: Material(
                            color: colorScheme.primaryContainer,
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () => _showNotReadyMessage(context),
                              child: SizedBox(
                                width: 176,
                                height: 176,
                                child: Icon(
                                  Icons.power_settings_new_rounded,
                                  size: 76,
                                  color: colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'برای اتصال لمس کنید',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 28),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              children: [
                                _InfoRow(
                                  icon: Icons.public_rounded,
                                  label: 'سرور انتخابی',
                                  value: 'انتخاب خودکار',
                                ),
                                Divider(
                                  height: 28,
                                  color: colorScheme.outlineVariant,
                                ),
                                _InfoRow(
                                  icon: Icons.account_circle_outlined,
                                  label: 'اشتراک',
                                  value: 'هنوز اضافه نشده',
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Row(
                              children: [
                                Expanded(
                                  child: _UsageItem(
                                    label: 'مصرف داده',
                                    value: '—',
                                    icon: Icons.data_usage_rounded,
                                  ),
                                ),
                                Container(
                                  width: 1,
                                  height: 42,
                                  color: colorScheme.outlineVariant,
                                ),
                                Expanded(
                                  child: _UsageItem(
                                    label: 'اعتبار اشتراک',
                                    value: '—',
                                    icon: Icons.event_available_rounded,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        OutlinedButton.icon(
                          onPressed: () => _showNotReadyMessage(context),
                          icon: const Icon(Icons.add_link_rounded),
                          label: const Text('افزودن اشتراک'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(56),
                            textStyle: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'نسخه زیرساختی · اتصال واقعی هنوز فعال نیست',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: isDark
                                ? colorScheme.onSurfaceVariant
                                : Colors.blueGrey.shade500,
                          ),
                        ),
                        if (constraints.maxHeight < 620)
                          const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Icon(icon, color: colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(child: Text(label)),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _UsageItem extends StatelessWidget {
  const _UsageItem({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Icon(icon, color: colorScheme.primary),
        const SizedBox(height: 8),
        Text(label, textAlign: TextAlign.center),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
      ],
    );
  }
}
