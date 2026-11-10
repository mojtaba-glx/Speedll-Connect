# Changelog

All notable changes to Speedll Connect will be documented here.

## [Unreleased] - 2026-11-10

- Implemented dedicated parsers for VLESS Reality, VMess, Trojan, Shadowsocks, and Hysteria2.
- Added `SubscriptionDetector` supporting multiline, comments, and Base64 subscription payloads with 2MB DoS protection cap.
- Implemented `SingboxConverter` to generate valid sing-box outbound configurations from normalized `ServerProfile`.
- Added sanitized test fixtures for Hiddify Germany (VLESS Reality), Hiddify Turkey (VMess), Sanaei France (Trojan), and X-Net (Hysteria2).
- Added comprehensive unit, negative, and edge-case test suites (13 automated tests passing).
- Extracted subscription pipeline into standalone Pure Dart package (`packages/speedll_subscription`).
- Added `ServerProfile` with `schemaVersion`, serialization and `ProfileMigrator` architecture.
- Integrated Riverpod (`flutter_riverpod`) for reactive state management across Presentation and Application layers.
- Modularized Flutter presentation widgets (`HomeScreen`, `ConnectionButton`, `ServerInfoCard`, `UsageCard`).
- Accepted ADR 0002 for single-engine MVP strategy (focusing on `sing-box` and deferring `Xray`).
- Resolved platform duality between root `platform/` specs and native Flutter platform host directories.

## [0.1.0-prealpha] - 2026-11-09

- Created initial repository structure and Persian project documentation.
- Added phased roadmap, architecture, engine evaluation, security and test plans.
- Added initial Flutter UI preview with light/dark/system themes.
- Added domain model and connection engine interface placeholders.
- No real VPN engine or native tunnel is included in this release.
