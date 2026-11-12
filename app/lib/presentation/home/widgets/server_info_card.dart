import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../application/theme/theme_controller.dart';
import '../../../domain/profiles/country_flag_resolver.dart';
import 'country_flag_avatar.dart';

class ServerInfoCard extends ConsumerWidget {
  const ServerInfoCard({
    required this.serverName,
    required this.subscriptionName,
    required this.location,
    this.profilesLabel = 'پروفایل‌ها',
    this.modeBadge,
    this.serverAddress,
    this.pingMs,
    this.isSmartMode = false,
    this.onTapServer,
    super.key,
  });

  final String serverName;
  final String subscriptionName;
  final CountryLocationInfo location;
  final String profilesLabel;
  final String? modeBadge;
  final String? serverAddress;
  final int? pingMs;
  final bool isSmartMode;
  final VoidCallback? onTapServer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(themePaletteProvider);
    final isLight = palette.isLight;
    final pingText = pingMs == null
        ? '— ms'
        : (pingMs! < 0 ? 'Timeout' : '$pingMs ms');

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isLight
              ? [
                  Colors.white,
                  const Color(0xFFF3E8FF),
                ]
              : [
                  palette.cardSurface.withOpacity(0.85),
                  palette.dialogBackground.withOpacity(0.88),
                ],
        ),
        border: Border.all(
          color: palette.borderColor,
          width: 1.3,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isLight ? 0.06 : 0.28),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTapServer,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Row(
              children: [
                CountryFlagAvatar(
                  location: location,
                  size: 46,
                  isSmartMode: isSmartMode,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            profilesLabel,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: palette.textSecondary,
                            ),
                          ),
                          if (modeBadge != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: isSmartMode
                                    ? palette.secondaryAccent.withOpacity(0.20)
                                    : palette.primaryAccent.withOpacity(0.22),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isSmartMode
                                      ? palette.secondaryAccent.withOpacity(0.6)
                                      : palette.primaryAccentLight
                                          .withOpacity(0.5),
                                ),
                              ),
                              child: Text(
                                modeBadge!,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: isSmartMode
                                      ? palette.secondaryAccent
                                      : palette.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              serverName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w800,
                                color: palette.textPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SignalBarsIndicator(pingMs: pingMs),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${serverAddress != null && serverAddress!.isNotEmpty ? "IP $serverAddress  |  " : ""}$subscriptionName  |  $pingText',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isLight
                              ? Colors.blueGrey.shade700
                              : Colors.white.withOpacity(0.75),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        palette.buttonCoreGradient.first,
                        palette.buttonCoreGradient[1],
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: palette.primaryAccent.withOpacity(0.45),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
