# Changelog

All notable changes to Speedll Connect will be documented here.

## [1.9.0] - 2026-11-13

- **Opt-In IPv6 Support (Disabled by Default):**
  - Added **IPv6 Support / پشتیبانی از IPv6** switch in Settings (defaults to `false`).
  - Added `enableIpv6` field to `SingboxRoutingOptions` and persistent `SecureProfileStorage`. When disabled, enforces `dns.strategy = ipv4_only` and strict IPv4 DNS resolution in `PingService` (never silently falling back to IPv6). When enabled, switches core DNS strategy to `prefer_ipv6` and prioritizes AAAA resolution with automatic IPv4 fallback.
  - Updated Android `LocalResolver.kt` to filter `Inet4Address`/`Inet6Address` accurately based on sing-box query `network` (`ip4`/`ip6`), strip interface scope IDs (`%iface`), and return DNS `NOERROR` (0) instead of `NXDOMAIN` (3) when a domain resolves only under the opposite IP family.
  - Updated `SafeProxyUri.parse` and `SingboxConverter` to preserve bracketed `[ipv6]` literals in proxy URIs while normalizing unbracketed IPv6 addresses across outbound `server`, WireGuard `peers`, and TLS `server_name`.
  - Updated Home Screen IP pill and Server Selector rows with `Directionality(textDirection: TextDirection.ltr)` and responsive flex layout to render long IPv6 addresses cleanly without truncation artifacts or RTL reversal, plus Cloudflare/Google IPv6 DNS presets in Settings.
- **Subscription Name Detection & Base64 Decoding (Hiddify-style):**
  - Added unified `SubscriptionSource.sanitizeSubscriberName` and `formatSubscriptionTitle` helpers to decode `base64:`-prefixed titles (`profile-title` HTTP headers, `#profile-title:` inside raw or Base64-encoded subscription bodies, `Content-Disposition: filename*=UTF-8''...`, URL fragments, and query parameters).
  - Automatically heals previously persisted `base64:` / `اشتراک base64:...` subscription titles during `SubscriptionSource.fromJson` deserialization and manual/background refreshes (`ConnectionController`, `ImportSubscriptionDialog`, `SelectServerDialog`).

## [1.8.0] - 2026-11-12

- **Migration to Native Libbox TUN (sing-box v1.14.4):** Completely decommissioned legacy `SpeedllVpnService`, `Tun2SocksBridge`, and standalone `libsingbox.so` binaries in `jniLibs`, cutting APK size by >150MB and eliminating userspace packet bridging battery drain.
- **APK Compression & Size Reduction:**
  - Enabled legacy packaging (`packaging.jniLibs.useLegacyPackaging = true`) in Gradle to compress (deflate) `libbox.so` inside the APK, shrinking the release APK from ~94MB down to ~34MB on `arm64-v8a` (~62% reduction) and ~85MB to ~34MB on `armeabi-v7a` (~58% reduction).
  - Provided reproducible minimal libbox build script at `scripts/build_libbox_minimal.sh`.
- **Platform Branding & Custom Icons:**
  - Added complete brand identity icons across all platforms (Android adaptive anydpi-v26, monochrome themed icon, roundIcon, legacy mipmaps; iOS AppIcon without alpha channel; macOS AppIcon and ICNS; Windows multi-resolution ICO 16-256px; Linux PNG icons and .desktop launcher).
  - Replaced system warning icon with custom monochrome vector notification icon (`ic_stat_speedll`) in `LibboxVpnService`.
  - Added master `app/assets/branding/app_icon.png` (1024x1024) for in-app About and branding displays.
- **Network & Battery Optimizations:**
  - Removed `setMetered(false)` in `openTun` to correctly inherit metered network status from the underlying active connection.
  - Added IPv6 ULA address (`fdfe:dcba:9876::1/126`) alongside IPv4 (`172.19.0.1/30`) to the native TUN inbound to prevent IPv6 traffic leakage.
  - Standardized `buildAndroidLibboxConfig` API with typed `List<String> tunAddresses`.
  - Set default TUN MTU to 9000 (matching SFA recommendations).
  - Removed redundant root-only `auto_redirect` from TUN configuration and service override options.
  - Streamlined smux multiplexing parameters with `padding: false` and removed `min_streams`.
