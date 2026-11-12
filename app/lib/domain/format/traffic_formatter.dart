/// Formatting utilities for live tunnel speeds, byte totals, connected hours,
/// chart axis timestamps, and IPv4/IPv6 detection.
class TrafficFormatter {
  const TrafficFormatter._();

  static const List<String> _byteUnits = <String>['B', 'KB', 'MB', 'GB', 'TB'];

  /// Formats [bytes] cleanly (e.g., `0 B`, `420 KB`, `18.4 MB`, `1.25 GB`).
  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    double value = bytes.toDouble();
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < _byteUnits.length - 1) {
      value /= 1024;
      unitIndex++;
    }
    if (unitIndex == 0) {
      return '${value.round()} B';
    }
    final decimals = value >= 100 ? 0 : (value >= 10 ? 1 : 2);
    return '${value.toStringAsFixed(decimals)} ${_byteUnits[unitIndex]}';
  }

  /// Formats throughput in [bytesPerSec] as `B/s`, `KB/s`, `MB/s`, or `GB/s`.
  static String formatSpeed(int bytesPerSec) {
    return '${formatBytes(bytesPerSec)}/s';
  }

  /// Formats [duration] as `HH:MM:SS` (always showing zero-padded hours).
  static String formatDurationHms(Duration duration) {
    final safe = duration.isNegative ? Duration.zero : duration;
    String two(int n) => n.toString().padLeft(2, '0');
    final hours = two(safe.inHours);
    final minutes = two(safe.inMinutes.remainder(60));
    final seconds = two(safe.inSeconds.remainder(60));
    return '$hours:$minutes:$seconds';
  }

  /// Formats a chart X-axis timestamp showing hours & minutes (`H:MM` or `MM:SS` under 1h).
  static String formatAxisElapsed(
    Duration elapsed, {
    required Duration totalSpan,
  }) {
    final safe = elapsed.isNegative ? Duration.zero : elapsed;
    String two(int n) => n.toString().padLeft(2, '0');
    if (totalSpan.inHours >= 1 || safe.inHours >= 1) {
      final hours = two(safe.inHours);
      final minutes = two(safe.inMinutes.remainder(60));
      return '$hours:$minutes';
    }
    final minutes = two(safe.inMinutes);
    final seconds = two(safe.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  /// Returns a concise connected hours badge (e.g., `2.5 ساعت` or `2.5h` / `45 دقیقه`).
  static String formatConnectedHoursLabel(
    Duration duration, {
    required bool isPersian,
  }) {
    final safe = duration.isNegative ? Duration.zero : duration;
    if (safe.inMinutes < 1) {
      final secs = safe.inSeconds;
      return isPersian ? '$secs ثانیه' : '${secs}s';
    }
    if (safe.inHours < 1) {
      final mins = safe.inMinutes;
      return isPersian ? '$mins دقیقه' : '${mins}m';
    }
    final hoursValue = safe.inMinutes / 60.0;
    final formattedHours = hoursValue >= 10
        ? hoursValue.toStringAsFixed(0)
        : hoursValue.toStringAsFixed(1);
    return isPersian ? '$formattedHours ساعت' : '${formattedHours}h';
  }

  /// Returns `'IPv6'`, `'IPv4'`, or `null` if [ipOrHost] is not an IP literal.
  static String? detectIpVersion(String? ipOrHost) {
    if (ipOrHost == null) return null;
    final clean = ipOrHost.trim().replaceAll('[', '').replaceAll(']', '');
    if (clean.isEmpty) return null;
    try {
      Uri.parseIPv4Address(clean);
      return 'IPv4';
    } on FormatException {
      try {
        Uri.parseIPv6Address(clean);
        return 'IPv6';
      } on FormatException {
        return null;
      }
    }
  }
}
