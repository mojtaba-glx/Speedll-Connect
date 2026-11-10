import 'package:flutter/material.dart';
import '../../../domain/connection/connection_phase.dart';

class ConnectionButton extends StatelessWidget {
  const ConnectionButton({
    required this.phase,
    required this.onPressed,
    super.key,
  });

  final ConnectionPhase phase;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final isConnected = phase == ConnectionPhase.connected;
    final isConnecting = phase == ConnectionPhase.connecting ||
        phase == ConnectionPhase.preparing;

    final buttonColor = isConnected
        ? Colors.green.shade600
        : isConnecting
            ? Colors.orange.shade600
            : colorScheme.primaryContainer;

    final iconColor = isConnected || isConnecting
        ? Colors.white
        : colorScheme.onPrimaryContainer;

    return Center(
      child: Material(
        color: buttonColor,
        shape: const CircleBorder(),
        elevation: 2,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 170,
            height: 170,
            child: Icon(
              Icons.power_settings_new_rounded,
              size: 76,
              color: iconColor,
            ),
          ),
        ),
      ),
    );
  }
}
