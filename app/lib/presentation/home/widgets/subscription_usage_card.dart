import 'package:flutter/material.dart';
import 'package:speedll_subscription/speedll_subscription.dart';

import '../../../application/localization/app_strings.dart';
import '../../../application/theme/theme_controller.dart';

/// Modern usage card shown for the active subscription. It visualizes consumed
/// traffic, percentage circle, remaining volume and days, and includes an inline
/// refresh button to update subscription profiles.
class SubscriptionUsageCard extends StatelessWidget {
  const SubscriptionUsageCard({
    super.key,
    required this.source,
    required this.strings,
    required this.palette,
    this.compact = false,
    this.onTap,
    this.onRefresh,
    this.isRefreshing = false,
  });

  final SubscriptionSource source;
  final AppStrings strings;
  final SpeedllThemePalette palette;
  final bool compact;
  final VoidCallback? onTap;
  final VoidCallback? onRefresh;
  final bool isRefreshing;

  @override
  Widget build(BuildContext context) {
    final info = source.userInfo;
    final used = info?.usedBytes;
    final total = info?.totalBytes;
    final remaining = info?.remainingBytes;
    final fraction = info?.usedFraction;
    final days = info?.remainingDays();
    final expiry = info?.expiresAt;
    final expired = days != null && days <= 0;
    final hasVolume = total != null && total > 0;
    final warningColor = fraction != null && fraction >= 0.85
        ? const Color(0xFFEF4444)
        : fraction != null && fraction >= 0.65
            ? const Color(0xFFF59E0B)
            : palette.secondaryAccent;

    final displayName = source.displayUserName;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: palette.isLight
              ? <Color>[
                  Colors.white.withOpacity(0.96),
                  palette.primaryAccent.withOpacity(0.12),
                ]
              : <Color>[
                  palette.cardSurface.withOpacity(0.94),
                  palette.primaryAccent.withOpacity(0.24),
                ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: palette.secondaryAccent.withOpacity(0.35),
          width: 1.3,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.20),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Row: Circular Refresh Button + User Name + Status / Days Remaining
                Row(
                  children: [
                    // Circular refresh button (replaces old ribbon icon)
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: isRefreshing ? null : onRefresh,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: palette.primaryAccent.withOpacity(0.22),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: palette.secondaryAccent.withOpacity(0.40),
                              width: 1.2,
                            ),
                          ),
                          child: isRefreshing
                              ? Padding(
                                  padding: const EdgeInsets.all(9),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: palette.secondaryAccent,
                                  ),
                                )
                              : Icon(
                                  Icons.sync_rounded,
                                  color: palette.secondaryAccent,
                                  size: 21,
                                ),
                        ),
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
                              color: palette.textPrimary,
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            strings.subscriptionUsageActive,
                            style: TextStyle(
                              color: palette.secondaryAccent,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: (expired
                                ? const Color(0xFFEF4444)
                                : warningColor)
                            .withOpacity(0.14),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: (expired
                                  ? const Color(0xFFEF4444)
                                  : warningColor)
                              .withOpacity(0.35),
                          width: 1.0,
                        ),
                      ),
                      child: Text(
                        days == null
                            ? '—'
                            : expired
                                ? strings.subscriptionUsageExpired
                                : '$days ${strings.subscriptionUsageDaysLeft}',
                        style: TextStyle(
                          color:
                              expired ? const Color(0xFFEF4444) : warningColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Middle & Bottom Section: Circular Gauge (Right) + Metrics Column (Left)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Circular Percentage Ring Gauge
                    SizedBox(
                      width: 88,
                      height: 88,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          TweenAnimationBuilder<double>(
                            tween: Tween<double>(
                              begin: 0,
                              end: fraction ?? 0,
                            ),
                            duration: const Duration(milliseconds: 700),
                            curve: Curves.easeOutCubic,
                            builder: (context, value, _) {
                              return SizedBox(
                                width: 86,
                                height: 86,
                                child: CircularProgressIndicator(
                                  value: hasVolume ? value : 0,
                                  strokeWidth: 8,
                                  strokeCap: StrokeCap.round,
                                  backgroundColor:
                                      palette.textPrimary.withOpacity(0.10),
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    warningColor,
                                  ),
                                ),
                              );
                            },
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                hasVolume && fraction != null
                                    ? '${(fraction * 100).round()}%'
                                    : '—',
                                style: TextStyle(
                                  color: palette.textPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                strings.subscriptionUsageUsed,
                                style: TextStyle(
                                  color: palette.textPrimary.withOpacity(0.65),
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),

                    // Metrics: Consumed volume, progress bar, remaining volume, expiry date
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _metricRow(
                            strings.subscriptionUsageUsed,
                            used == null
                                ? '—'
                                : total == null
                                    ? '${_formatBytes(used)} / ${strings.subscriptionUsageUnlimited}'
                                    : '${_formatBytes(used)} / ${_formatBytes(total)}',
                            palette,
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: TweenAnimationBuilder<double>(
                              tween:
                                  Tween<double>(begin: 0, end: fraction ?? 0),
                              duration: const Duration(milliseconds: 700),
                              curve: Curves.easeOutCubic,
                              builder: (context, value, _) {
                                return LinearProgressIndicator(
                                  minHeight: 8,
                                  value: hasVolume ? value : 0,
                                  backgroundColor:
                                      palette.textPrimary.withOpacity(0.09),
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    warningColor,
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 10),
                          _metricRow(
                            strings.subscriptionUsageRemaining,
                            remaining != null ? _formatBytes(remaining) : '—',
                            palette,
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(
                                Icons.event_available_rounded,
                                size: 14,
                                color: palette.textPrimary.withOpacity(0.55),
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  '${strings.subscriptionUsageExpiry}: '
                                  '${expiry != null ? _formatDate(expiry) : '—'}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color:
                                        palette.textPrimary.withOpacity(0.65),
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (!hasVolume && expiry == null) ...[
                  const SizedBox(height: 10),
                  Text(
                    strings.subscriptionUsageNoData,
                    style: TextStyle(
                      color: palette.textPrimary.withOpacity(0.52),
                      fontSize: 10,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _metricRow(String label, String value, SpeedllThemePalette palette) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: palette.textPrimary.withOpacity(0.65),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: palette.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  static String _formatBytes(int bytes) {
    const units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var index = 0;
    while (value >= 1024 && index < units.length - 1) {
      value /= 1024;
      index++;
    }
    final formatted = value >= 100
        ? value.toStringAsFixed(0)
        : value >= 10
            ? value.toStringAsFixed(1)
            : value.toStringAsFixed(2);
    return '$formatted ${units[index]}';
  }

  static String _formatDate(DateTime date) {
    final local = date.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}/$month/$day';
  }
}
