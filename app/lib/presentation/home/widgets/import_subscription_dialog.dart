import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speedll_subscription/speedll_subscription.dart';
import '../../../application/connection/connection_controller.dart';

class ImportSubscriptionDialog extends ConsumerStatefulWidget {
  const ImportSubscriptionDialog({super.key});

  @override
  ConsumerState<ImportSubscriptionDialog> createState() =>
      _ImportSubscriptionDialogState();
}

class _ImportSubscriptionDialogState
    extends ConsumerState<ImportSubscriptionDialog> {
  final TextEditingController _textController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _processImport() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      setState(() {
        _errorMessage = 'لطفاً لینک کانفیگ یا محتوای اشتراک را وارد کنید.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    const detector = SubscriptionDetector();
    final result = await detector.detectAndParse(text);

    if (!mounted) return;

    if (result.isSuccess && result.profiles.isNotEmpty) {
      ref.read(profilesListProvider.notifier).addProfiles(result.profiles);
      // Auto select the first imported profile if none selected
      final currentSelected =
          ref.read(connectionControllerProvider).activeProfile;
      if (currentSelected == null) {
        ref
            .read(connectionControllerProvider.notifier)
            .selectProfile(result.profiles.first);
      }

      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تعداد ${result.profiles.length} سرور با موفقیت اضافه شد.',
          ),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = result.errorMessage ?? 'قالب لینک یا محتوا نامعتبر است.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        'افزودن اشتراک یا کانفیگ',
        textAlign: TextAlign.right,
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'لینک تکی (VLESS، VMess، Hysteria2، Trojan یا Shadowsocks) یا لینک چندتایی سابسکرپشن را در کادر زیر جای‌گذاری کنید:',
              style: TextStyle(fontSize: 13),
              textAlign: TextAlign.right,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _textController,
              maxLines: 4,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                hintText: 'vless://... یا vmess://... یا hysteria2://...',
                hintStyle: const TextStyle(fontSize: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
                textAlign: TextAlign.right,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: const Text('انصراف'),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _processImport,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('افزودن سرورها'),
        ),
      ],
    );
  }
}
