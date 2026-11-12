import 'dart:async';
import 'dart:io';
import 'package:speedll_subscription/speedll_subscription.dart';

/// Measures real TCP handshake latency (ping in milliseconds) for VPN server profiles
/// and selects the optimal lowest-latency server in Smart Mode.
class PingService {
  const PingService({
    this.timeout = const Duration(milliseconds: 1400),
    Future<int> Function(ServerProfile profile)? customProber,
  }) : _customProber = customProber;

  final Duration timeout;
  final Future<int> Function(ServerProfile profile)? _customProber;

  static final Map<String, String> _resolvedHosts = <String, String>{};
  static final Map<String, DateTime> _dnsExpiry = <String, DateTime>{};
  static final Map<String, Future<String?>> _dnsInFlight =
      <String, Future<String?>>{};

  /// Returns `true` if [profile] represents a real connectable VPN proxy server
  /// rather than a panel info/status placeholder (`127.0.0.1`, `0.0.0.0`, etc.).
  static bool isConnectableServer(ServerProfile profile) {
    if (profile.extraParams['isInfoNode'] == true) return false;
    final host = (profile.serverAddress ?? '').trim();
    if (host.isEmpty) return false;
    return !SafeProxyUri.isInfoMetadataProfile(
      host: host,
      port: profile.serverPort ?? 443,
      displayName: profile.displayName,
      uuid: profile.extraParams['uuid']?.toString(),
    );
  }

  /// Measures the TCP connection latency to [profile.serverAddress]:[profile.serverPort] in milliseconds.
  /// When [samples] is greater than one, multiple handshakes are attempted in
  /// parallel and the fastest successful result is returned. This mirrors the
  /// "best of N" latency display used by popular clients and avoids showing a
  /// single congested handshake as the server's real delay.
  Future<int> measurePingMs(
    ServerProfile profile, {
    int samples = 1,
  }) async {
    if (_customProber != null) {
      return _customProber(profile);
    }

    if (!isConnectableServer(profile)) {
      return -1;
    }

    final host = profile.serverAddress?.trim() ?? '';
    final port = profile.serverPort ?? 443;
    if (host.isEmpty || port <= 0 || port > 65535) {
      return -1;
    }

    final proto = profile.protocol.toLowerCase();
    final isUdpBased = proto == 'wireguard' ||
        proto == 'hysteria2' ||
        proto == 'hysteria' ||
        proto == 'tuic' ||
        profile.extraParams['transportType']?.toString().toLowerCase() == 'quic';

    final attempts = samples < 1 ? 1 : samples;
    if (attempts == 1) {
      return _probeOnce(host, port, acceptRstForUdp: isUdpBased);
    }

    final results = await Future.wait(
      List<Future<int>>.generate(
        attempts,
        (_) => _probeOnce(host, port, acceptRstForUdp: isUdpBased),
      ),
    );
    var best = -1;
    for (final value in results) {
      if (value > 0 && (best < 0 || value < best)) {
        best = value;
      }
    }
    return best;
  }

  Future<int> _probeOnce(
    String host,
    int port, {
    bool acceptRstForUdp = false,
  }) async {
    final stopwatch = Stopwatch()..start();
    Socket? socket;
    try {
      final target = await _resolveHost(host);
      socket = await Socket.connect(
        target ?? host,
        port,
        timeout: timeout,
      );
      stopwatch.stop();
      final elapsed = stopwatch.elapsedMilliseconds;
      return elapsed > 0 ? elapsed : 1;
    } on SocketException catch (e) {
      stopwatch.stop();
      if (acceptRstForUdp) {
        final msg = e.message.toLowerCase();
        final code = e.osError?.errorCode;
        if (code == 111 || msg.contains('connection refused')) {
          final elapsed = stopwatch.elapsedMilliseconds;
          if (elapsed > 0 && elapsed < timeout.inMilliseconds) {
            return elapsed;
          }
        }
      }
      return -1;
    } catch (_) {
      stopwatch.stop();
      return -1;
    } finally {
      try {
        socket?.destroy();
      } catch (_) {}
    }
  }

  /// Returns the cached IP address for [host] if previously resolved.
  static String? getCachedIp(String host) {
    if (InternetAddress.tryParse(host) != null) return host;
    return _resolvedHosts[host];
  }

  /// Extracts IPv4 or IPv6 address from raw text or remark string.
  static String? extractIp(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    final v4 = RegExp(
      r'\b(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b',
    ).firstMatch(text);
    if (v4 != null) {
      final ip = v4.group(0)!;
      if (!ip.startsWith('127.') && ip != '0.0.0.0') return ip;
    }
    final v6 = RegExp(
      r'\b(?:[0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}\b',
    ).firstMatch(text);
    if (v6 != null) return v6.group(0)!;
    return null;
  }

