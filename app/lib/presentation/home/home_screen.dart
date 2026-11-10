import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/connection/connection_controller.dart';
import '../../application/theme/theme_controller.dart';
import '../../domain/connection/connection_phase.dart';
import 'widgets/connection_button.dart';
import 'widgets/import_subscription_dialog.dart';
import 'widgets/select_server_dialog.dart';
import 'widgets/server_info_card.dart';
import 'widgets/usage_card.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  String _formatDuration(Duration d) {
    final hours = d.inHours.toString().padLeft(2, '0');
    final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  String _statusLabel(ConnectionPhase phase) {
    return switch (phase) {
      ConnectionPhase.connected => 'متصل شد',
      ConnectionPhase.connecting => 'در حال اتصال...',
      ConnectionPhase.preparing => 'در حال آماده‌سازی...',
      ConnectionPhase.reconnecting => 'تلاش مجدد اتصال...',
      ConnectionPhase.disconnecting => 'در حال قطع اتصال...',
      ConnectionPhase.failed => 'خطا در برقراری اتصال',
      ConnectionPhase.disconnected => 'قطع شده',
    };
  }

  String _themeLabel(ThemeMode mode) => switch (mode) {
        ThemeMode.system => 'خودکار',
        ThemeMode.light => 'روشن',
        ThemeMode.dark => 'تاریک',
      };

  IconData _themeIcon(ThemeMode mode) => switch (mode) {
        ThemeMode.system => Icons.brightness_auto_rounded,
        ThemeMode.light => Icons.light_mode_rounded,
        ThemeMode.dark => Icons.dark_mode_rounded,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final themeMode = ref.watch(themeModeProvider);
    final connectionState = ref.watch(connectionControllerProvider);

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
              tooltip: 'تغییر پوسته: ${_themeLabel(themeMode)}',
              onPressed: () => ref.read(themeModeProvider.notifier).cycleTheme(),
              icon: Icon(_themeIcon(themeMode)),
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
                          'وضعیت اتصال',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _statusLabel(connectionState.phase),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: connectionState.isConnected
                                ? Colors.green.shade600
                                : connectionState.phase == ConnectionPhase.failed
                                    ? Colors.red.shade600
                                    : null,
                          ),
                        ),
                        if (connectionState.isConnected) ...[
                          const SizedBox(height: 6),
                          Text(
                            _formatDuration(connectionState.connectedDuration),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: colorScheme.primary,
                            ),
                          ),
                        ],
                        if (connectionState.errorMessage != null) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: Text(
                              connectionState.errorMessage!,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.red.shade800,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 28),
                        ConnectionButton(
                          phase: connectionState.phase,
                          onPressed: () => ref
                              .read(connectionControllerProvider.notifier)
                              .toggleConnection(),
                        ),
                        const SizedBox(height: 32),
                        ServerInfoCard(
                          serverName: connectionState.activeProfile?.displayName ??
                              'انتخاب سرور',
                          subscriptionName:
                              connectionState.activeProfile != null
                                  ? connectionState.activeProfile!.protocol.toUpperCase()
                                  : 'هنوز اضافه نشده',
                          onTapServer: () {
                            showDialog(
                              context: context,
                              builder: (_) => const SelectServerDialog(),
                            );
                          },
                        ),
                        const SizedBox(height: 14),
                        const UsageCard(
                          dataUsage: '—',
                          subscriptionRemaining: '—',
                        ),
                        const SizedBox(height: 18),
                        OutlinedButton.icon(
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (_) => const ImportSubscriptionDialog(),
                            );
                          },
                          icon: const Icon(Icons.add_link_rounded),
                          label: const Text('افزودن اشتراک یا کانفیگ'),
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
                          'هسته متصل: sing-box · آماده اتصال واقعی',
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
