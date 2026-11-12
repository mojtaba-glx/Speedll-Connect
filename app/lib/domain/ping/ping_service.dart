import 'dart:async';
import 'dart:io';
import 'package:speedll_subscription/speedll_subscription.dart';

/// Measures real TCP handshake latency (ping in milliseconds) for VPN server profiles
/// and selects the optimal lowest-latency server in Smart Mode.
class PingService {
  const PingService({
    this.timeout = const Duration(milliseconds: 1400),
    Future<int> Function(ServerProfile profile)? customProber,
    Future<List<InternetAddress>> Function(String host, InternetAddressType type)?
        customDnsLookup,
  })  : _customProber = customProber,
        _customDnsLookup = customDnsLookup;

  final Duration timeout;
  final Future<int> Function(ServerProfile profile)? _customProber;
  final Future<List<InternetAddress>> Function(
    String host,
    InternetAddressType type,
  )? _customDnsLookup;

  static final Map<String, String> _resolvedHosts = <String, String>{};
  static final Map<String, DateTime> _dnsExpiry = <String, DateTime>{};
  static final Map<String, Future<List<String>>> _dnsInFlight =
      <String, Future<List<String>>>{};

  static String _cacheKey(String host, {required bool preferIpv6}) =>
      '${preferIpv6 ? 'v6' : 'v4'}:$host';

  /// Parses [raw] as a numeric IPv4 or IPv6 literal (stripping optional `[...]` brackets).
  static String? _parseLiteralIp(String? raw) {
    if (raw == null) return null;
    final normalized = SafeProxyUri.normalizeHost(raw);
    if (normalized.isEmpty) return null;
    if (InternetAddress.tryParse(normalized) != null) {
      return normalized;
    }
    return null;
  }