  /// Resolves the destination server IP (IPv4 or IPv6) synchronously from profile metadata,
  /// server address, remark IP, or cached DNS resolution.
  static String? resolveServerIpSync(ServerProfile? profile) {
    if (profile == null) return null;
    final host = (profile.serverAddress ?? '').trim();
    if (host.isNotEmpty && InternetAddress.tryParse(host) != null) {
      return host;
    }
    final extraIp = profile.extraParams['ip']?.toString().trim();
    if (extraIp != null && InternetAddress.tryParse(extraIp) != null) {
      return extraIp;
    }
    final fromName = extractIp(profile.displayName);
    if (fromName != null) {
      return fromName;
    }
    if (host.isNotEmpty) {
      final cached = _resolvedHosts[host];
      if (cached != null) return cached;
    }
    return null;
  }

  /// Resolves [host] once and caches the numeric address for a short period.
  /// Reusing the resolved IP keeps subsequent measurements focused on the TCP
  /// round-trip instead of paying repeated DNS lookup cost.
  Future<String?> _resolveHost(String host) async {
    if (InternetAddress.tryParse(host) != null) {
      return host;
    }
    final now = DateTime.now();
    final cached = _resolvedHosts[host];
    final expiry = _dnsExpiry[host];
    if (cached != null && expiry != null && expiry.isAfter(now)) {
      return cached;
    }
    final pending = _dnsInFlight[host];
    if (pending != null) {
      return pending;
    }
    final future = () async {
      try {
        var addresses = await InternetAddress.lookup(
          host,
          type: InternetAddressType.IPv4,
        );
        if (addresses.isEmpty) {
          addresses = await InternetAddress.lookup(host);
        }
        if (addresses.isEmpty) return null;
        final address = addresses.first.address;
        if (_resolvedHosts.length > 512) {
          _resolvedHosts.clear();
          _dnsExpiry.clear();
        }
        _resolvedHosts[host] = address;
        _dnsExpiry[host] = DateTime.now().add(const Duration(minutes: 10));
        return address;
      } catch (_) {
        return null;
      } finally {
        _dnsInFlight.remove(host);
      }
    }();
    _dnsInFlight[host] = future;
    return future;
  }

  /// Measures pings for all connectable [profiles] one by one with a short
  /// pause between servers, so the UI can animate results sequentially instead
  /// of replacing all latencies at once.
  Future<Map<String, int>> measureAllPings(
    List<ServerProfile> profiles, {
    void Function(String profileId, int pingMs)? onSingleResult,
    int samplesPerProfile = 2,
    Duration interPingDelay = const Duration(milliseconds: 160),
  }) async {
    final results = <String, int>{};
    final connectable = _customProber != null
        ? profiles
        : profiles.where(isConnectableServer).toList();
    if (connectable.isEmpty) return results;

    final delay = _customProber != null ? Duration.zero : interPingDelay;
    for (var i = 0; i < connectable.length; i++) {
      final profile = connectable[i];
      final ms = await measurePingMs(profile, samples: samplesPerProfile);
      results[profile.id] = ms;
      onSingleResult?.call(profile.id, ms);
      if (i < connectable.length - 1) {
        await Future<void>.delayed(delay);
      }
    }

    return results;
  }

  /// Measures pings for connectable [profiles] in fast parallel batches, used by
  /// Smart Mode on initial connect and automatic failover.
  Future<Map<String, int>> measureBatchParallel(
    List<ServerProfile> profiles, {
    int concurrency = 8,
    int samplesPerProfile = 1,
    void Function(String profileId, int pingMs)? onSingleResult,
  }) async {
    final results = <String, int>{};
    final connectable = _customProber != null
        ? profiles
        : profiles.where(isConnectableServer).toList();
    if (connectable.isEmpty) return results;

    final batchSize = concurrency < 1 ? 1 : concurrency;
    for (var i = 0; i < connectable.length; i += batchSize) {
      final end = (i + batchSize < connectable.length)
          ? i + batchSize
          : connectable.length;
      final batch = connectable.sublist(i, end);
      await Future.wait(
        batch.map((profile) async {
          final ms = await measurePingMs(profile, samples: samplesPerProfile);
          results[profile.id] = ms;
          onSingleResult?.call(profile.id, ms);
        }),
      );
    }

    return results;
  }

  /// Selects the best connectable profile with the lowest positive latency (`ms > 0`).
  /// Falls back to the first connectable profile if no positive ping was recorded yet.
  ServerProfile? pickBestProfile(
    List<ServerProfile> profiles,
    Map<String, int> pingMap, {
    Set<String> excludeIds = const <String>{},
  }) {
    if (profiles.isEmpty) return null;

    final connectable = profiles
        .where((p) => !excludeIds.contains(p.id) && isConnectableServer(p))
        .toList();
    final fallbackAll =
        profiles.where((p) => !excludeIds.contains(p.id)).toList();
    final candidates = connectable.isNotEmpty
        ? connectable
        : (fallbackAll.isNotEmpty ? fallbackAll : profiles);

    ServerProfile? best;
    int? bestPing;

    for (final profile in candidates) {
      final ms = pingMap[profile.id];
      if (ms != null && ms > 0) {
        if (bestPing == null || ms < bestPing) {
          bestPing = ms;
          best = profile;
        }
      }
    }

    return best ?? candidates.first;
  }
}
