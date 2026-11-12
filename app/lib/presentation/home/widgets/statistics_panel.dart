import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speedll_subscription/speedll_subscription.dart';

import '../../../application/connection/connection_controller.dart';
import '../../../application/connection/connection_state.dart';
import '../../../application/localization/app_strings.dart';
import '../../../application/localization/locale_controller.dart';
import '../../../application/theme/theme_controller.dart';
import '../../../domain/format/traffic_formatter.dart';
import '../../../domain/ping/ping_service.dart';
import '../../../domain/profiles/country_flag_resolver.dart';
import 'country_flag_avatar.dart';

/// Statistics & Connection Details screen with real numeric throughput,
/// connected-hours timeline chart, server IP/IPv4-IPv6 badge, and full protocol model.
class StatisticsPanel extends ConsumerWidget {
  const StatisticsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final palette = ref.watch(themePaletteProvider);
    final connState = ref.watch(connectionControllerProvider);
    final activeProfile = connState.activeProfile;
    final location = CountryFlagResolver.resolve(activeProfile);
    final pingText = strings.pingMsValue(connState.livePingMs);

    final resolvedIp = activeProfile == null
        ? null
        : (PingService.resolveServerIpSync(
              activeProfile,
              preferIpv6: connState.routingOptions.enableIpv6,
            ) ??
            activeProfile.serverAddress);
    final ipVersion = TrafficFormatter.detectIpVersion(resolvedIp) ??
        (activeProfile != null
            ? (connState.routingOptions.enableIpv6 ? 'IPv6/v4' : 'IPv4')
            : null);

    final protocolDetails = activeProfile != null
        ? ProtocolDetailsFormatter.inspect(activeProfile)
        : null;
    final modeText =
        connState.isSmartMode ? strings.smartBadge : strings.manualBadge;
    final protocolCaptionParts = <String>[
      modeText,
      if (connState.routingOptions.enableMux) 'Mux',
      if (protocolDetails != null) ...protocolDetails.secondarySpecs,
    ];

    final downloadSpeedText = connState.isConnected
        ? TrafficFormatter.formatSpeed(connState.downlinkBytesPerSec)
        : '0 B/s';
    final uploadSpeedText = connState.isConnected
        ? TrafficFormatter.formatSpeed(connState.uplinkBytesPerSec)
        : '0 B/s';
    final downloadTotalText =
        (connState.isConnected || connState.downlinkTotalBytes > 0)
            ? '${strings.sessionTotalPrefix}: ${TrafficFormatter.formatBytes(connState.downlinkTotalBytes)}'
            : '—';
    final uploadTotalText =
        (connState.isConnected || connState.uplinkTotalBytes > 0)
            ? '${strings.sessionTotalPrefix}: ${TrafficFormatter.formatBytes(connState.uplinkTotalBytes)}'
            : '—';

    final sessionSpan = _effectiveSessionSpan(connState);
    final midSpan = Duration(milliseconds: sessionSpan.inMilliseconds ~/ 2);
    final peakBps = _peakTrafficBps(connState.trafficHistory);

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
          const SizedBox(height: 18),

