import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speedll_subscription/speedll_subscription.dart';
import '../../../application/connection/connection_controller.dart';
import '../../../domain/ping/ping_service.dart';

class ImportSubscriptionDialog extends ConsumerStatefulWidget {
  const ImportSubscriptionDialog({super.key});

  @override
  ConsumerState<ImportSubscriptionDialog> createState() =>
      _ImportSubscriptionDialogState();
}

class _ImportSubscriptionDialogState
    extends ConsumerState<ImportSubscriptionDialog> {
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _textController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final clipText = data?.text?.trim() ?? '';
    if (clipText.isNotEmpty && mounted) {
      setState(() {
        _textController.text = clipText;
        _errorMessage = null;
      });
    }
  }

  Future<void> _scanWithCamera() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final scanner = ref.read(qrScannerServiceProvider);
      final scannedText = await scanner.scanQrCode();
      if (!mounted) return;

      if (scannedText == null || scannedText.trim().isEmpty) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      _textController.text = scannedText.trim();
      await _processImport(sourceOverride: ProfileSource.qrCode);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _processImport({ProfileSource? sourceOverride}) async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      setState(() {
        _isLoading = false;
        _errorMessage =
            'لطفاً لینک کانفیگ، آدرس اشتراک یا بارکد QR را وارد کنید.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final lower = text.toLowerCase();
    final isWebSubscriptionUrl = !text.contains('\n') &&
        (lower.startsWith('https://') || lower.startsWith('http://'));

    List<ServerProfile> importedProfiles = const <ServerProfile>[];
    String? failureMessage;
    String? importedSubscriptionId;

    if (isWebSubscriptionUrl) {
      final updater = ref.read(subscriptionUpdaterProvider);
      final updateResult = await updater.fetchAndValidate(text);
      if (updateResult.isSuccess && updateResult.profiles.isNotEmpty) {
        importedProfiles = updateResult.profiles;
        final uri = Uri.tryParse(text);
        final customName = _nameController.text.trim();
        String autoName = '';
        if (uri != null) {
          if (uri.fragment.trim().isNotEmpty) {
            autoName = Uri.decodeComponent(uri.fragment.trim());
          } else {
            for (final q in ['name', 'user', 'username', 'remark', 'title']) {
              final val = uri.queryParameters[q]?.trim();
              if (val != null && val.isNotEmpty) {
                autoName = Uri.decodeComponent(val);
                break;
              }
            }
            if (autoName.isEmpty) {
              final segs =
                  uri.pathSegments.where((s) => s.trim().isNotEmpty).toList();
              final subIdx = segs.indexWhere((s) => s.toLowerCase() == 'sub');
              if (subIdx >= 0 && subIdx + 1 < segs.length) {
                final c = segs[subIdx + 1].trim();
                if (!c.contains('.') && c.length <= 24) {
                  autoName = Uri.decodeComponent(c);
                }
              }
            }
          }
        }
        final existingSubs = ref.read(subscriptionsListProvider);
        final subId = 'sub_${SafeProxyUri.stableHash(text)}';
        final existingMatch =
            existingSubs.where((s) => s.id == subId || s.url == text).firstOrNull;
        final extractedSubscriber = SubscriptionSource.sanitizeSubscriberName(
              updateResult.subscriberName,
            ) ??
            SubscriptionSource.extractSubscriberName(
              url: text,
              profiles: updateResult.profiles,
            );
        final cleanAutoName =
            SubscriptionSource.sanitizeSubscriberName(autoName) ?? '';
        final existingClean = existingMatch != null
            ? SubscriptionSource.sanitizeSubscriberName(existingMatch.name)
            : null;
        final fallbackName = SubscriptionSource.generateSmartFallbackName(text);
        final cleanCustomName = customName.isNotEmpty
            ? (customName.toLowerCase().startsWith('base64:')
                ? (SubscriptionSource.sanitizeSubscriberName(customName) ??
                    customName)
                : customName)
            : '';
        final resolvedName = cleanCustomName.isNotEmpty
            ? cleanCustomName
            : (extractedSubscriber != null
                ? SubscriptionSource.formatSubscriptionTitle(
                    extractedSubscriber,
                  )
                : (existingMatch != null &&
                        existingClean != null &&
                        !existingMatch.name.contains('(')
                    ? existingMatch.displayUserName
                    : (cleanAutoName.isNotEmpty
                        ? SubscriptionSource.formatSubscriptionTitle(
                            cleanAutoName,
                          )
                        : 'اشتراک $fallbackName')));
        final subSource = SubscriptionSource(
          id: subId,
          name: resolvedName,
          url: text,
          lastUpdatedAt: DateTime.now().toUtc(),
          lastStatusMessage:
              'دریافت موفق (${updateResult.profiles.length} سرور)',
          userInfo: updateResult.userInfo,
          subscriberName: extractedSubscriber,
        );
        importedSubscriptionId = subSource.id;
        await ref
            .read(subscriptionsListProvider.notifier)
            .addOrUpdateSubscription(subSource);
      } else {
        failureMessage = updateResult.errorMessage ??
            'خطا در دریافت یا اعتبارسنجی لینک اشتراک.';
      }
    } else {
      const detector = SubscriptionDetector();
      final result = await detector.detectAndParse(text);
      final usableProfiles =
          result.profiles.where(PingService.isConnectableServer).toList();
      if (result.isSuccess && usableProfiles.isNotEmpty) {
        importedProfiles = sourceOverride != null
            ? usableProfiles
                .map((p) => p.copyWith(source: sourceOverride))
                .toList()
            : usableProfiles;
      } else {
        failureMessage = result.isSuccess
            ? 'این محتوا فقط شامل ردیف اطلاعات وضعیت است و کانفیگ قابل اتصال ندارد.'
            : result.errorMessage ?? 'قالب لینک یا محتوا نامعتبر است.';
      }
    }

    if (!mounted) return;

    if (importedProfiles.isNotEmpty) {
      final profilesNotifier = ref.read(profilesListProvider.notifier);
      if (importedSubscriptionId != null) {
        final annotated = importedProfiles
            .map(
              (profile) => profile.copyWith(
                extraParams: <String, dynamic>{
                  ...profile.extraParams,
                  'subscriptionId': importedSubscriptionId,
                },
              ),
            )
            .toList();
        importedProfiles = annotated;
        await profilesNotifier.replaceSubscriptionProfiles(
          importedSubscriptionId,
          annotated,
        );
      } else {
        await profilesNotifier.addProfiles(importedProfiles);
      }

      final connNotifier = ref.read(connectionControllerProvider.notifier);

      if (!mounted) return;
      Navigator.of(context).pop();
      final realCount =
          importedProfiles.where(PingService.isConnectableServer).length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تعداد ${realCount > 0 ? realCount : importedProfiles.length} سرور ذخیره شد؛ اتصال به سرور جدید آغاز گردید.',
          ),
          backgroundColor: Colors.green.shade700,
        ),
      );
      unawaited(connNotifier.activateAndConnectImportedProfiles(importedProfiles));
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = failureMessage ?? 'قالب لینک یا محتوا نامعتبر است.';
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
              'لینک اشتراک (HTTPS)، بارکد QR، فایل JSON/Clash یا لینک کانفیگ (VLESS، VMess، Trojan، Shadowsocks، Hysteria2، TUIC، WireGuard) را وارد کنید:',
              style: TextStyle(fontSize: 13),
              textAlign: TextAlign.right,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _nameController,
              textAlign: TextAlign.right,
              decoration: InputDecoration(
                hintText: 'نام اشتراک (اختیاری - مثلاً: اشتراک اول یا VIP)',
                hintStyle: const TextStyle(fontSize: 12),
                prefixIcon: const Icon(Icons.folder_special_outlined, size: 18),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isLoading ? null : _scanWithCamera,
                    icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                    label: const Text(
                      'اسکن بارکد QR با دوربین',
                      style: TextStyle(fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _isLoading ? null : _pasteFromClipboard,
                  icon: const Icon(Icons.content_paste_rounded, size: 18),
                  label: const Text(
                    'جای‌گذاری',
                    style: TextStyle(fontSize: 12),
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _textController,
              maxLines: 4,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                hintText:
                    'https://.../sub/.../all.txt یا vless://... یا vmess://...',
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
          onPressed: _isLoading ? null : () => _processImport(),
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
