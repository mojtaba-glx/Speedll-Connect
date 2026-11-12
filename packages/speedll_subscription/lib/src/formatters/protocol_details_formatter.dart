import 'package:meta/meta.dart';

import '../models/server_profile.dart';

/// Structured technical description of a proxy profile's protocol model,
/// transport stack, security layer, and key tuning attributes.
@immutable
class ProtocolDetails {
  const ProtocolDetails({
    required this.protocolName,
    this.securityModel,
    this.transportModel,
    this.flowOrMode,
    this.fingerprint,
    this.alpn,
    this.cipherMethod,
    this.congestionControl,
    this.obfsModel,
    this.mtu,
  });

  final String protocolName;
  final String? securityModel;
  final String? transportModel;
  final String? flowOrMode;
  final String? fingerprint;
  final String? alpn;
  final String? cipherMethod;
  final String? congestionControl;
  final String? obfsModel;
  final int? mtu;

  /// Primary concise model signature, e.g. `VLESS · REALITY · Vision · TCP`.
  String get headlineModel {
    final parts = <String>[
      protocolName,
      if (securityModel != null) securityModel!,
      if (flowOrMode != null) flowOrMode!,
      if (cipherMethod != null) cipherMethod!,
      if (obfsModel != null) obfsModel!,
      if (congestionControl != null) congestionControl!,
      if (transportModel != null) transportModel!,
    ];
    return parts.join(' · ');
  }

  /// Secondary technical tokens (e.g., uTLS fingerprint, ALPN, MTU).
  List<String> get secondarySpecs => <String>[
        if (fingerprint != null) 'uTLS: $fingerprint',
        if (alpn != null) 'ALPN: $alpn',
        if (mtu != null) 'MTU: $mtu',
      ];
}

/// Extracts complete protocol model metadata from [ServerProfile].
class ProtocolDetailsFormatter {
  const ProtocolDetailsFormatter._();

  static ProtocolDetails inspect(ServerProfile profile) {
    final protocol = profile.protocol.trim().toLowerCase();
    final extra = profile.extraParams;

    switch (protocol) {
      case 'vless':
        return _inspectXrayStyle(
          protocolName: 'VLESS',
          extra: extra,
          defaultSecurity: _str(extra['pbk']) != null ? 'reality' : 'none',
        );
      case 'vmess':
        return _inspectVmess(extra);
      case 'trojan':
        return _inspectXrayStyle(
          protocolName: 'Trojan',
          extra: extra,
          defaultSecurity: _str(extra['pbk']) != null ? 'reality' : 'tls',
        );
      case 'shadowsocks':
      case 'ss':
        final method = _str(extra['method']) ?? 'aes-256-gcm';
        final is2022 = method.toLowerCase().startsWith('2022-');
        final hasPlugin = _str(extra['plugin']) != null;
        return ProtocolDetails(
          protocolName: 'Shadowsocks',
          securityModel: is2022 ? 'AEAD-2022' : 'AEAD',
          cipherMethod: method,
          flowOrMode: _isTrue(extra['udpOverTcp']) ? 'UoT' : null,
          obfsModel: hasPlugin ? _str(extra['plugin']) : null,
          transportModel: 'TCP/UDP',
        );
      case 'hysteria2':
      case 'hy2':
        final obfs = _str(extra['obfs']);
        return ProtocolDetails(
          protocolName: 'Hysteria2',
          securityModel: 'TLS',
          transportModel: 'QUIC',
          obfsModel: obfs != null && obfs.toLowerCase() != 'none'
              ? _capitalize(obfs)
              : null,
          alpn: _str(extra['alpn']) ?? 'h3',
        );
      case 'hysteria':
        final obfs = _str(extra['obfs']);
        return ProtocolDetails(
          protocolName: 'Hysteria',
          securityModel: 'TLS',
          transportModel: 'QUIC',
          obfsModel: obfs != null && obfs.toLowerCase() != 'none'
              ? _capitalize(obfs)
              : null,
          alpn: _str(extra['alpn']),
        );
      case 'tuic':
        return ProtocolDetails(
          protocolName: 'TUIC v5',
          securityModel: 'TLS',
          transportModel: 'QUIC',
          congestionControl:
              (_str(extra['congestionControl']) ?? 'bbr').toUpperCase(),
          flowOrMode: _isTrue(extra['zeroRttHandshake']) ? '0-RTT' : null,
          alpn: _str(extra['alpn']) ?? 'h3',
        );
      case 'anytls':
        return ProtocolDetails(
          protocolName: 'AnyTLS',
          securityModel: 'TLS',
          transportModel: 'TCP',
          fingerprint: _str(extra['fingerprint']) ?? _str(extra['fp']),
          alpn: _str(extra['alpn']),
        );
      case 'wireguard':
      case 'wg':
        final mtuVal = int.tryParse(_str(extra['mtu']) ?? '');
        return ProtocolDetails(
          protocolName: 'WireGuard',
          securityModel: 'Noise',
          transportModel: 'UDP',
          mtu: mtuVal,
        );
      default:
        return ProtocolDetails(
          protocolName: profile.protocol.trim().isEmpty
              ? 'Proxy'
              : profile.protocol.trim().toUpperCase(),
        );
    }
  }

