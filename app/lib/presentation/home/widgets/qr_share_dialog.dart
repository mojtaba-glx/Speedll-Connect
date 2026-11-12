import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/connection/connection_controller.dart';
import '../../../application/localization/locale_controller.dart';
import '../../../application/theme/theme_controller.dart';
import '../../../domain/share/share_qr_service.dart';

/// Offline QR Code & Share modal sheet/dialog for subscription links and proxy configs.
class QrShareDialog extends ConsumerStatefulWidget {
  const QrShareDialog({
    required this.title,
    required this.shareText,
    this.subtitle,
    this.copiedToast,
    super.key,
  });

  final String title;
  final String shareText;
  final String? subtitle;
  final String? copiedToast;

  static Future<void> show(
    BuildContext context, {
    required String title,
    required String shareText,
    String? subtitle,
    String? copiedToast,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => QrShareDialog(
        title: title,
        shareText: shareText,
        subtitle: subtitle,
        copiedToast: copiedToast,
      ),
    );
  }

  @override
  ConsumerState<QrShareDialog> createState() => _QrShareDialogState();
}

class _QrShareDialogState extends ConsumerState<QrShareDialog> {
  late final Future<QrMatrixData?> _qrFuture;

  @override
  void initState() {
    super.initState();
    _qrFuture =
        ref.read(shareQrServiceProvider).generateQrMatrix(widget.shareText);
  }

  Future<void> _copyToClipboard() async {
    await Clipboard.setData(ClipboardData(text: widget.shareText));
    if (!mounted) return;
    final strings = ref.read(appStringsProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(widget.copiedToast ?? strings.configCopiedToast),
        backgroundColor: const Color(0xFF16A34A),
      ),
    );
  }

  Future<void> _shareViaSystem() async {
    final launched = await ref.read(shareQrServiceProvider).shareText(
          widget.shareText,
          subject: widget.subtitle ?? widget.title,
        );
    if (!launched && mounted) {
      await _copyToClipboard();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = ref.watch(themePaletteProvider);
    final strings = ref.watch(appStringsProvider);

    return Dialog(
      backgroundColor: palette.dialogBackground,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: palette.primaryAccent.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      Icons.qr_code_2_rounded,
                      color: palette.primaryAccent,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (widget.subtitle != null &&
                            widget.subtitle!.trim().isNotEmpty)
                          Text(
                            widget.subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.textSecondary,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(
                      Icons.close_rounded,
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Center(
                child: FutureBuilder<QrMatrixData?>(
                  future: _qrFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return SizedBox(
                        width: 210,
                        height: 210,
                        child: Center(
                          child: CircularProgressIndicator(
                            color: palette.secondaryAccent,
                          ),
                        ),
                      );
                    }
                    final data = snapshot.data;
                    if (data == null || !data.isValid) {
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: palette.cardSurface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: palette.borderColor),
                        ),
                        child: Text(
                          strings.qrUnavailableFallback,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: 12.5,
                            height: 1.5,
                          ),
                        ),
                      );
                    }
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.18),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: SizedBox(
                        width: 204,
                        height: 204,
                        child: CustomPaint(
                          painter: _QrMatrixPainter(data: data),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: palette.isLight
                      ? Colors.black.withOpacity(0.04)
                      : Colors.black.withOpacity(0.24),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: palette.borderColor),
                ),
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: SelectableText(
                    widget.shareText,
                    maxLines: 3,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: palette.textSecondary,
                      height: 1.35,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _copyToClipboard,
                      icon: const Icon(Icons.content_copy_rounded, size: 17),
                      label: Text(strings.copyLinkAction),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: palette.textPrimary,
                        side: BorderSide(color: palette.borderColor),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _shareViaSystem,
                      icon: const Icon(Icons.share_rounded, size: 17),
                      label: Text(strings.shareLinkAction),
                      style: FilledButton.styleFrom(
                        backgroundColor: palette.primaryAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QrMatrixPainter extends CustomPainter {
  const _QrMatrixPainter({required this.data});

  final QrMatrixData data;

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = Colors.white;
    canvas.drawRect(Offset.zero & size, bgPaint);

    final fgPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;

    final moduleSize = size.width / data.size;
    for (var y = 0; y < data.size; y++) {
      for (var x = 0; x < data.size; x++) {
        if (!data.moduleAt(x, y)) continue;
        // Slight subpixel overlap avoids hairline seams on fractional DPI scaling.
        canvas.drawRect(
          Rect.fromLTWH(
            x * moduleSize,
            y * moduleSize,
            moduleSize + 0.3,
            moduleSize + 0.3,
          ),
          fgPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QrMatrixPainter oldDelegate) {
    return oldDelegate.data != data;
  }
}