- **Health Checks & Stability:**
  - Increased `_smartHealthTimer` interval from 10s to 60s (`_smartHealthInterval`) with optional constructor injection.
  - Reduced sample count for background Smart health checks from 3 to 1 while preserving 3-sample latency probing for UI interactions.
  - Prevented Activity leaks in `MainActivity` by nulling out `LibboxVpnService.statusCallback` on destroy.
- **Release Hardening:**
  - Enabled R8 minification (`minifyEnabled true`), resource shrinking (`shrinkResources true`), and ProGuard keep rules for libbox, Go runtime, app, and ZXing.
  - Added ABI filters to target only `arm64-v8a` and `armeabi-v7a`.
  - Guarded debug crash triggers and verbose logging strictly behind `BuildConfig.DEBUG`.
- **Version Harmonization:** Consolidated versioning to 1.8.0 (Build 14).

## [1.7.1] - 2026-11-12

- Fixed Sing-box `ERR-CORE-CONFIG` unknown field bug by removing obsolete `sniff` fields from inbound options (sing-box v1.14 handles traffic sniffing strictly via `route.rules`).
- Enhanced subscriber name extractor to recognize emoji-tagged Hiddify/Sellbot status nodes (`📊 🖥 pc | ⏳ ...` -> `pc`), and added base64 decoding support (e.g. `base64:bW9qd...` -> `mojtaba`).
- Added smart fallback subscriber name generator with short UUIDs (`کاربر ویژه (170e)`) for links and configs without explicit names, preventing raw domain names or placeholder keys.
- Added live destination server IP badge (IPv4 / IPv6) directly beside the country name on the Home screen's ping/status card.
- Version bumped to 1.7.1 (Build 13).

## [1.7.0] - 2026-11-11

- Redesigned and categorized Settings panel into 5 modern grouped cards: Appearance & Language, Connection & Servers, Routing & Tunneling, Network, Core & Stability, and About & Diagnostics with soft icon badges and navigation chevrons.
- Removed subscription and profile manager completely from the Settings screen; profiles are now managed exclusively in the dedicated Profiles tab.
- Constrained the top-bar `+` button strictly to the Home screen tab.
- Fixed Sing-box core crash when Multiplexing (MUX) is active on VLESS XTLS-Vision connections by ensuring MUX is selectively applied only to compatible transports.
- Activated native Sing-box smart traffic sniffing (`sniff: true`) in inbound routing.
- Enhanced Kill Switch with hardware blocking (`setBlocking(true)`) in the Android VPN service and added a direct shortcut to Android's native Always-on VPN settings.
- Version bumped to 1.7.0 (Build 12).

## [1.6.0] - 2026-11-11

- Updated official application icon to modern 3D beveled SC neon monogram with electric cyan, emerald-mint, and royal purple glow on midnight obsidian squircle tile.
- Redesigned Home subscription usage card: added circular profile refresh button, subscriber user name extraction (replacing raw domain links), percentage ring gauge, and clear volume metrics.
- Replaced AppBar top action button with `+` icon for quick profile import and camera QR code scanning.
- Cleaned up Home Screen: removed redundant profile selector card, bottom add button, and footer text for a minimal and focused interface.
- Version bumped to 1.6.0 (Build 11).

## [1.5.0] - 2026-11-11

- Completed protocol and transport support for `sing-box v1.14.4`: added full WireGuard support (`wireguard://`, `wg://`, `.conf`, Clash YAML, sing-box JSON, and v1.14 top-level `endpoints` config generation), Trojan Reality (`security=reality`), VMess URI format (`vmess://uuid@host:port?...`), QUIC transport, Shadowsocks SIP003 plugin & UDP-over-TCP, and Hysteria2 port-hopping (`mport`) & bandwidth parameters.
- Added Multi-Subscription separation in `ProfilesBrowserPanel` (`SelectServerDialog`) with horizontal filter tabs per subscription (`All`, each named subscription, and `Manual`), custom subscription naming on import (`ImportSubscriptionDialog`), and subscription badges on each server card and on the Home screen.
- Restructured the Home screen layout (`HomeScreen`): moved the compact `SubscriptionUsageCard` to the top of the Home screen, placed the compact status badge + timer + live ping card below the Connect button, and made tapping Connect on first launch (when no profiles exist) open `ImportSubscriptionDialog` (with QR Code scanner and link input).
- Implemented Smart Mode Connection Lock & Health-Check Auto-Failover (`ConnectionController`): probes candidates in fast parallel batches on connect, locks onto the chosen server while healthy so manual/background refreshes do not cause reconnects, and automatically fails over to the next best working server only after consecutive health/latency failures.
- Redesigned `ConnectionButton` with a theme-adaptive celestial corona (`_CelestialCoronaPainter`) emitting solar golden-yellow sunbeams, soft sky-blue lunar arcs, and twinkling 4-point stars when connected.
- Hardened Android tunnel and DNS stability (`Tun2SocksBridge.kt` & `SpeedllVpnService.kt`): cleared post-handshake TCP read timeout (`socket.soTimeout = 0`, `keepAlive = true`) to prevent 2-minute idle stream drops, added in-memory DNS response caching (45s TTL) + 2-attempt UDP retry, and prevented IPv6 blackhole stalls when Kill Switch is off.
- Version bumped to 1.5.0 (Build 10).

