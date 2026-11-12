import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../application/theme/theme_controller.dart';
import '../../../domain/connection/connection_phase.dart';

class ConnectionButton extends ConsumerStatefulWidget {
  const ConnectionButton({
    required this.phase,
    required this.onPressed,
    super.key,
  });

  final ConnectionPhase phase;
  final VoidCallback onPressed;

  @override
  ConsumerState<ConnectionButton> createState() => _ConnectionButtonState();
}

class _ConnectionButtonState extends ConsumerState<ConnectionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  AppLifecycleListener? _lifecycleListener;
  bool _isPressed = false;

  bool get _isTestEnv => Platform.environment.containsKey('FLUTTER_TEST');

  bool get _shouldAnimate =>
      !_isTestEnv &&
      (widget.phase == ConnectionPhase.connected ||
          widget.phase == ConnectionPhase.connecting ||
          widget.phase == ConnectionPhase.preparing ||
          widget.phase == ConnectionPhase.reconnecting);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
      value: 0.35,
    );
    _syncAnimation();
    if (!_isTestEnv) {
      _lifecycleListener = AppLifecycleListener(
        onStateChange: (state) {
          if (state == AppLifecycleState.resumed) {
            _syncAnimation();
          } else {
            _controller.stop();
          }
        },
      );
    }
  }

  @override
  void didUpdateWidget(covariant ConnectionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.phase != widget.phase) {
      _syncAnimation();
    }
  }

  void _syncAnimation() {
    if (_shouldAnimate) {
      if (!_controller.isAnimating) {
        _controller.repeat();
      }
    } else {
      _controller.stop();
      _controller.value = 0.35;
    }
  }

  @override
  void dispose() {
    _lifecycleListener?.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Returns complementary Solar (warm golden/yellow) and Lunar/Stellar (soft sky-blue/cyan)
  /// ray colors tailored to the active [SpeedllThemePreset].
  (Color solarRay, Color lunarRay, List<Color> connectedCore) _celestialColors(
    SpeedllThemePalette palette,
  ) {
    return switch (palette.preset) {
      SpeedllThemePreset.royalPurple => (
          const Color(0xFFFACC15), // Warm Sun Gold
          const Color(0xFF7DD3FC), // Soft Sky Blue
          const [
            Color(0xFF38BDF8),
            Color(0xFF9333EA),
            Color(0xFF4C1D95),
          ],
        ),
      SpeedllThemePreset.midnightDark => (
          const Color(0xFFFBBF24), // Golden Amber
          const Color(0xFF38BDF8), // Ice Cyan
          const [
            Color(0xFF38BDF8),
            Color(0xFF0284C7),
            Color(0xFF0F172A),
          ],
        ),
      SpeedllThemePreset.cyberCyan => (
          const Color(0xFFFDE047), // Radiant Lemon Gold
          const Color(0xFF67E8F9), // Luminous Aqua
          const [
            Color(0xFF2DD4BF),
            Color(0xFF0891B2),
            Color(0xFF164E63),
          ],
        ),
      SpeedllThemePreset.emeraldGreen => (
          const Color(0xFFFACC15), // Sunlit Gold
          const Color(0xFF7DD3FC), // Sky Cyan
          const [
            Color(0xFF34D399),
            Color(0xFF059669),
            Color(0xFF064E3B),
          ],
        ),
      SpeedllThemePreset.oceanBlue => (
          const Color(0xFFFDE047), // Solar Yellow
          const Color(0xFF93C5FD), // Soft Celestial Blue
          const [
            Color(0xFF60A5FA),
            Color(0xFF2563EB),
            Color(0xFF1E3A8A),
          ],
        ),
      SpeedllThemePreset.cleanLight => (
          const Color(0xFFF59E0B), // Warm Amber Sun
          const Color(0xFF0EA5E9), // Bright Sky Blue
          const [
            Color(0xFF38BDF8),
            Color(0xFF7E22CE),
            Color(0xFF581C87),
          ],
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final palette = ref.watch(themePaletteProvider);
    final isConnected = widget.phase == ConnectionPhase.connected;
    final isConnecting = widget.phase == ConnectionPhase.connecting ||
        widget.phase == ConnectionPhase.preparing ||
        widget.phase == ConnectionPhase.reconnecting;
    final isDisconnecting = widget.phase == ConnectionPhase.disconnecting;
    final isBusy = isConnecting || isDisconnecting;

    final (solarColor, lunarColor, connectedCore) = _celestialColors(palette);

    final List<Color> coreGradient = isBusy
        ? const [Color(0xFFFDE047), Color(0xFFF59E0B), Color(0xFFB45309)]
        : isConnected
            ? connectedCore
            : palette.buttonCoreGradient;

    return Center(
      child: SizedBox(
        width: 236,
        height: 236,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value;
            final pulse = 0.5 + 0.5 * math.sin(t * 2 * math.pi * 2);

            return Stack(
              alignment: Alignment.center,
              children: [
                // 1. Ambient Outer Solar & Lunar Corona Glow
                Container(
                  width: isConnected ? 222 + (pulse * 8) : 208,
                  height: isConnected ? 222 + (pulse * 8) : 208,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: isConnected
                          ? [
                              solarColor.withOpacity(0.28 + pulse * 0.10),
                              lunarColor.withOpacity(0.22 + pulse * 0.08),
                              palette.primaryAccent.withOpacity(0.08),
                              Colors.transparent,
                            ]
                          : isBusy
                              ? [
                                  solarColor.withOpacity(0.26),
                                  lunarColor.withOpacity(0.12),
                                  Colors.transparent,
                                ]
                              : [
                                  palette.primaryAccentLight.withOpacity(0.16),
                                  palette.primaryAccent.withOpacity(0.05),
                                  Colors.transparent,
                                ],
                      stops: isConnected
                          ? const [0.35, 0.65, 0.85, 1.0]
                          : const [0.4, 0.75, 1.0],
                    ),
                  ),
                ),

                // 2. Custom Painted Sunbeams, Lunar Crescent Arcs & Twinkling Stars
                CustomPaint(
                  size: const Size(232, 232),
                  painter: _CelestialCoronaPainter(
                    progress: t,
                    isConnected: isConnected,
                    isBusy: isBusy,
                    solarColor: solarColor,
                    lunarColor: lunarColor,
                    accentColor: palette.primaryAccentLight,
                  ),
                ),

                // 3. Frosted Orbital Glass Ring
                Container(
                  width: 152,
                  height: 152,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: palette.primaryAccent.withOpacity(
                      isConnected ? 0.22 : 0.16,
                    ),
                    border: Border.all(
                      color: isConnected
                          ? Color.lerp(lunarColor, solarColor, pulse)!
                              .withOpacity(0.78)
                          : isBusy
                              ? solarColor.withOpacity(0.65)
                              : palette.primaryAccentLight.withOpacity(0.32),
                      width: isConnected ? 2.2 : 1.6,
                    ),
                    boxShadow: isConnected
                        ? [
                            BoxShadow(
                              color: lunarColor.withOpacity(0.35),
                              blurRadius: 22,
                              spreadRadius: 2,
                            ),
                            BoxShadow(
                              color: solarColor.withOpacity(0.25),
                              blurRadius: 30,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                ),

                // 4. Core Tactile 3D Power Orb with Specular Shine
                AnimatedScale(
                  scale: _isPressed ? 0.93 : 1.0,
                  duration: const Duration(milliseconds: 130),
                  curve: Curves.easeOutCubic,
                  child: GestureDetector(
                    onTapDown: isDisconnecting
                        ? null
                        : (_) => setState(() => _isPressed = true),
                    onTapUp: isDisconnecting
                        ? null
                        : (_) => setState(() => _isPressed = false),
                    onTapCancel: () => setState(() => _isPressed = false),
                    onTap: isDisconnecting
                        ? null
                        : () {
                            HapticFeedback.lightImpact();
                            widget.onPressed();
                          },
                    child: Container(
                      width: 118,
                      height: 118,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: coreGradient,
                        ),
                        border: Border.all(
                          color: isConnected
                              ? Color.lerp(solarColor, Colors.white, 0.45)!
                                  .withOpacity(0.88)
                              : Colors.white.withOpacity(0.32),
                          width: isConnected ? 2.4 : 1.6,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (isConnected
                                    ? lunarColor
                                    : coreGradient.first)
                                .withOpacity(isConnected ? 0.62 : 0.48),
                            blurRadius: isConnected ? 28 : 20,
                            spreadRadius: isConnected ? 3 : 0,
                            offset: const Offset(0, 6),
                          ),
                          if (isConnected)
                            BoxShadow(
                              color: solarColor.withOpacity(0.45),
                              blurRadius: 34,
                              spreadRadius: 2,
                            ),
                        ],
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Top crescent glass specular reflection
                          Positioned(
                            top: 8,
                            child: Container(
                              width: 76,
                              height: 34,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(34),
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.white.withOpacity(0.38),
                                    Colors.white.withOpacity(0.0),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          // Center Power / Busy / Connected Icon
                          if (isBusy)
                            const SizedBox(
                              width: 44,
                              height: 44,
                              child: CircularProgressIndicator(
                                strokeWidth: 3.2,
                                color: Colors.white,
                              ),
                            )
                          else
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.power_settings_new_rounded,
                                  size: 50,
                                  color: Colors.white,
                                  shadows: [
                                    Shadow(
                                      color: isConnected
                                          ? solarColor.withOpacity(0.85)
                                          : Colors.black26,
                                      blurRadius: isConnected ? 16 : 6,
                                    ),
                                  ],
                                ),
                                if (isConnected) ...[
                                  const SizedBox(height: 2),
                                  Container(
                                    width: 18,
                                    height: 3.5,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(4),
                                      color: solarColor,
                                      boxShadow: [
                                        BoxShadow(
                                          color: solarColor.withOpacity(0.9),
                                          blurRadius: 8,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CelestialCoronaPainter extends CustomPainter {
  _CelestialCoronaPainter({
    required this.progress,
    required this.isConnected,
    required this.isBusy,
    required this.solarColor,
    required this.lunarColor,
    required this.accentColor,
  });

  final double progress;
  final bool isConnected;
  final bool isBusy;
  final Color solarColor;
  final Color lunarColor;
  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    if (!isConnected && !isBusy) {
      // Subtle idle starlight ring with delicate ticks
      final ringPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = accentColor.withOpacity(0.20);
      canvas.drawCircle(center, maxRadius - 14, ringPaint);

      final tickPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 1.6
        ..color = accentColor.withOpacity(0.26);

      const tickCount = 16;
      for (var i = 0; i < tickCount; i++) {
        final angle = (i * 2 * math.pi) / tickCount;
        final inner = maxRadius - 24;
        final outer = maxRadius - (i.isEven ? 16 : 20);
        canvas.drawLine(
          Offset(
            center.dx + inner * math.cos(angle),
            center.dy + inner * math.sin(angle),
          ),
          Offset(
            center.dx + outer * math.cos(angle),
            center.dy + outer * math.sin(angle),
          ),
          tickPaint,
        );
      }
      return;
    }

    final rotAngle = progress * 2 * math.pi;

    // 1. Luminous Lunar & Solar Crescent Orbital Arcs
    final arcRect = Rect.fromCircle(center: center, radius: 86);
    final lunarArcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.2
      ..color = lunarColor.withOpacity(0.82)
      ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 4);
    final solarArcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.2
      ..color = solarColor.withOpacity(0.88)
      ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 4);

    canvas.drawArc(arcRect, rotAngle, math.pi * 0.68, false, solarArcPaint);
    canvas.drawArc(
      arcRect,
      rotAngle + math.pi,
      math.pi * 0.68,
      false,
      lunarArcPaint,
    );

    // 2. Radiant Sunbeams (اشعه‌های خورشید و ماه دور دکمه اتصال)
    final rayCount = isConnected ? 24 : 12;
    for (var i = 0; i < rayCount; i++) {
      final isSolar = i.isEven;
      final baseAngle = (i * 2 * math.pi / rayCount) +
          (isSolar ? rotAngle * 0.5 : -rotAngle * 0.35);
      final wave = math.sin((progress * 2 * math.pi * 2) + i * 0.9);

      const innerR = 79.0;
      final outerR = isConnected
          ? (isSolar ? 105.0 + wave * 8.0 : 98.0 - wave * 6.0)
          : 94.0 + wave * 4.0;

      final rayColor = isSolar ? solarColor : lunarColor;
      final rayPaint = Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = isSolar ? 2.8 : 2.1
        ..shader = LinearGradient(
          colors: [
            rayColor.withOpacity(isConnected ? 0.92 : 0.65),
            rayColor.withOpacity(0.05),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: maxRadius));

      final p1 = Offset(
        center.dx + innerR * math.cos(baseAngle),
        center.dy + innerR * math.sin(baseAngle),
      );
      final p2 = Offset(
        center.dx + outerR * math.cos(baseAngle),
        center.dy + outerR * math.sin(baseAngle),
      );
      canvas.drawLine(p1, p2, rayPaint);
    }

    // 3. Twinkling 4-Point Celestial Stars (ستاره‌های درخشان در مدار دکمه)
    if (isConnected) {
      const starCount = 6;
      for (var i = 0; i < starCount; i++) {
        final starAngle =
            -rotAngle * 0.8 + (i * 2 * math.pi / starCount) + 0.4;
        final twinkle =
            0.45 + 0.55 * math.sin((progress * 2 * math.pi * 3) + i * 1.3);
        final orbitR = 96.0 + (i.isEven ? 10.0 : 2.0);
        final starCenter = Offset(
          center.dx + orbitR * math.cos(starAngle),
          center.dy + orbitR * math.sin(starAngle),
        );
        final starColor = i.isEven ? solarColor : lunarColor;
        _drawFourPointStar(
          canvas,
          starCenter,
          radius: 4.5 + (twinkle * 3.0),
          color: starColor.withOpacity(0.55 + twinkle * 0.45),
        );
      }
    }
  }

  void _drawFourPointStar(
    Canvas canvas,
    Offset center, {
    required double radius,
    required Color color,
  }) {
    final inner = radius * 0.28;
    final path = Path()
      ..moveTo(center.dx, center.dy - radius)
      ..quadraticBezierTo(
        center.dx + inner,
        center.dy - inner,
        center.dx + radius,
        center.dy,
      )
      ..quadraticBezierTo(
        center.dx + inner,
        center.dy + inner,
        center.dx,
        center.dy + radius,
      )
      ..quadraticBezierTo(
        center.dx - inner,
        center.dy + inner,
        center.dx - radius,
        center.dy,
      )
      ..quadraticBezierTo(
        center.dx - inner,
        center.dy - inner,
        center.dx,
        center.dy - radius,
      )
      ..close();

    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = color;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CelestialCoronaPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.isConnected != isConnected ||
        oldDelegate.isBusy != isBusy ||
        oldDelegate.solarColor != solarColor ||
        oldDelegate.lunarColor != lunarColor;
  }
}
