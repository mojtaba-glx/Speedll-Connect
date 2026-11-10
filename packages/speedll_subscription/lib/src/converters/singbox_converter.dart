import '../models/server_profile.dart';

class SingboxConvertException implements Exception {
  const SingboxConvertException(this.message);
  final String message;
  @override
  String toString() => 'SingboxConvertException: $message';
}

/// Converts normalized ServerProfile into deterministic sing-box outbound JSON structures.
class SingboxConverter {
  const SingboxConverter();

  Map<String, dynamic> buildOutbound(ServerProfile profile) {
    final protocol = profile.protocol.toLowerCase();
    switch (protocol) {
      case 'vless':
        return _buildVless(profile);
      case 'vmess':
        return _buildVmess(profile);
      case 'trojan':
        return _buildTrojan(profile);
      case 'shadowsocks':
        return _buildShadowsocks(profile);
      case 'hysteria2':
        return _buildHysteria2(profile);
      default:
        throw SingboxConvertException('پروتکل $protocol توسط مبدل sing-box پشتیبانی نمی‌شود.');
    }
  }

  Map<String, dynamic> _buildVless(ServerProfile profile) {
    final extra = profile.extraParams;
    final security = (extra['security'] as String? ?? 'none').toLowerCase();
    final transportType = (extra['transportType'] as String? ?? 'tcp').toLowerCase();

    final outbound = <String, dynamic>{
      'type': 'vless',
      'tag': 'proxy',
      'server': profile.serverAddress,
      'server_port': profile.serverPort ?? 443,
      'uuid': extra['uuid'] ?? '',
    };

    if (extra['flow'] != null && (extra['flow'] as String).isNotEmpty) {
      outbound['flow'] = extra['flow'];
    }

    // TLS or Reality
    if (security == 'reality') {
      outbound['tls'] = <String, dynamic>{
        'enabled': true,
        'server_name': extra['sni'] ?? profile.serverAddress,
        'utls': <String, dynamic>{
          'enabled': true,
          'fingerprint': extra['fingerprint'] ?? 'chrome',
        },
        'reality': <String, dynamic>{
          'enabled': true,
          'public_key': extra['pbk'] ?? '',
          if (extra['sid'] != null) 'short_id': extra['sid'],
        },
      };
    } else if (security == 'tls') {
      outbound['tls'] = <String, dynamic>{
        'enabled': true,
        if (extra['sni'] != null) 'server_name': extra['sni'],
        'utls': <String, dynamic>{
          'enabled': true,
          'fingerprint': extra['fingerprint'] ?? 'chrome',
        },
      };
    }

    // Transport (ws / grpc / tcp)
    if (transportType == 'ws') {
      outbound['transport'] = <String, dynamic>{
        'type': 'ws',
        if (extra['path'] != null) 'path': extra['path'],
        if (extra['host'] != null) 'headers': {'Host': extra['host']},
      };
    } else if (transportType == 'grpc') {
      outbound['transport'] = <String, dynamic>{
        'type': 'grpc',
        if (extra['serviceName'] != null) 'service_name': extra['serviceName'],
      };
    }

    return outbound;
  }

  Map<String, dynamic> _buildVmess(ServerProfile profile) {
    final extra = profile.extraParams;
    final transportType = (extra['transportType'] as String? ?? 'tcp').toLowerCase();
    final isTls = extra['tls'] == 'tls';

    final outbound = <String, dynamic>{
      'type': 'vmess',
      'tag': 'proxy',
      'server': profile.serverAddress,
      'server_port': profile.serverPort ?? 443,
      'uuid': extra['uuid'] ?? '',
      'security': extra['security'] ?? 'auto',
      'alter_id': extra['alterId'] ?? 0,
    };

    if (isTls) {
      outbound['tls'] = <String, dynamic>{
        'enabled': true,
        if (extra['sni'] != null) 'server_name': extra['sni'],
      };
    }

    if (transportType == 'ws') {
      outbound['transport'] = <String, dynamic>{
        'type': 'ws',
        if (extra['path'] != null) 'path': extra['path'],
        if (extra['host'] != null) 'headers': {'Host': extra['host']},
      };
    }

    return outbound;
  }

  Map<String, dynamic> _buildTrojan(ServerProfile profile) {
    final extra = profile.extraParams;
    final outbound = <String, dynamic>{
      'type': 'trojan',
      'tag': 'proxy',
      'server': profile.serverAddress,
      'server_port': profile.serverPort ?? 443,
      'password': extra['password'] ?? '',
      'tls': <String, dynamic>{
        'enabled': true,
        if (extra['sni'] != null) 'server_name': extra['sni'],
      },
    };

    final transportType = (extra['transportType'] as String? ?? 'tcp').toLowerCase();
    if (transportType == 'grpc') {
      outbound['transport'] = <String, dynamic>{
        'type': 'grpc',
        if (extra['serviceName'] != null) 'service_name': extra['serviceName'],
      };
    }

    return outbound;
  }

  Map<String, dynamic> _buildShadowsocks(ServerProfile profile) {
    final extra = profile.extraParams;
    return <String, dynamic>{
      'type': 'shadowsocks',
      'tag': 'proxy',
      'server': profile.serverAddress,
      'server_port': profile.serverPort ?? 8388,
      'method': extra['method'] ?? 'aes-256-gcm',
      'password': extra['password'] ?? '',
    };
  }

  Map<String, dynamic> _buildHysteria2(ServerProfile profile) {
    final extra = profile.extraParams;
    final outbound = <String, dynamic>{
      'type': 'hysteria2',
      'tag': 'proxy',
      'server': profile.serverAddress,
      'server_port': profile.serverPort ?? 443,
      if (extra['auth'] != null) 'password': extra['auth'],
      'tls': <String, dynamic>{
        'enabled': true,
        if (extra['sni'] != null) 'server_name': extra['sni'],
        'insecure': extra['insecure'] == true,
      },
    };

    if (extra['obfs'] != null) {
      outbound['obfs'] = <String, dynamic>{
        'type': extra['obfs'],
        if (extra['obfsPassword'] != null) 'password': extra['obfsPassword'],
      };
    }

    return outbound;
  }
}