          // Top Numeric Download & Upload Speed + Total Cards
          Row(
            children: [
              Expanded(
                child: _SpeedMetricCard(
                  label: strings.downloadLabel,
                  value: downloadSpeedText,
                  secondaryValue: downloadTotalText,
                  icon: Icons.download_rounded,
                  accentColor: palette.secondaryAccent,
                  palette: palette,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SpeedMetricCard(
                  label: strings.uploadLabel,
                  value: uploadSpeedText,
                  secondaryValue: uploadTotalText,
                  icon: Icons.upload_rounded,
                  accentColor: palette.primaryAccentLight,
                  palette: palette,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Live Ping + Connected Hours Strip
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 6,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => ref
                    .read(connectionControllerProvider.notifier)
                    .pingActiveProfile(),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: palette.isLight
                        ? Colors.white.withOpacity(0.65)
                        : Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: palette.borderColor),
                  ),
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
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: palette.isLight
                      ? Colors.white.withOpacity(0.65)
                      : Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: palette.borderColor),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      size: 16,
                      color: connState.isConnected
                          ? palette.secondaryAccent
                          : palette.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(
                        TrafficFormatter.formatDurationHms(
                          connState.connectedDuration,
                        ),
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    if (connState.connectedDuration > Duration.zero) ...[
                      Text(
                        ' · ${TrafficFormatter.formatConnectedHoursLabel(connState.connectedDuration, isPersian: strings.isFa)}',
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Dual-Line Session Traffic Timeline Chart (covering connected hours)
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: palette.isLight
                  ? Colors.white.withOpacity(0.88)
                  : Colors.black.withOpacity(0.28),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: palette.borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _LegendDot(
                      color: const Color(0xFF4ADE80),
                      label: strings.isFa ? 'دریافت' : 'Download',
                      textColor: palette.textSecondary,
                    ),
                    const SizedBox(width: 12),
                    _LegendDot(
                      color: const Color(0xFFC084FC),
                      label: strings.isFa ? 'ارسال' : 'Upload',
                      textColor: palette.textSecondary,
                    ),
                    const Spacer(),
                    if (peakBps > 0)
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(
                          TrafficFormatter.formatSpeed(peakBps),
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: palette.textSecondary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 118,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(
                        painter: _DualTrafficChartPainter(
                          samples: connState.trafficHistory,
                          isConnected: connState.isConnected,
                          isLight: palette.isLight,
                        ),
                        child: const SizedBox.expand(),
                      ),
                      if (!connState.isConnected &&
                          connState.trafficHistory.isEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: palette.isLight
                                ? Colors.white.withOpacity(0.85)
                                : Colors.black.withOpacity(0.45),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            strings.noActiveTrafficHint,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              color: palette.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        TrafficFormatter.formatAxisElapsed(
                          connState.trafficHistory.isNotEmpty
                              ? connState.trafficHistory.first.elapsed
                              : Duration.zero,
                          totalSpan: sessionSpan,
                        ),
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: palette.textSecondary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      Text(
                        TrafficFormatter.formatAxisElapsed(
                          midSpan,
                          totalSpan: sessionSpan,
                        ),
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: palette.textSecondary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      Text(
                        TrafficFormatter.formatAxisElapsed(
                          sessionSpan,
                          totalSpan: sessionSpan,
                        ),
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: palette.textSecondary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Connection Details 2x2 Grid
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: palette.isLight
                  ? Colors.white.withOpacity(0.92)
                  : palette.cardSurface.withOpacity(0.76),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: palette.borderColor),
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
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _DetailWhiteCard(
                          icon: Icons.wifi_tethering_rounded,
                          title: strings.statusLabel(connState.phase),
                          subtitle: TrafficFormatter.formatDurationHms(
                            connState.connectedDuration,
                          ),
                          subtitleLtr: true,
                          caption: connState.connectedDuration > Duration.zero
                              ? TrafficFormatter.formatConnectedHoursLabel(
                                  connState.connectedDuration,
                                  isPersian: strings.isFa,
                                )
                              : strings.connectedDurationTitle,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _DetailWhiteCard(
                          icon: Icons.public_rounded,
                          title: strings.countryLabel,
                          subtitle:
                              '${location.flagEmoji} ${location.localizedName(strings.isFa)}',
                          footer: activeProfile != null
                              ? _IpVersionFooter(
                                  address: resolvedIp ?? '—',
                                  ipVersion: ipVersion,
                                )
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _DetailWhiteCard(
                          icon: Icons.bolt_rounded,
                          title: strings.protocolAndModeLabel,
                          subtitle: protocolDetails?.headlineModel ?? '—',
                          subtitleMaxLines: 2,
                          subtitleLtr: protocolDetails != null,
                          caption: activeProfile != null
                              ? protocolCaptionParts.join(' · ')
                              : null,
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
                          subtitleMaxLines: 2,
                          caption: _routingCaption(connState, strings),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Duration _effectiveSessionSpan(ConnectionUiState connState) {
    var span = connState.connectedDuration;
    if (connState.trafficHistory.isNotEmpty) {
      final lastElapsed = connState.trafficHistory.last.elapsed;
      if (lastElapsed > span) {
        span = lastElapsed;
      }
    }
    return span.isNegative ? Duration.zero : span;
  }

  static int _peakTrafficBps(List<TrafficSample> samples) {
    var peak = 0;
    for (final sample in samples) {
      if (sample.downlinkBps > peak) peak = sample.downlinkBps;
      if (sample.uplinkBps > peak) peak = sample.uplinkBps;
    }
    return peak;
  }

  static String _routingCaption(
    ConnectionUiState connState,
    AppStrings strings,
  ) {
    final regionLabel = switch (connState.routingOptions.region) {
      RoutingRegion.china => strings.regionChina,
      RoutingRegion.russia => strings.regionRussia,
      RoutingRegion.global => strings.regionGlobal,
      RoutingRegion.auto || RoutingRegion.iran => strings.regionIran,
    };
    final sniffLabel = connState.routingOptions.enableTrafficSniffing
        ? (strings.isFa ? 'اسنیف فعال' : 'Sniffing On')
        : (strings.isFa ? 'بدون تداخل اسنیف' : 'Clean Sniffing');
    return '$regionLabel · $sniffLabel';
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({
    required this.color,
    required this.label,
    required this.textColor,
  });

  final Color color;
  final String label;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: textColor,
          ),
        ),
      ],
    );
  }
}

class _SpeedMetricCard extends StatelessWidget {
  const _SpeedMetricCard({
    required this.label,
    required this.value,
    required this.secondaryValue,
    required this.icon,
    required this.accentColor,
    required this.palette,
  });

  final String label;
  final String value;
  final String secondaryValue;
  final IconData icon;
  final Color accentColor;
  final SpeedllThemePalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
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
                    fontSize: 10.5,
                    color: palette.textPrimary.withOpacity(0.75),
                  ),
                ),
                const SizedBox(height: 2),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: palette.textPrimary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  secondaryValue,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: palette.textSecondary,
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

class _IpVersionFooter extends StatelessWidget {
  const _IpVersionFooter({
    required this.address,
    required this.ipVersion,
  });

  final String address;
  final String? ipVersion;

  @override
  Widget build(BuildContext context) {
    final isV6 = ipVersion == 'IPv6';
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        children: [
          if (ipVersion != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: (isV6 ? const Color(0xFF0EA5E9) : const Color(0xFF7E22CE))
                    .withOpacity(0.14),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color:
                      (isV6 ? const Color(0xFF0EA5E9) : const Color(0xFF7E22CE))
                          .withOpacity(0.45),
                ),
              ),
              child: Text(
                ipVersion!,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  color:
                      isV6 ? const Color(0xFF0369A1) : const Color(0xFF6B21A8),
                ),
              ),
            ),
            const SizedBox(width: 5),
          ],
          Expanded(
            child: Text(
              address,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: Colors.blueGrey.shade700,
              ),
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
    this.caption,
    this.footer,
    this.subtitleMaxLines = 1,
    this.subtitleLtr = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? caption;
  final Widget? footer;
  final int subtitleMaxLines;
  final bool subtitleLtr;

  @override
  Widget build(BuildContext context) {
    final subtitleWidget = Text(
      subtitle,
      maxLines: subtitleMaxLines,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: Colors.blueGrey.shade800,
        fontWeight: FontWeight.w700,
        fontSize: 11.5,
        height: 1.35,
      ),
    );

    return Container(
      padding: const EdgeInsets.all(13),
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
          const SizedBox(height: 10),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF1E1B4B),
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 3),
          subtitleLtr
              ? Directionality(
                  textDirection: TextDirection.ltr,
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: subtitleWidget,
                  ),
                )
              : subtitleWidget,
          if (caption != null && caption!.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              caption!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.blueGrey.shade600,
                fontWeight: FontWeight.w600,
                fontSize: 10,
                height: 1.3,
              ),
            ),
          ],
          if (footer != null) ...[
            const SizedBox(height: 6),
            footer!,
          ],
        ],
      ),
    );
  }
}