  /// Clears cached DNS lookups (e.g. when toggling IPv6 preference or network changes).
  static void clearDnsCache() {
    _resolvedHosts.clear();
    _dnsExpiry.clear();
  }

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
    bool preferIpv6 = false,
  }) async {
    if (_customProber != null) {
      return _customProber(profile);
    }

    if (!isConnectableServer(profile)) {
      return -1;
    }

    final rawHost = profile.serverAddress?.trim() ?? '';
    final host = SafeProxyUri.normalizeHost(rawHost);
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
      return _probeOnce(
        host,
        port,
        acceptRstForUdp: isUdpBased,
        preferIpv6: preferIpv6,
      );
    }

    final results = await Future.wait(
      List<Future<int>>.generate(
        attempts,
        (_) => _probeOnce(
          host,
          port,
          acceptRstForUdp: isUdpBased,
          preferIpv6: preferIpv6,
        ),
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
    bool preferIpv6 = false,
  }) async {
    final candidates = await _resolveHostCandidates(
      host,
      preferIpv6: preferIpv6,
    );
    final targets = candidates.isNotEmpty ? candidates : <String>[host];
    final key = _cacheKey(host, preferIpv6: preferIpv6);
    final isLiteral = _parseLiteralIp(host) != null;

    for (final target in targets) {
      final stopwatch = Stopwatch()..start();
      Socket? socket;
      try {
        socket = await Socket.connect(
          target,
          port,
          timeout: timeout,
        );
        stopwatch.stop();
        if (!isLiteral && _parseLiteralIp(target) != null) {
          _cacheResolvedIp(key, target);
        }
        final elapsed = stopwatch.elapsedMilliseconds;
        return elapsed > 0 ? elapsed : 1;
      } on SocketException catch (e) {
        stopwatch.stop();
        if (acceptRstForUdp) {
          final msg = e.message.toLowerCase();
          final code = e.osError?.errorCode;
          if (code == 111 || msg.contains('connection refused')) {
            if (!isLiteral && _parseLiteralIp(target) != null) {
              _cacheResolvedIp(key, target);
            }
            final elapsed = stopwatch.elapsedMilliseconds;
            if (elapsed > 0 && elapsed < timeout.inMilliseconds) {
              return elapsed;
            }
          }
        }
      } catch (_) {
        stopwatch.stop();
      } finally {
        try {
          socket?.destroy();
        } catch (_) {}
      }
    }
    return -1;
  }

  /// Returns the cached IP address for [host] if previously resolved.
  static String? getCachedIp(String host, {bool preferIpv6 = false}) {
    final literal = _parseLiteralIp(host);
    if (literal != null) return literal;
    final norm = SafeProxyUri.normalizeHost(host);
    return _resolvedHosts[_cacheKey(norm, preferIpv6: preferIpv6)];
  }

  /// Extracts IPv4 or IPv6 address from raw text or remark string.
  static String? extractIp(String? text, {bool preferIpv6 = false}) {
    if (text == null || text.trim().isEmpty) return null;

    String? findIpv4() {
      final v4 = RegExp(
        r'\b(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b',
      ).firstMatch(text);
      if (v4 != null) {
        final ip = v4.group(0)!;
        if (!ip.startsWith('127.') && ip != '0.0.0.0') return ip;
      }
      return null;
    }

    String? findIpv6() {
      final bracketedOrToken = RegExp(
        r'\[([0-9a-fA-F:]+)\]|\b([0-9a-fA-F]{0,4}(?::[0-9a-fA-F]{0,4}){2,7})\b',
      );
      for (final match in bracketedOrToken.allMatches(text)) {
        final candidate = (match.group(1) ?? match.group(2) ?? '').trim();
        if (candidate.isEmpty ||
            candidate == '::' ||
            candidate == '::1' ||
            !candidate.contains(':')) {
          continue;
        }
        final parsed = InternetAddress.tryParse(candidate);
        if (parsed != null && parsed.type == InternetAddressType.IPv6) {
          return parsed.address;
        }
      }
      return null;
    }

    if (preferIpv6) {
      return findIpv6() ?? findIpv4();
    }
    return findIpv4() ?? findIpv6();
  }

  /// Resolves the destination server IP (IPv4 or IPv6) synchronously from literal server host,
  /// cached DNS resolution for [preferIpv6], profile metadata, or remark IP.
  static String? resolveServerIpSync(
    ServerProfile? profile, {
    bool preferIpv6 = false,
  }) {
    if (profile == null) return null;
    final rawHost = (profile.serverAddress ?? '').trim();
    final literalHost = _parseLiteralIp(rawHost);
    if (literalHost != null) {
      return literalHost;
    }
    final normHost = SafeProxyUri.normalizeHost(rawHost);
    if (normHost.isNotEmpty) {
      final cached =
          _resolvedHosts[_cacheKey(normHost, preferIpv6: preferIpv6)];
      if (cached != null) return cached;
    }
    final extraIp = _parseLiteralIp(profile.extraParams['ip']?.toString());
    if (extraIp != null) {
      return extraIp;
    }
    return extractIp(profile.displayName, preferIpv6: preferIpv6);
  }

  static void _cacheResolvedIp(String cacheKey, String address) {
    if (_resolvedHosts.length > 512) {
      _resolvedHosts.clear();
      _dnsExpiry.clear();
    }
    _resolvedHosts[cacheKey] = address;
    _dnsExpiry[cacheKey] = DateTime.now().add(const Duration(minutes: 10));
  }

  Future<List<InternetAddress>> _lookupFamily(
    String host,
    InternetAddressType type,
  ) async {
    try {
      if (_customDnsLookup != null) {
        return await _customDnsLookup(host, type);
      }
      return await InternetAddress.lookup(host, type: type);
    } on SocketException {
      return const <InternetAddress>[];
    } catch (_) {
      return const <InternetAddress>[];
    }
  }

  /// Resolves [host] to candidate IP addresses according to [preferIpv6].
  Future<List<String>> resolveTargetCandidates(
    String host, {
    bool preferIpv6 = false,
  }) {
    return _resolveHostCandidates(host, preferIpv6: preferIpv6);
  }

  /// Resolves [host] once and caches the winning numeric address for the
  /// selected IP family preference ([preferIpv6]).
  Future<List<String>> _resolveHostCandidates(
    String host, {
    required bool preferIpv6,
  }) async {
    final norm = SafeProxyUri.normalizeHost(host);
    final literal = _parseLiteralIp(norm);
    if (literal != null) {
      return <String>[literal];
    }
    final key = _cacheKey(norm, preferIpv6: preferIpv6);
    final now = DateTime.now();
    final cached = _resolvedHosts[key];
    final expiry = _dnsExpiry[key];
    if (cached != null && expiry != null && expiry.isAfter(now)) {
      return <String>[cached];
    }
    final pending = _dnsInFlight[key];
    if (pending != null) {
      return pending;
    }
    final future = () async {
      try {
        final candidates = <String>[];
        if (preferIpv6) {
          final results = await Future.wait(<Future<List<InternetAddress>>>[
            _lookupFamily(norm, InternetAddressType.IPv6),
            _lookupFamily(norm, InternetAddressType.IPv4),
          ]);
          for (final addr in results[0]) {
            if (!candidates.contains(addr.address)) {
              candidates.add(addr.address);
              break;
            }
          }
          for (final addr in results[1]) {
            if (!candidates.contains(addr.address)) {
              candidates.add(addr.address);
              break;
            }
          }
        } else {
          // Strict IPv4 mode when IPv6 support toggle is OFF: never auto-fallback to IPv6.
          final v4 = await _lookupFamily(norm, InternetAddressType.IPv4);
          if (v4.isNotEmpty) {
            candidates.add(v4.first.address);
          }
        }
        if (candidates.isNotEmpty) {
          _cacheResolvedIp(key, candidates.first);
        }
        return candidates;
      } catch (_) {
        return const <String>[];
      } finally {
        _dnsInFlight.remove(key);
      }
    }();
    _dnsInFlight[key] = future;
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
    bool preferIpv6 = false,
  }) async {
    final results = <String, int>{};
    final connectable = _customProber != null
        ? profiles
        : profiles.where(isConnectableServer).toList();
    if (connectable.isEmpty) return results;

    final delay = _customProber != null ? Duration.zero : interPingDelay;
    for (var i = 0; i < connectable.length; i++) {
      final profile = connectable[i];
      final ms = await measurePingMs(
        profile,
        samples: samplesPerProfile,
        preferIpv6: preferIpv6,
      );
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
    bool preferIpv6 = false,
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
          final ms = await measurePingMs(
            profile,
            samples: samplesPerProfile,
            preferIpv6: preferIpv6,
          );
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
