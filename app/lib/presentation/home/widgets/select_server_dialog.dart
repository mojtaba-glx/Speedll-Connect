import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../application/connection/connection_controller.dart';

class SelectServerDialog extends ConsumerWidget {
  const SelectServerDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(profilesListProvider);
    final activeProfile =
        ref.watch(connectionControllerProvider).activeProfile;

    return AlertDialog(
      title: const Text('انتخاب سرور', textAlign: TextAlign.right),
      content: SizedBox(
        width: double.maxFinite,
        child: profiles.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'هنوز هیچ سروری اضافه نشده است.\nاز دکمه افزودن اشتراک برای اضافه کردن کانفیگ استفاده کنید.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13),
                ),
              )
            : ListView.separated(
                shrinkWrap: true,
                itemCount: profiles.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final profile = profiles[index];
                  final isSelected = profile.id == activeProfile?.id;

                  return ListTile(
                    leading: Icon(
                      isSelected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                    title: Text(
                      profile.displayName,
                      style: TextStyle(
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    subtitle: Text(
                      '${profile.protocol.toUpperCase()} · ${profile.serverAddress ?? ""}:${profile.serverPort ?? ""}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    onTap: () {
                      ref
                          .read(connectionControllerProvider.notifier)
                          .selectProfile(profile);
                      Navigator.of(context).pop();
                    },
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('بستن'),
        ),
      ],
    );
  }
}
