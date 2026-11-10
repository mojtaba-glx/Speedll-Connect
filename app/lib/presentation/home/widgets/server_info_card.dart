import 'package:flutter/material.dart';

class ServerInfoCard extends StatelessWidget {
  const ServerInfoCard({
    required this.serverName,
    required this.subscriptionName,
    super.key,
  });

  final String serverName;
  final String subscriptionName;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          children: [
            _InfoRow(
              icon: Icons.dns_outlined,
              label: 'موقعیت سرور',
              value: serverName,
            ),
            Divider(
              height: 28,
              color: colorScheme.outlineVariant,
            ),
            _InfoRow(
              icon: Icons.account_circle_outlined,
              label: 'اشتراک',
              value: subscriptionName,
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Icon(icon, color: colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(child: Text(label)),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
