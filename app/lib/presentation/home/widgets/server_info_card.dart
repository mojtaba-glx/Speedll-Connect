import 'package:flutter/material.dart';

class ServerInfoCard extends StatelessWidget {
  const ServerInfoCard({
    required this.serverName,
    required this.subscriptionName,
    this.onTapServer,
    super.key,
  });

  final String serverName;
  final String subscriptionName;
  final VoidCallback? onTapServer;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          children: [
            InkWell(
              onTap: onTapServer,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(Icons.dns_outlined, color: colorScheme.primary),
                    const SizedBox(width: 12),
                    const Expanded(child: Text('موقعیت سرور')),
                    Text(
                      serverName,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.chevron_left_rounded, size: 20),
                  ],
                ),
              ),
            ),
            Divider(
              height: 24,
              color: colorScheme.outlineVariant,
            ),
            Row(
              children: [
                Icon(Icons.account_circle_outlined, color: colorScheme.primary),
                const SizedBox(width: 12),
                const Expanded(child: Text('اشتراک')),
                Text(
                  subscriptionName,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