## [1.4.0] - 2026-11-10

- Added region detection and manual region selection for Iran, China, Russia, and Global; auto-detection uses device locale/timezone and persists the resolved region.
- Added domestic direct-routing data for China (about 1,789 domains, 7,552 IPv4/IPv6 CIDRs) and Russia (about 101 domains, 10,842 IPv4/IPv6 CIDRs), with region-aware DNS bypass rules. Generated configs validate with sing-box 1.14.4.
- Subscription status rows (`.invalid` hosts, `status.*` hosts, or names containing usage/expiry metadata) are now filtered out of imports, stored profiles, ping/selection lists, and credential handling; their usage is parsed before hiding.
- Added `subscription-userinfo` header and response-body comment parsing plus Persian/English name fallback for used/total traffic and expiry, persisted per subscription.
- Added a modern home-screen subscription card with animated traffic ring, used/remaining volume, expiry date, and remaining-day badge.
- Release hardening: non-backup manifest, non-debuggable release defaults, APK Signature Scheme v2+v3, release signing fail-fast retained.
- Version bumped to 1.4.0 (Build 9).

## [1.3.0] - 2026-11-10

- Domestic bypass now routes all `.ir`/Iranian IDN domains and the complete Iranian IPv4/IPv6 allocation directly, plus 650+ curated domestic domains (banks, payment gateways, and local services), fixing bank and local-site access while the VPN is on.
- Direct DNS defaults to a domestic resolver (Shecan) instead of blocked Google DNS, with Radar/403 presets and a manual DNS editor for both remote and direct resolvers.
- Ping measurement now reuses cached DNS results and takes the fastest of parallel handshakes, and "test all" measures servers sequentially with a visible medium-paced progression instead of updating every server at once.
- Battery review: no wake locks or busy loops, UI duration timer stays stopped in the background, and active-profile ping is measured only on connect.
- Release APK now uses a dedicated release keystore instead of the Android debug certificate to reduce Play Protect warnings.
- Version bumped to 1.3.0 (Build 8).

## [1.2.0] - 2026-11-10

- Added real Mux support, `.ir`-only bypass fix, and converters/parsers for TUIC, AnyTLS, Hysteria, Clash YAML, and sing-box JSON subscriptions.
- Removed the periodic 6-second ping loop and made the connection timer lifecycle-aware to reduce battery usage.
- Added optional Kill Switch (default off) with native fail-closed handling, IPv6 blocking, notification permission request, and Android 14 foreground-service subtype metadata.
- Isolated subscriptions on refresh, pruned deleted profiles, replacement of a removed active profile, stable subscription IDs, and improved dark-mode server cards.
- Fixed disconnect-button double taps, custom rules validation, and release signing configuration (`key.properties` + fail-fast guard).
- Windows: real DPAPI vault encryption, dynamic local port, system-proxy snapshot/restore, TUN admin diagnostics, IPv6 TUN address, and crash detection.
- Windows host (Go): pinned sing-box checksum, SSRF-safe subscription download, crash monitor, dynamic port, `.ir` fix, and proxy restore.
- CI: package tests, Windows checksum verification, full payload bundling, and Go host vet/cross-build.

## [1.0.0] - 2026-11-10

