import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speedll_subscription/speedll_subscription.dart';

import '../../../application/connection/connection_controller.dart';
import '../../../application/connection/connection_state.dart';
import '../../../application/localization/app_strings.dart';
import '../../../application/localization/locale_controller.dart';
import '../../../application/theme/theme_controller.dart';
import '../../../domain/ping/ping_service.dart';
import '../../../domain/profiles/country_flag_resolver.dart';
import 'country_flag_avatar.dart';
import 'import_subscription_dialog.dart';

class SelectServerDialog extends ConsumerWidget {
  const SelectServerDialog({this.initialSubscriptionId, super.key});

  final String? initialSubscriptionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(themePaletteProvider);
    return Dialog(
      backgroundColor: palette.dialogBackground,
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 740),
        child: ProfilesBrowserPanel(
          isModal: true,
          initialSubscriptionId: initialSubscriptionId,
        ),
      ),
    );
  }
}

/// Modern Hiddify-style independent profile manager.
/// Each subscription is displayed as its own card with user name, status,
/// volume/expiry metrics, smart mode toggle, refresh, and delete actions.
/// Configs are grouped neatly by country in an expandable accordion.
class ProfilesBrowserPanel extends ConsumerStatefulWidget {
  const ProfilesBrowserPanel({
    this.isModal = false,
    this.initialSubscriptionId,
    super.key,
  });

  final bool isModal;
  final String? initialSubscriptionId;

  @override
  ConsumerState<ProfilesBrowserPanel> createState() =>
      _ProfilesBrowserPanelState();
}

class _ProfilesBrowserPanelState extends ConsumerState<ProfilesBrowserPanel> {
  final Set<String> _expandedSubscriptionIds = <String>{};
  bool _initialized = false;
  bool _manualExpanded = false;
  bool _sortByPing = false;

  void _ensureInitialized(
    List<SubscriptionSource> subscriptions,
    String? activeSubId,
    List<ServerProfile> manualProfiles,
  ) {
    if (_initialized) return;
    _initialized = true;

    final targetSubId = widget.initialSubscriptionId;
    if (targetSubId != null &&
        subscriptions.any((s) => s.id == targetSubId)) {
      _expandedSubscriptionIds.add(targetSubId);
    } else if (activeSubId != null &&
        subscriptions.any((s) => s.id == activeSubId)) {
      _expandedSubscriptionIds.add(activeSubId);
    } else if (subscriptions.isNotEmpty) {
      _expandedSubscriptionIds.add(subscriptions.first.id);
    } else if (manualProfiles.isNotEmpty) {
      _manualExpanded = true;
    }
  }

  String _resolveSubName(
    SubscriptionSource sub,
    List<ServerProfile> subProfiles,
  ) {
    final cleanSub = SubscriptionSource.sanitizeSubscriberName(
      sub.subscriberName,
    );
    if (cleanSub != null) {
      return SubscriptionSource.formatSubscriptionTitle(cleanSub);
    }

    final d = sub.displayUserName;
    if (!d.contains('.') &&
        !d.contains('(') &&
        d != 'اشتراک کاربر' &&
        !d.toLowerCase().contains('base64:')) {
      return d;
    }

    final extracted = SubscriptionSource.extractSubscriberName(
      url: sub.url,
      profiles: subProfiles,
    );
    if (extracted != null && extracted.isNotEmpty) {
      return SubscriptionSource.formatSubscriptionTitle(extracted);
    }

    final clean = SubscriptionSource.sanitizeSubscriberName(
      sub.name.replaceAll(RegExp(r'\s*\([^\)]+\)'), ''),
      allowDots: false,
    );
    if (clean != null) {
      return SubscriptionSource.formatSubscriptionTitle(clean);
    }

    return d;
  }

  String _transportSummary(ServerProfile profile) {
    final extra = profile.extraParams;
    final parts = <String>[profile.protocol.toUpperCase()];
    final net =
        (extra['transportType'] ?? extra['type'] ?? extra['network'] ?? '')
            .toString()
            .trim();
    if (net.isNotEmpty && net.toLowerCase() != 'tcp') {
      parts.add(net.toUpperCase());
    }
    final sec = (extra['security'] ?? '').toString().trim();
    if (sec.isNotEmpty && sec.toLowerCase() != 'none') {
      parts.add(sec.toUpperCase());
    } else if (extra['tls'] == true || extra['tls'] == 'tls') {
      parts.add('TLS');
    }
    return parts.join(' · ');
  }

