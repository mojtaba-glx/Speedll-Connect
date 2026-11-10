# Changelog

All notable changes to Speedll Connect will be documented here.

## [Unreleased] - 2026-11-10

- Integrated native Android `VpnService` with foreground service notification, permission flow, and lifecycle management.
- Embedded official `sing-box` core binaries (v1.14.4) for `arm64-v8a` and `armeabi-v7a` architectures in Android `jniLibs`.
- Implemented `AndroidVpnEngineAdapter` bridging Flutter UI and Android Native tunnel via MethodChannel and EventChannel.
- Implemented full in-app Subscription Import dialog supporting single links, multiline, and Base64 subscription formats.
- Implemented Server Selection dialog allowing user to browse and switch between added profiles.
- Live connection state and duration timer wired to UI with auto reconnect and error handling.
- Built working Android APK package containing real sing-box core and VpnService tunnel.
- Implemented dedicated parsers for VLESS Reality, VMess, Trojan, Shadowsocks, and Hysteria2.
- Added `SubscriptionDetector` supporting multiline, comments, and Base64 subscription payloads with 2MB DoS protection cap.
- Implemented `SingboxConverter` to generate valid sing-box outbound configurations from normalized `ServerProfile`.
- Added sanitized test fixtures for Hiddify Germany (VLESS Reality), Hiddify Turkey (VMess), Sanaei France (Trojan), and X-Net (Hysteria2).
- Added comprehensive unit, negative, and edge-case test suites (14 automated tests passing).

## [0.1.0-prealpha] - 2026-11-09

- Created initial repository structure and Persian project documentation.
- Added phased roadmap, architecture, engine evaluation, security and test plans.
- Added initial Flutter UI preview with light/dark/system themes.
- Added domain model and connection engine interface placeholders.
- No real VPN engine or native tunnel is included in this release.
