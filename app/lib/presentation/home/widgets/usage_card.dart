import 'package:flutter/material.dart';

class UsageCard extends StatelessWidget {
  const UsageCard({
    required this.dataUsage,
    required this.subscriptionRemaining,
    super.key,
  });

  final String dataUsage;
  final String subscriptionRemaining;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Expanded(
              child: _UsageItem(
                label: 'مصرف داده',
                value: dataUsage,
                icon: Icons.data_usage_rounded,
              ),
            ),
            Container(
              width: 1,
              height: 42,
              color: colorScheme.outlineVariant,
            ),
            Expanded(
              child: _UsageItem(
                label: 'اعتبار اشتراک',
                value: subscriptionRemaining,
                icon: Icons.event_available_rounded,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UsageItem extends StatelessWidget {
  const _UsageItem({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Icon(icon, color: colorScheme.primary),
        const SizedBox(height: 8),
        Text(label, textAlign: TextAlign.center),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
      ],
    );
  }
}
