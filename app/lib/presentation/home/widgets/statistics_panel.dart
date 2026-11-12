import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../application/connection/connection_controller.dart';
import '../../../application/localization/locale_controller.dart';
import '../../../application/theme/theme_controller.dart';
import '../../../domain/profiles/country_flag_resolver.dart';
import 'country_flag_avatar.dart';

/// Statistics & Connection Details screen matching the right panel of the reference UI.
class StatisticsPanel extends ConsumerWidget {
  const StatisticsPanel({super.key});

  String _formatDuration(Duration d) {
    final hours = d.inHours.toString().padLeft(2, '0');
    final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final palette = ref.watch(themePaletteProvider);
    final connState = ref.watch(connectionControllerProvider);
    final activeProfile = connState.activeProfile;
    final location = CountryFlagResolver.resolve(activeProfile);
    final pingText = strings.pingMsValue(connState.livePingMs);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            strings.statisticsHeader,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: palette.textPrimary,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 20),

          // Top Download & Upload Cards (matching right panel of screenshot)
          Row(
            children: [
              Expanded(
                child: _SpeedMetricCard(
                  label: strings.downloadLabel,
                  value: connState.isConnected ? 'TCP / UDP' : '—',
                  icon: Icons.download_rounded,
                  accentColor: palette.secondaryAccent,
                  palette: palette,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SpeedMetricCard(
                  label: strings.uploadLabel,
                  value: connState.isConnected
                      ? (activeProfile?.protocol.toUpperCase() ?? 'ACTIVE')
                      : '—',
                  icon: Icons.upload_rounded,
                  accentColor: palette.primaryAccentLight,
                  palette: palette,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Center Live Ping Label
          Center(
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => ref
                  .read(connectionControllerProvider.notifier)
                  .pingActiveProfile(),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SignalBarsIndicator(pingMs: connState.livePingMs),
                    const SizedBox(width: 8),
                    Text(
                      '${strings.livePingLabel}: $pingText',
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Dual-Line Latency & Activity Waveform Chart
          Container(
            height: 140,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
            decoration: BoxDecoration(
              color: palette.isLight
                  ? Colors.white.withOpacity(0.85)
                  : Colors.black.withOpacity(0.28),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: palette.borderColor,
              ),
            ),
            child: CustomPaint(
              painter: _DualWaveChartPainter(
                pingHistory: connState.pingHistory,
                isConnected: connState.isConnected,
              ),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(height: 22),

          // Connection Details Section (matching bottom of right panel in screenshot)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: palette.isLight
                  ? Colors.white.withOpacity(0.92)
                  : palette.cardSurface.withOpacity(0.76),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: palette.borderColor,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.connectionDetailsHeader,
                  style: TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w800,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _DetailWhiteCard(
                        icon: Icons.wifi_tethering_rounded,
                        title: strings.statusLabel(connState.phase),
                        subtitle: _formatDuration(connState.connectedDuration),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _DetailWhiteCard(
                        icon: Icons.public_rounded,
                        title: strings.countryLabel,
                        subtitle:
                            '${location.flagEmoji} ${location.localizedName(strings.isFa)}',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _DetailWhiteCard(
                        icon: Icons.bolt_rounded,
                        title: strings.protocolAndModeLabel,
                        subtitle:
                            '${connState.isSmartMode ? strings.smartBadge : strings.manualBadge} · ${activeProfile?.protocol.toUpperCase() ?? "—"}',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _DetailWhiteCard(
                        icon: Icons.alt_route_rounded,
                        title: strings.routingModeLabel,
                        subtitle: connState.routingOptions.bypassIranDomains
                            ? strings.routingDomesticBypassValue
                            : strings.routingGlobalValue,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SpeedMetricCard extends StatelessWidget {
  const _SpeedMetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.accentColor,
    required this.palette,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accentColor;
  final SpeedllThemePalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: palette.isLight
            ? Colors.white.withOpacity(0.92)
            : palette.cardSurface.withOpacity(0.78),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: accentColor.withOpacity(0.40),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accentColor.withOpacity(0.22),
              border: Border.all(color: accentColor, width: 1.5),
            ),
            child: Icon(icon, color: accentColor, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: palette.textPrimary.withOpacity(0.75),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: palette.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailWhiteCard extends StatelessWidget {
  const _DetailWhiteCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF5F3FF), Color(0xFFEDE9FE)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF9333EA).withOpacity(0.14),
            ),
            child: Icon(icon, color: const Color(0xFF7E22CE), size: 19),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF1E1B4B),
              fontWeight: FontWeight.w800,
              fontSize: 13.5,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.blueGrey.shade700,
              fontWeight: FontWeight.w600,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _DualWaveChartPainter extends CustomPainter {
  const _DualWaveChartPainter({
    required this.pingHistory,
    required this.isConnected,
  });

  final List<int> pingHistory;
  final bool isConnected;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.10)
      ..strokeWidth = 1;

    for (var i = 0; i < 4; i++) {
      final y = size.height * (i / 3);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final samples = pingHistory.length >= 4
        ? pingHistory
        : (isConnected
            ? const <int>[65, 58, 72, 49, 54, 46, 61, 48, 52, 44]
            : const <int>[120, 120, 120, 120, 120, 120]);

    final greenPath = Path();
    final purplePath = Path();

    final count = samples.length;
    for (var i = 0; i < count; i++) {
      final x = (i / (count - 1)) * size.width;
      final normalized = (samples[i].clamp(15, 350) - 15) / 335.0;
      final y1 = size.height * (0.25 + (1.0 - normalized) * 0.45);
      final y2 = size.height * (0.48 + (normalized * 0.38));

      if (i == 0) {
        greenPath.moveTo(x, y1);
        purplePath.moveTo(x, y2);
      } else {
        greenPath.lineTo(x, y1);
        purplePath.lineTo(x, y2);
      }
    }

    final greenPaint = Paint()
      ..color = const Color(0xFF4ADE80)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;

    final purplePaint = Paint()
      ..color = const Color(0xFFC084FC)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(greenPath, greenPaint);
    canvas.drawPath(purplePath, purplePaint);
  }

  @override
  bool shouldRepaint(covariant _DualWaveChartPainter oldDelegate) {
    return oldDelegate.pingHistory != pingHistory ||
        oldDelegate.isConnected != isConnected;
  }
}