- Redesigned app UI with Royal Purple & Neon Violet theme matching reference design (3-ring glowing power button, large digital timer, glowing status pill badge, and floating bottom navigation bar with Home, Profiles, Statistics, and Settings tabs).
- Added real TCP latency measurement (`PingService` in `ms`), live ping & country flag badge below the Connect button (`CountryFlagResolver`, `CountryFlagAvatar`, `SignalBarsIndicator`), and Smart Mode (`حالت هوشمند`) auto-selecting the lowest-ping server.
- Renamed server selector to "پروفایل‌ها / Profiles" (`ProfilesBrowserPanel` & `SelectServerDialog`) showing all subscription/imported configs with search, `Ping All`, signal bars (`|||`), country flags, and seamless live hot-switching of active configs while connected (`SpeedllVpnService` + `ConnectionController`).
- Added bilingual support (`فارسی` RTL and `English` LTR via `AppStrings` & `LocaleController`) with device locale auto-detection, first-launch `LanguageOnboardingDialog`, and instant language switching in `SettingsPanel`.
- Added comprehensive `SettingsPanel` (Language, Theme, Smart Mode, `.ir` & LAN Split-Tunneling Routing switches, Subscription management, and App Version `1.0.0 (Build 5)`).
- Fixed Android VPN 0-byte data transfer issue by implementing native `Tun2SocksBridge` (user-space IPv4 TCP/UDP/DNS packet translator bridging `VpnService` TUN descriptor to `sing-box` local `mixed` SOCKS5 port `2080` and `direct` UDP DNS port `2053`), adding `VpnService.Builder.addDisallowedApplication(packageName)` to prevent outbound routing loops, and updating `SingboxConverter` to `sing-box v1.14.4` schema (`sniff` and `hijack-dns` route actions, `default_domain_resolver`, typed `tcp`/`udp` DNS servers, and WebSocket `?ed=` early data + HTTP transport support).
- Enforced real core readiness verification in `SpeedllVpnService` (`launchAndVerifySingboxCore`) so `"connected"` is only emitted after `libsingbox.so` stays alive and opens `127.0.0.1:2080`.
- Added Wi-Fi / Mobile network handoff monitoring (`ConnectivityManager.NetworkCallback`) and controlled core recovery (`reconnecting` -> `connected`) in `SpeedllVpnService`.
- Added `DiagnosticErrorMapper` to translate native and engine errors into user-friendly Persian messages and diagnostic codes (`ERR-CORE-CONFIG`, `ERR-CORE-START`, `ERR-NET-SWITCH`, `ERR-VPN-PERMISSION`, etc.) while redacting all UUIDs, passwords, tokens, URIs, and IP addresses.
- Replaced in-memory profile storage with `flutter_secure_storage` and native `AndroidKeystoreSecureStorage` (AES-256-GCM hardware-backed key encryption in Android Keystore), isolating sensitive profile secrets (`uuid`, `password`, `auth`, `pbk`, `obfsPassword`, `sid`) from profile metadata.
- Added foundational `sing-box` routing and DNS rules in `SingboxConverter` (`SingboxRoutingOptions`) to bypass private/LAN IP ranges and domestic `.ir` domains without DNS leaks.
- Added native camera QR Code scanner (`QrScannerActivity` + `QrScannerService` backed by Android Camera2 and `zxing-core`) integrated into `ImportSubscriptionDialog`.
- Implemented `SubscriptionUpdater` with periodic background refresh, SSRF protection (blocking HTTP, loopback, link-local, metadata, and private IP ranges including via redirects), 2MB response cap, HTML/corrupt response rejection, URL token redaction, and graceful offline preservation of existing profiles.
- Integrated profile deletion (with automatic secret cleanup) and manual/periodic subscription refresh into `ConnectionController` and UI.
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
- Added sanitized test fixtures for Germany (VLESS Reality), Turkey (VMess), Sanaei France (Trojan), and X-Net (Hysteria2).
- Added comprehensive unit, negative, and edge-case test suites (14 automated tests passing).

## [0.1.0-prealpha] - 2026-11-09

- Created initial repository structure and Persian project documentation.
- Added phased roadmap, architecture, engine evaluation, security and test plans.
- Added initial Flutter UI preview with light/dark/system themes.
- Added domain model and connection engine interface placeholders.
- No real VPN engine or native tunnel is included in this release.
