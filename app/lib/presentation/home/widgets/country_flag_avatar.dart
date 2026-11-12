import 'package:flutter/material.dart';
import '../../../domain/profiles/country_flag_resolver.dart';

/// Circular country flag badge matching the reference UI design.
class CountryFlagAvatar extends StatelessWidget {
  const CountryFlagAvatar({
    required this.location,
    this.size = 42,
    this.isSmartMode = false,
    super.key,
  });

  final CountryLocationInfo location;
  final double size;
  final bool isSmartMode;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                location.primaryColor,
                location.secondaryColor,
                if (location.tertiaryColor != null) location.tertiaryColor!,
              ],
            ),
            border: Border.all(
              color: Colors.white.withOpacity(0.45),
              width: 1.8,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Container(
            width: size - 4,
            height: size - 4,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withOpacity(0.18),
            ),
            alignment: Alignment.center,
            child: Text(
              location.flagEmoji,
              style: TextStyle(
                fontSize: size * 0.52,
                height: 1.0,
              ),
            ),
          ),
        ),
        if (isSmartMode)
          Positioned(
            right: -3,
            bottom: -3,
            child: Container(
              width: size * 0.44,
              height: size * 0.44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF9333EA),
                border: Border.all(color: Colors.white, width: 1.4),
              ),
              child: Icon(
                Icons.bolt_rounded,
                size: size * 0.28,
                color: const Color(0xFF4ADE80),
              ),
            ),
          ),
      ],
    );
  }
}

/// Three vertical signal strength bars (`|||`) colored by ping latency in ms.
class SignalBarsIndicator extends StatelessWidget {
  const SignalBarsIndicator({
    required this.pingMs,
    this.height = 13,
    super.key,
  });

  final int? pingMs;
  final double height;

  @override
  Widget build(BuildContext context) {
    final ms = pingMs;
    final Color activeColor;
    final int activeBars;

    if (ms == null) {
      activeColor = const Color(0xFF4ADE80);
      activeBars = 3;
    } else if (ms < 0) {
      activeColor = Colors.redAccent;
      activeBars = 1;
    } else if (ms < 160) {
      activeColor = const Color(0xFF22C55E);
      activeBars = 3;
    } else if (ms < 350) {
      activeColor = const Color(0xFFF59E0B);
      activeBars = 2;
    } else {
      activeColor = const Color(0xFFEF4444);
      activeBars = 1;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(3, (index) {
        final isActive = index < activeBars;
        final barHeight = height * (0.55 + (index * 0.225));
        return Container(
          width: 2.6,
          height: barHeight,
          margin: const EdgeInsets.symmetric(horizontal: 1.3),
          decoration: BoxDecoration(
            color: isActive ? activeColor : Colors.grey.withOpacity(0.35),
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }
}
