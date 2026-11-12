import 'package:flutter/services.dart';

/// Platform-neutral contract for scanning QR code configurations via the device camera.
abstract interface class QrScannerService {
  /// Opens the native camera QR scanner and returns the scanned text, or `null` if cancelled.
  Future<String?> scanQrCode();
}

class AndroidQrScannerService implements QrScannerService {
  const AndroidQrScannerService({
    MethodChannel? methodChannel,
  }) : _methodChannel = methodChannel ??
            const MethodChannel('app.speedll.connect/qr_scanner');

  final MethodChannel _methodChannel;

  @override
  Future<String?> scanQrCode() async {
    try {
      final scanned = await _methodChannel.invokeMethod<String>('scanQrCode');
      final trimmed = scanned?.trim();
      if (trimmed == null || trimmed.isEmpty) {
        return null;
      }
      return trimmed;
    } on PlatformException catch (e) {
      if (e.code == 'CANCELLED') {
        return null;
      }
      throw Exception(e.message ?? 'خطا در اسکن بارکد QR با دوربین.');
    } on MissingPluginException {
      throw Exception('اسکنر دوربین در این پلتفرم در دسترس نیست.');
    }
  }
}
