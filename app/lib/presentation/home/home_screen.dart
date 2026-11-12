import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/connection/connection_controller.dart';
import '../../application/localization/app_strings.dart';
import '../../application/localization/locale_controller.dart';
import '../../application/theme/theme_controller.dart';
import '../../domain/connection/connection_phase.dart';
import '../../domain/ping/ping_service.dart';
import '../../domain/profiles/country_flag_resolver.dart';
import 'widgets/connection_button.dart';
import 'widgets/country_flag_avatar.dart';
import 'widgets/import_subscription_dialog.dart';
import 'widgets/language_onboarding_dialog.dart';
import 'widgets/select_server_dialog.dart';
import 'widgets/settings_panel.dart';
import 'widgets/statistics_panel.dart';
import 'widgets/subscription_usage_card.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _selectedTabIndex = 0;
  bool _onboardingDialogShown = false;

  String _formatDuration(Duration d) {
    final hours = d.inHours.toString().padLeft(2, '0');
    final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  void _maybeShowOnboarding(LocaleState localeState) {
    if (localeState.isLoaded &&
        localeState.needsOnboarding &&
        !_onboardingDialogShown) {
      _onboardingDialogShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const LanguageOnboardingDialog(),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final localeState = ref.watch(localeControllerProvider);
    final strings = ref.watch(appStringsProvider);
    final connectionState = ref.watch(connectionControllerProvider);
    final palette = ref.watch(themePaletteProvider);

    _maybeShowOnboarding(localeState);

    return Directionality(
      textDirection: localeState.language.textDirection,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: palette.backgroundGradient,
          ),
        ),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            titleSpacing: 20,
            title: Text(
              'Speedll Connect',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: palette.textPrimary,
                fontSize: 19,
              ),
            ),
            actions: [
              if (_selectedTabIndex == 0) ...[
                IconButton(
                  tooltip: strings.addSubscriptionOrConfig,
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => const ImportSubscriptionDialog(),
                    );
                  },
                  icon: Icon(
                    Icons.add_rounded,
                    color: palette.textPrimary,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
          body: SafeArea(
            child: Stack(
              children: [
                Positioned.fill(
                  child: IndexedStack(
                    index: _selectedTabIndex,
                    children: [
                      _buildMainConnectionTab(
                        context,
                        strings,
                        connectionState,
                        palette,
                      ),
                      const Padding(
                        padding: EdgeInsets.only(bottom: 84),
                        child: ProfilesBrowserPanel(isModal: false),
                      ),
                      const StatisticsPanel(),
                      const SettingsPanel(),
                    ],
                  ),
                ),
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 14,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: _FloatingBottomNavBar(
                        selectedIndex: _selectedTabIndex,
                        strings: strings,
                        palette: palette,
                        onSelect: (index) {
                          setState(() => _selectedTabIndex = index);
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMainConnectionTab(
    BuildContext context,
    AppStrings strings,
    dynamic connectionState,
    SpeedllThemePalette palette,
  ) {
    final activeProfile = connectionState.activeProfile;
    final location = CountryFlagResolver.resolve(activeProfile);
    final phase = connectionState.phase as ConnectionPhase;
    final isConnected = connectionState.isConnected as bool;
    final profiles = ref.watch(profilesListProvider);
    final subscriptions = ref.watch(subscriptionsListProvider);
    final activeSubscriptionId =
        activeProfile?.extraParams['subscriptionId']?.toString();
    final activeSubscription = subscriptions
            .where((subscription) => subscription.id == activeSubscriptionId)
            .firstOrNull ??
        (subscriptions.isNotEmpty ? subscriptions.first : null);

    final Color badgeBgColor = switch (phase) {
      ConnectionPhase.connected => const Color(0xFF22C55E),
      ConnectionPhase.connecting ||
      ConnectionPhase.preparing ||
      ConnectionPhase.reconnecting =>
        const Color(0xFFF59E0B),
      ConnectionPhase.failed => const Color(0xFFEF4444),
      ConnectionPhase.disconnecting ||
      ConnectionPhase.disconnected =>
        palette.primaryAccent.withOpacity(0.85),
    };

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 104),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Active Subscription Card at the TOP of the Home screen
              if (activeSubscription != null) ...[
                SubscriptionUsageCard(
                  source: activeSubscription,
                  strings: strings,
                  palette: palette,
                  compact: false,
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (_) => SelectServerDialog(
                        initialSubscriptionId: activeSubscription.id,
                      ),
                    );
                  },
                  onRefresh: () async {
                    final res = await ref
                        .read(connectionControllerProvider.notifier)
                        .refreshSubscriptionsNow();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            res.isSuccess
                                ? strings.subscriptionsUpdatedToast
                                : (res.errorMessage ??
                                    strings.subscriptionsUpdateFailedToast),
                          ),
                          backgroundColor: res.isSuccess
                              ? const Color(0xFF16A34A)
                              : const Color(0xFFEF4444),
                        ),
                      );
                    }
                  },
                  isRefreshing: connectionState.isRefreshingSubscriptions,
                ),
                const SizedBox(height: 16),
              ] else ...[
                const SizedBox(height: 8),
              ],

              // 2. Radiant Sun/Moon/Star Power Button
              // On first launch (when no profiles/subscriptions exist), tapping Connect
              // immediately opens the QR Code & Subscription Link import dialog.
              ConnectionButton(
                phase: phase,
                onPressed: () {
                  if (profiles.isEmpty && activeProfile == null) {
                    showDialog(
                      context: context,
                      builder: (_) => const ImportSubscriptionDialog(),
                    );
                    return;
                  }
                  ref
                      .read(connectionControllerProvider.notifier)
                      .toggleConnection();
                },
              ),

              const SizedBox(height: 14),

              // 3. Compact Status Badge + Secured Timer + Live Ping below the Connect Button
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: palette.isLight
                      ? Colors.white.withOpacity(0.90)
                      : palette.cardSurface.withOpacity(0.76),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isConnected
                        ? palette.secondaryAccent.withOpacity(0.55)
                        : palette.borderColor,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Status Pill Badge
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: badgeBgColor,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: badgeBgColor.withOpacity(0.42),
                                  blurRadius: 10,
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isConnected
                                      ? Icons.verified_user_rounded
                                      : Icons.shield_outlined,
                                  size: 13,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 5),
                                Flexible(
                                  child: Text(
                                    strings.statusLabel(phase),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Compact Connection Timer
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.timer_outlined,
                              size: 15,
                              color: isConnected
                                  ? palette.secondaryAccent
                                  : palette.textSecondary,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              _formatDuration(
                                  connectionState.connectedDuration),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: palette.textPrimary,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Divider(
                      height: 1,
                      color: palette.borderColor.withOpacity(0.5),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => ref
                          .read(connectionControllerProvider.notifier)
                          .pingActiveProfile(),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CountryFlagAvatar(
                                  location: location,
                                  size: 20,
                                  isSmartMode: connectionState.isSmartMode,
                                ),
                                const SizedBox(width: 7),
                                Flexible(
                                  child: Text(
                                    location.localizedName(strings.isFa),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: palette.textPrimary,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                if (PingService.resolveServerIpSync(activeProfile) != null) ...[
                                  const SizedBox(width: 5),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 1.5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: palette.secondaryAccent.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: palette.secondaryAccent.withOpacity(0.35),
                                        width: 0.8,
                                      ),
                                    ),
                                    child: Text(
                                      PingService.resolveServerIpSync(activeProfile)!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: palette.secondaryAccent,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 10.5,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SignalBarsIndicator(
                                pingMs: connectionState.livePingMs,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${strings.livePingLabel}: ${strings.pingMsValue(connectionState.livePingMs)}',
                                style: TextStyle(
                                  color: isConnected
                                      ? palette.secondaryAccent
                                      : palette.textPrimary.withOpacity(0.85),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              if (connectionState.errorMessage != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7F1D1D).withOpacity(0.88),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.redAccent.shade200),
                  ),
                  child: Text(
                    connectionState.errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Floating white/frosted pill bottom navigation bar with glowing active indicator,
/// matching the bottom navigation bar in the reference image.
class _FloatingBottomNavBar extends StatelessWidget {
  const _FloatingBottomNavBar({
    required this.selectedIndex,
    required this.strings,
    required this.palette,
    required this.onSelect,
  });

  final int selectedIndex;
  final AppStrings strings;
  final SpeedllThemePalette palette;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final items = <({IconData icon, String tooltip})>[
      (icon: Icons.home_rounded, tooltip: strings.navHome),
      (icon: Icons.rocket_launch_rounded, tooltip: strings.navProfiles),
      (icon: Icons.analytics_outlined, tooltip: strings.navStatistics),
      (icon: Icons.settings_rounded, tooltip: strings.navSettings),
    ];

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF5F3FF), Color(0xFFE2E8F0)],
        ),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.32),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(items.length, (index) {
          final isSelected = index == selectedIndex;
          final item = items[index];

          return GestureDetector(
            onTap: () => onSelect(index),
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: isSelected
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          palette.buttonCoreGradient.first,
                          palette.buttonCoreGradient.last,
                        ],
                      )
                    : null,
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: palette.primaryAccent.withOpacity(0.45),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                item.icon,
                size: 23,
                color: isSelected ? Colors.white : const Color(0xFF334155),
              ),
            ),
          );
        }),
      ),
    );
  }
}