  Color _pingBadgeColor(int? pingMs) {
    if (pingMs == null) return const Color(0xFF64748B);
    if (pingMs < 0) return const Color(0xFFEF4444);
    if (pingMs < 180) return const Color(0xFF16A34A);
    if (pingMs < 380) return const Color(0xFFD97706);
    return const Color(0xFFEA580C);
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final palette = ref.watch(themePaletteProvider);
    final profiles = ref.watch(profilesListProvider);
    final subscriptions = ref.watch(subscriptionsListProvider);
    final connState = ref.watch(connectionControllerProvider);
    final activeProfile = connState.activeProfile;
    final activeSubId =
        activeProfile?.extraParams['subscriptionId']?.toString();

    final subById = <String, SubscriptionSource>{
      for (final s in subscriptions) s.id: s,
    };

    final connectableProfiles =
        profiles.where(PingService.isConnectableServer).toList();
    final manualProfiles = connectableProfiles
        .where(
          (p) =>
              p.extraParams['subscriptionId'] == null ||
              !subById.containsKey(p.extraParams['subscriptionId'].toString()),
        )
        .toList();

    _ensureInitialized(subscriptions, activeSubId, manualProfiles);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Row: Close (if modal) + Title + Ping All + Add Subscription
          Row(
            children: [
              if (widget.isModal)
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: IconButton.styleFrom(
                    backgroundColor: palette.textPrimary.withOpacity(0.10),
                  ),
                  icon: Icon(Icons.close_rounded, color: palette.textPrimary),
                ),
              if (widget.isModal) const SizedBox(width: 8),
              Expanded(
                child: Text(
                  strings.myProfilesTitle,
                  textAlign:
                      widget.isModal ? TextAlign.center : TextAlign.start,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: palette.textPrimary,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              IconButton(
                tooltip: strings.sortByPing,
                onPressed: () => setState(() => _sortByPing = !_sortByPing),
                style: IconButton.styleFrom(
                  backgroundColor: _sortByPing
                      ? palette.secondaryAccent.withOpacity(0.24)
                      : palette.primaryAccent.withOpacity(0.14),
                ),
                icon: Icon(
                  Icons.sort_rounded,
                  size: 20,
                  color: _sortByPing
                      ? palette.secondaryAccent
                      : palette.textPrimary.withOpacity(0.85),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: strings.testAllPings,
                onPressed: connState.isPingingAll
                    ? null
                    : () async {
                        await ref
                            .read(connectionControllerProvider.notifier)
                            .pingAllProfiles();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(strings.pingingAllCompletedToast),
                              duration: const Duration(seconds: 2),
                              backgroundColor: const Color(0xFF16A34A),
                            ),
                          );
                        }
                      },
                style: IconButton.styleFrom(
                  backgroundColor: palette.primaryAccent.withOpacity(0.20),
                ),
                icon: connState.isPingingAll
                    ? SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: palette.textPrimary,
                        ),
                      )
                    : Icon(
                        Icons.speed_rounded,
                        color: palette.secondaryAccent,
                        size: 21,
                      ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: strings.addSubscriptionOrConfig,
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => const ImportSubscriptionDialog(),
                  );
                },
                style: IconButton.styleFrom(
                  backgroundColor: palette.primaryAccent.withOpacity(0.24),
                ),
                icon: Icon(
                  Icons.add_rounded,
                  color: palette.textPrimary,
                  size: 24,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Main Content: Independent Subscription Cards
          Expanded(
            child: subscriptions.isEmpty && manualProfiles.isEmpty
                ? _buildEmptyState(palette, strings)
                : ListView(
                    padding: const EdgeInsets.only(bottom: 12),
                    children: [
                      // Subscriptions list
                      for (final sub in subscriptions) ...[
                        _buildSubscriptionCard(
                          context: context,
                          sub: sub,
                          subProfiles: connectableProfiles
                              .where(
                                (p) =>
                                    p.extraParams['subscriptionId']
                                        ?.toString() ==
                                    sub.id,
                              )
                              .toList(),
                          isActive: activeSubId == sub.id,
                          isExpanded:
                              _expandedSubscriptionIds.contains(sub.id),
                          palette: palette,
                          strings: strings,
                          connState: connState,
                        ),
                        const SizedBox(height: 14),
                      ],

                      // Manual profiles card (if any exist)
                      if (manualProfiles.isNotEmpty) ...[
                        _buildManualCard(
                          context: context,
                          manualProfiles: manualProfiles,
                          isActive: activeProfile != null &&
                              (activeSubId == null ||
                                  !subById.containsKey(activeSubId)),
                          isExpanded: _manualExpanded,
                          palette: palette,
                          strings: strings,
                          connState: connState,
                        ),
                        const SizedBox(height: 14),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(SpeedllThemePalette palette, AppStrings strings) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: palette.primaryAccent.withOpacity(0.12),
              ),
              child: Icon(
                Icons.dns_outlined,
                size: 48,
                color: palette.primaryAccent,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              strings.noProfilesYet,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textPrimary.withOpacity(0.85),
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => const ImportSubscriptionDialog(),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: palette.primaryAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 11,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.add_rounded, size: 20),
              label: Text(
                strings.addSubscriptionOrConfig,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubscriptionCard({
    required BuildContext context,
    required SubscriptionSource sub,
    required List<ServerProfile> subProfiles,
    required bool isActive,
    required bool isExpanded,
    required SpeedllThemePalette palette,
    required AppStrings strings,
    required ConnectionUiState connState,
  }) {
    final displayName = _resolveSubName(sub, subProfiles);
    final info = sub.userInfo;
    final used = info?.usedBytes;
    final total = info?.totalBytes;
    final fraction = info?.usedFraction;
    final days = info?.remainingDays();
    final hasVolume = total != null && total > 0;

    return Container(
      decoration: BoxDecoration(
        color: palette.isLight
            ? Colors.white.withOpacity(0.96)
            : palette.cardSurface.withOpacity(0.92),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isActive
              ? palette.secondaryAccent.withOpacity(0.85)
              : palette.borderColor,
          width: isActive ? 2.0 : 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: isActive
                ? palette.secondaryAccent.withOpacity(0.18)
                : Colors.black.withOpacity(0.12),
            blurRadius: isActive ? 16 : 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Top Card Header: Avatar + User/Profile Name + Active Badge / Select Button
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        palette.primaryAccent.withOpacity(0.35),
                        palette.secondaryAccent.withOpacity(0.25),
                      ],
                    ),
                  ),
                  child: Icon(
                    Icons.person_rounded,
                    size: 21,
                    color: palette.secondaryAccent,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: palette.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${subProfiles.length} ${strings.isFa ? "کانفیگ / سرور" : "servers"}',
                        style: TextStyle(
                          fontSize: 11,
                          color: palette.textPrimary.withOpacity(0.60),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (isActive)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16A34A).withOpacity(0.20),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF4ADE80).withOpacity(0.85),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.check_circle_rounded,
                          size: 13,
                          color: Color(0xFF4ADE80),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          strings.activeStatus,
                          style: const TextStyle(
                            color: Color(0xFF4ADE80),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  OutlinedButton(
                    onPressed: () => _activateSubscription(sub, subProfiles),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      minimumSize: const Size(0, 32),
                      side: BorderSide(
                        color: palette.primaryAccent.withOpacity(0.65),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      strings.selectAction,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: palette.primaryAccent,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // 2. Volume & Days Remaining Row with slim progress bar
          if (info != null && (hasVolume || days != null)) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      if (hasVolume && used != null) ...[
                        Text(
                          '📊 ${SubscriptionUserInfo.formatBytes(used)} / ${SubscriptionUserInfo.formatBytes(total)}',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: palette.textPrimary.withOpacity(0.85),
                          ),
                        ),
                      ],
                      if (hasVolume && days != null)
                        Text(
                          '  |  ',
                          style: TextStyle(
                            color: palette.textPrimary.withOpacity(0.40),
                          ),
                        ),
                      if (days != null) ...[
                        Text(
                          '⏳ $days ${strings.subscriptionUsageDaysLeft}',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: days <= 3
                                ? const Color(0xFFEF4444)
                                : palette.secondaryAccent,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (fraction != null) ...[
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: fraction,
                        minHeight: 4,
                        backgroundColor: palette.isLight
                            ? Colors.black.withOpacity(0.08)
                            : Colors.white.withOpacity(0.12),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          fraction >= 0.85
                              ? const Color(0xFFEF4444)
                              : fraction >= 0.65
                                  ? const Color(0xFFF59E0B)
                                  : palette.secondaryAccent,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],

          const SizedBox(height: 6),

          // 3. Actions Row: [⚡ هوشمند]  [👁️ مشاهده کانفیگ‌ها]  [🔄 بروزرسانی]  [🗑️]
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: palette.isLight
                  ? Colors.black.withOpacity(0.03)
                  : Colors.white.withOpacity(0.03),
              borderRadius: BorderRadius.circular(16),
            ),
            margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: Row(
              children: [
                // Smart Mode action
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () async {
                    if (!isActive && subProfiles.isNotEmpty) {
                      await _activateSubscription(sub, subProfiles);
                    }
                    await ref
                        .read(connectionControllerProvider.notifier)
                        .setSmartMode(true);
                    if (context.mounted && connState.isConnected) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(strings.switchedWhileConnectedToast),
                          backgroundColor: const Color(0xFF16A34A),
                        ),
                      );
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: isActive && connState.isSmartMode
                          ? palette.secondaryAccent.withOpacity(0.24)
                          : palette.primaryAccent.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isActive && connState.isSmartMode
                            ? palette.secondaryAccent
                            : Colors.transparent,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.bolt_rounded,
                          size: 15,
                          color: isActive && connState.isSmartMode
                              ? palette.secondaryAccent
                              : palette.textPrimary.withOpacity(0.85),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          strings.smartBadge,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: isActive && connState.isSmartMode
                                ? palette.secondaryAccent
                                : palette.textPrimary.withOpacity(0.85),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(width: 6),

                // View Configs action
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      setState(() {
                        if (isExpanded) {
                          _expandedSubscriptionIds.remove(sub.id);
                        } else {
                          _expandedSubscriptionIds.add(sub.id);
                        }
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: isExpanded
                            ? palette.primaryAccent.withOpacity(0.20)
                            : palette.primaryAccent.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            isExpanded
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.visibility_outlined,
                            size: 15,
                            color: palette.textPrimary,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              isExpanded
                                  ? strings.hideConfigsLabel
                                  : '${strings.viewConfigsLabel} (${subProfiles.length})',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: palette.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 6),

                // Refresh action
                IconButton(
                  tooltip: strings.refreshSubscriptionsTooltip,
                  visualDensity: VisualDensity.compact,
                  onPressed: connState.isRefreshingSubscriptions
                      ? null
                      : () async {
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
                                          strings
                                              .subscriptionsUpdateFailedToast),
                                ),
                                backgroundColor: res.isSuccess
                                    ? const Color(0xFF16A34A)
                                    : const Color(0xFFEF4444),
                              ),
                            );
                          }
                        },
                  icon: connState.isRefreshingSubscriptions
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 1.8),
                        )
                      : Icon(
                          Icons.refresh_rounded,
                          size: 18,
                          color: palette.textPrimary.withOpacity(0.85),
                        ),
                ),

                // Delete subscription action
                IconButton(
                  tooltip: strings.deleteSubscriptionTitle,
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _confirmDeleteSubscription(
                    context: context,
                    sub: sub,
                    displayName: displayName,
                    palette: palette,
                    strings: strings,
                  ),
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    size: 19,
                    color: Color(0xFFEF4444),
                  ),
                ),
              ],
            ),
          ),

          // 4. Expanded Server List (grouped by country)
          if (isExpanded) ...[
            Container(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
              decoration: BoxDecoration(
                color: palette.isLight
                    ? Colors.grey.shade50.withOpacity(0.85)
                    : Colors.black.withOpacity(0.18),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(22),
                  bottomRight: Radius.circular(22),
                ),
              ),
              child: subProfiles.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        strings.isFa
                            ? 'هیچ کانفیگ فعالی در این اشتراک وجود ندارد.'
                            : 'No connectable servers found.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: palette.textPrimary.withOpacity(0.65),
                          fontSize: 12,
                        ),
                      ),
                    )
                  : _buildGroupedConfigsList(
                      profiles: subProfiles,
                      connState: connState,
                      palette: palette,
                      strings: strings,
                      activeSubId: sub.id,
                    ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildManualCard({
    required BuildContext context,
    required List<ServerProfile> manualProfiles,
    required bool isActive,
    required bool isExpanded,
    required SpeedllThemePalette palette,
    required AppStrings strings,
    required ConnectionUiState connState,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: palette.isLight
            ? Colors.white.withOpacity(0.96)
            : palette.cardSurface.withOpacity(0.92),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isActive
              ? palette.secondaryAccent.withOpacity(0.85)
              : palette.borderColor,
          width: isActive ? 2.0 : 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: palette.primaryAccent.withOpacity(0.18),
                  ),
                  child: Icon(
                    Icons.vpn_key_rounded,
                    size: 19,
                    color: palette.primaryAccent,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        strings.manualConfigsSectionTitle,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: palette.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${manualProfiles.length} ${strings.isFa ? "کانفیگ / سرور" : "servers"}',
                        style: TextStyle(
                          fontSize: 11,
                          color: palette.textPrimary.withOpacity(0.60),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isActive)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16A34A).withOpacity(0.20),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF4ADE80).withOpacity(0.85),
                      ),
                    ),
                    child: Text(
                      strings.activeStatus,
                      style: const TextStyle(
                        color: Color(0xFF4ADE80),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: palette.isLight
                  ? Colors.black.withOpacity(0.03)
                  : Colors.white.withOpacity(0.03),
              borderRadius: BorderRadius.circular(16),
            ),
            margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () =>
                        setState(() => _manualExpanded = !_manualExpanded),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: _manualExpanded
                            ? palette.primaryAccent.withOpacity(0.20)
                            : palette.primaryAccent.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _manualExpanded
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.visibility_outlined,
                            size: 15,
                            color: palette.textPrimary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _manualExpanded
                                ? strings.hideConfigsLabel
                                : '${strings.viewConfigsLabel} (${manualProfiles.length})',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: palette.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: strings.clearManualConfigsPrompt,
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _confirmDeleteManual(
                    context: context,
                    palette: palette,
                    strings: strings,
                  ),
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    size: 19,
                    color: Color(0xFFEF4444),
                  ),
                ),
              ],
            ),
          ),
          if (_manualExpanded) ...[
            Container(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
              decoration: BoxDecoration(
                color: palette.isLight
                    ? Colors.grey.shade50.withOpacity(0.85)
                    : Colors.black.withOpacity(0.18),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(22),
                  bottomRight: Radius.circular(22),
                ),
              ),
              child: _buildGroupedConfigsList(
                profiles: manualProfiles,
                connState: connState,
                palette: palette,
                strings: strings,
                activeSubId: null,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGroupedConfigsList({
    required List<ServerProfile> profiles,
    required ConnectionUiState connState,
    required SpeedllThemePalette palette,
    required AppStrings strings,
    required String? activeSubId,
  }) {
    final sortedProfiles = [...profiles];
    if (_sortByPing) {
      sortedProfiles.sort((a, b) {
        final pingA = connState.pingForProfile(a.id);
        final pingB = connState.pingForProfile(b.id);
        final scoreA = (pingA != null && pingA > 0) ? pingA : 999999;
        final scoreB = (pingB != null && pingB > 0) ? pingB : 999999;
        return scoreA.compareTo(scoreB);
      });
    }

    // Group by Country
    final countryMap = <String, List<ServerProfile>>{};
    for (final p in sortedProfiles) {
      final loc = CountryFlagResolver.resolve(p);
      final key = strings.isFa ? loc.nameFa : loc.nameEn;
      countryMap.putIfAbsent(key, () => <ServerProfile>[]).add(p);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in countryMap.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4, right: 4, left: 4),
            child: Row(
              children: [
                CountryFlagAvatar(
                  location: CountryFlagResolver.resolve(entry.value.first),
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text(
                  '${entry.key} (${entry.value.length})',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: palette.textPrimary.withOpacity(0.85),
                  ),
                ),
              ],
            ),
          ),
          for (final profile in entry.value) ...[
            _buildCompactServerRow(
              profile: profile,
              connState: connState,
              palette: palette,
              strings: strings,
            ),
            const SizedBox(height: 6),
          ],
        ],
      ],
    );
  }

  Widget _buildCompactServerRow({
    required ServerProfile profile,
    required ConnectionUiState connState,
    required SpeedllThemePalette palette,
    required AppStrings strings,
  }) {
    final isSelected = profile.id == connState.activeProfile?.id &&
        !connState.isSmartMode;
    final isCurrentActive = profile.id == connState.activeProfile?.id;
    final loc = CountryFlagResolver.resolve(profile);
    final pingMs = connState.pingForProfile(profile.id);
    final pingColor = _pingBadgeColor(pingMs);

    return Container(
      decoration: BoxDecoration(
        color: palette.isLight
            ? Colors.white
            : palette.cardSurface.withOpacity(0.95),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCurrentActive
              ? palette.primaryAccent
              : palette.borderColor.withOpacity(0.65),
          width: isCurrentActive ? 1.8 : 1.0,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () async {
            final wasConnected = connState.isConnected;
            await ref
                .read(connectionControllerProvider.notifier)
                .selectProfile(profile, manualSelection: true);
            if (!mounted) return;
            if (wasConnected) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(strings.switchedWhileConnectedToast),
                  backgroundColor: const Color(0xFF16A34A),
                ),
              );
            }
            if (widget.isModal) {
              Navigator.of(context).pop();
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                CountryFlagAvatar(location: loc, size: 28),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: palette.primaryAccent.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              _transportSummary(profile),
                              style: TextStyle(
                                color: palette.primaryAccent,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Directionality(
                              textDirection: TextDirection.ltr,
                              child: Text(
                                () {
                                  final rawHost =
                                      (profile.serverAddress ?? '—').trim();
                                  final port = profile.serverPort ?? 443;
                                  final formattedHost = rawHost.contains(':') &&
                                          !rawHost.startsWith('[')
                                      ? '[$rawHost]'
                                      : rawHost;
                                  return '$formattedHost:$port';
                                }(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: palette.textSecondary.withOpacity(0.70),
                                  fontSize: 10.5,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: pingColor.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: pingColor.withOpacity(0.40)),
                  ),
                  child: Text(
                    strings.pingMsValue(pingMs),
                    style: TextStyle(
                      color: pingColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 10.5,
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  tooltip: strings.confirmDelete,
                  icon: Icon(
                    Icons.close_rounded,
                    size: 17,
                    color: palette.textSecondary.withOpacity(0.65),
                  ),
                  onPressed: () async {
                    await ref
                        .read(profilesListProvider.notifier)
                        .removeProfile(profile.id);
                  },
                ),
                Icon(
                  isSelected || isCurrentActive
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  size: 19,
                  color: isSelected || isCurrentActive
                      ? palette.primaryAccent
                      : Colors.blueGrey.shade400,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _activateSubscription(
    SubscriptionSource sub,
    List<ServerProfile> subProfiles,
  ) async {
    final connNotifier = ref.read(connectionControllerProvider.notifier);
    if (subProfiles.isNotEmpty) {
      await connNotifier.selectProfile(subProfiles.first, manualSelection: true);
    }
  }

  Future<void> _confirmDeleteSubscription({
    required BuildContext context,
    required SubscriptionSource sub,
    required String displayName,
    required SpeedllThemePalette palette,
    required AppStrings strings,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.dialogBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Row(
          children: [
            const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444)),
            const SizedBox(width: 8),
            Text(
              strings.deleteSubscriptionTitle,
              style: TextStyle(color: palette.textPrimary, fontSize: 16),
            ),
          ],
        ),
        content: Text(
          strings.deleteSubscriptionPrompt(displayName),
          style: TextStyle(
            color: palette.textPrimary.withOpacity(0.85),
            fontSize: 13.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              strings.cancelAction,
              style: TextStyle(color: palette.textPrimary),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(strings.confirmDelete),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref
          .read(connectionControllerProvider.notifier)
          .deleteSubscription(sub.id);
    }
  }

  Future<void> _confirmDeleteManual({
    required BuildContext context,
    required SpeedllThemePalette palette,
    required AppStrings strings,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.dialogBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Row(
          children: [
            const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444)),
            const SizedBox(width: 8),
            Text(
              strings.manualConfigsSectionTitle,
              style: TextStyle(color: palette.textPrimary, fontSize: 16),
            ),
          ],
        ),
        content: Text(
          strings.clearManualConfigsPrompt,
          style: TextStyle(
            color: palette.textPrimary.withOpacity(0.85),
            fontSize: 13.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              strings.cancelAction,
              style: TextStyle(color: palette.textPrimary),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(strings.confirmDelete),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref
          .read(connectionControllerProvider.notifier)
          .deleteManualProfiles();
    }
  }
}