class _DualTrafficChartPainter extends CustomPainter {
  const _DualTrafficChartPainter({
    required this.samples,
    required this.isConnected,
    required this.isLight,
  });

  final List<TrafficSample> samples;
  final bool isConnected;
  final bool isLight;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color =
          (isLight ? Colors.black : Colors.white).withOpacity(0.09)
      ..strokeWidth = 1;

    for (var i = 0; i < 4; i++) {
      final y = size.height * (i / 3);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (samples.length < 2) {
      final baselineY = size.height * 0.88;
      final basePaint = Paint()
        ..color = isConnected
            ? const Color(0xFF4ADE80).withOpacity(0.55)
            : Colors.grey.withOpacity(0.35)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;
      canvas.drawLine(
        Offset(0, baselineY),
        Offset(size.width, baselineY),
        basePaint,
      );
      return;
    }

    var peak = 1024; // minimum 1 KB/s scale so tiny background keepalives don't fill 100%
    for (final s in samples) {
      peak = math.max(peak, math.max(s.downlinkBps, s.uplinkBps));
    }

    final firstMs = samples.first.elapsed.inMilliseconds;
    final lastMs = samples.last.elapsed.inMilliseconds;
    final spanMs = lastMs - firstMs;

    List<Offset> buildPoints(int Function(TrafficSample s) pickBps) {
      final points = <Offset>[];
      for (var i = 0; i < samples.length; i++) {
        final s = samples[i];
        final xRatio = spanMs > 0
            ? ((s.elapsed.inMilliseconds - firstMs) / spanMs).clamp(0.0, 1.0)
            : (i / (samples.length - 1));
        final valRatio = (pickBps(s) / peak).clamp(0.0, 1.0);
        final x = xRatio * size.width;
        final y = size.height * (0.90 - valRatio * 0.78);
        points.add(Offset(x, y));
      }
      return points;
    }

    final downPoints = buildPoints((s) => s.downlinkBps);
    final upPoints = buildPoints((s) => s.uplinkBps);

    _drawSeries(
      canvas: canvas,
      size: size,
      points: downPoints,
      color: const Color(0xFF4ADE80),
      baselineY: size.height * 0.90,
    );
    _drawSeries(
      canvas: canvas,
      size: size,
      points: upPoints,
      color: const Color(0xFFC084FC),
      baselineY: size.height * 0.90,
    );
  }

  void _drawSeries({
    required Canvas canvas,
    required Size size,
    required List<Offset> points,
    required Color color,
    required double baselineY,
  }) {
    if (points.length < 2) return;
    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 0; i < points.length - 1; i++) {
      final curr = points[i];
      final next = points[i + 1];
      final midX = (curr.dx + next.dx) / 2;
      linePath.cubicTo(midX, curr.dy, midX, next.dy, next.dx, next.dy);
    }

    final areaPath = Path.from(linePath)
      ..lineTo(points.last.dx, baselineY)
      ..lineTo(points.first.dx, baselineY)
      ..close();

    final areaPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withOpacity(0.28),
          color.withOpacity(0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(areaPath, areaPaint);

    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(linePath, strokePaint);

    final last = points.last;
    canvas.drawCircle(last, 3.6, Paint()..color = color);
    canvas.drawCircle(last, 1.8, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _DualTrafficChartPainter oldDelegate) {
    return oldDelegate.samples != samples ||
        oldDelegate.isConnected != isConnected ||
        oldDelegate.isLight != isLight;
  }
}