  static ProtocolDetails _inspectXrayStyle({
    required String protocolName,
    required Map<String, dynamic> extra,
    required String defaultSecurity,
  }) {
    final securityRaw = (_str(extra['security']) ?? defaultSecurity).toLowerCase();
    final securityLabel = switch (securityRaw) {
      'reality' => 'REALITY',
      'tls' => 'TLS',
      'none' || '' => 'Plain',
      _ => securityRaw.toUpperCase(),
    };

    final flowRaw = _str(extra['flow']);
    final flowLabel = switch (flowRaw?.toLowerCase()) {
      'xtls-rprx-vision' => 'Vision',
      'xtls-rprx-vision-udp443' => 'Vision-UDP443',
      _ => flowRaw,
    };

    final rawTransport =
        (_str(extra['transportType']) ?? _str(extra['type']) ?? 'tcp')
            .toLowerCase();
    final headerType = _str(extra['headerType'])?.toLowerCase();
    final transportLabel = _formatTransport(rawTransport, headerType: headerType);
    final fp = (securityRaw == 'reality' || securityRaw == 'tls')
        ? (_str(extra['fingerprint']) ?? _str(extra['fp']))
        : null;

    return ProtocolDetails(
      protocolName: protocolName,
      securityModel: securityLabel,
      transportModel: transportLabel,
      flowOrMode: flowLabel,
      fingerprint: fp,
      alpn: _str(extra['alpn']),
    );
  }

  static ProtocolDetails _inspectVmess(Map<String, dynamic> extra) {
    final rawTls = _str(extra['tls'])?.toLowerCase();
    final rawSec = _str(extra['security'])?.toLowerCase();
    final isTls = rawTls == 'tls' || rawTls == '1' || rawTls == 'true';
    final cipher = _str(extra['scy']) ??
        ((rawSec != null && rawSec != 'tls' && rawSec != 'none') ? rawSec : 'auto');
    final rawTransport =
        (_str(extra['transportType']) ?? _str(extra['net']) ?? 'tcp')
            .toLowerCase();
    final headerType = _str(extra['headerType'])?.toLowerCase();

    return ProtocolDetails(
      protocolName: 'VMess',
      securityModel: isTls ? 'TLS' : 'AEAD',
      cipherMethod: cipher == 'auto' ? null : cipher,
      transportModel: _formatTransport(rawTransport, headerType: headerType),
      fingerprint:
          isTls ? (_str(extra['fingerprint']) ?? _str(extra['fp'])) : null,
      alpn: isTls ? _str(extra['alpn']) : null,
    );
  }

  static String _formatTransport(String raw, {String? headerType}) {
    switch (raw) {
      case 'ws':
      case 'websocket':
        return 'WebSocket';
      case 'grpc':
        return 'gRPC';
      case 'http':
      case 'h2':
        return 'HTTP/2';
      case 'httpupgrade':
        return 'HTTPUpgrade';
      case 'splithttp':
      case 'xhttp':
        return 'XHTTP';
      case 'quic':
        return 'QUIC';
      case 'tcp':
        if (headerType == 'http') return 'TCP (HTTP)';
        return 'TCP';
      default:
        return raw.toUpperCase();
    }
  }

  static String? _str(dynamic value) {
    if (value == null) return null;
    final trimmed = value.toString().trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static bool _isTrue(dynamic value) {
    if (value == true || value == 1) return true;
    final lower = value?.toString().trim().toLowerCase();
    return lower == 'true' || lower == '1';
  }

  static String _capitalize(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1);
  }
}
