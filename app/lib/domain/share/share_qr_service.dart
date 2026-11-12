import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Monochrome QR matrix encoded as row-major `0` / `1` modules.
@immutable
class QrMatrixData {
  const QrMatrixData({
    required this.size,
    required this.modules,
  });

  final int size;
  final List<int> modules;

  bool get isValid => size > 0 && modules.length == size * size;

  bool moduleAt(int x, int y) => modules[(y * size) + x] != 0;
}

/// Abstracts native QR matrix encoding and OS text sharing so the UI stays
/// platform-safe and easy to override in tests without external packages.
abstract interface class ShareAndQrService {
  Future<QrMatrixData?> generateQrMatrix(String text);

  Future<bool> shareText(String text, {String? subject});
}

class AndroidShareAndQrService implements ShareAndQrService {
  const AndroidShareAndQrService({
    MethodChannel? channel,
  }) : _channel = channel ?? const MethodChannel('app.speedll.connect/share');

  final MethodChannel _channel;

  @override
  Future<QrMatrixData?> generateQrMatrix(String text) async {
    final clean = text.trim();
    if (clean.isEmpty) return null;
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'generateQrMatrix',
        <String, dynamic>{'text': clean},
      );
      if (result == null) return null;
      final size = (result['size'] as num?)?.toInt() ?? 0;
      final rawModules = result['modules'];
      if (size <= 0 || rawModules is! List) return null;
      final modules = rawModules.map((e) => (e as num).toInt()).toList();
      final data = QrMatrixData(size: size, modules: modules);
      return data.isValid ? data : null;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<bool> shareText(String text, {String? subject}) async {
    final clean = text.trim();
    if (clean.isEmpty) return false;
    try {
      final launched = await _channel.invokeMethod<bool>(
        'shareText',
        <String, dynamic>{
          'text': clean,
          if (subject != null && subject.trim().isNotEmpty)
            'subject': subject.trim(),
        },
      );
      return launched ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
