import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speedll_subscription/speedll_subscription.dart';

import '../../../application/connection/connection_controller.dart';
import '../../../application/localization/app_strings.dart';
import '../../../application/localization/locale_controller.dart';
import '../../../application/theme/theme_controller.dart';
import '../../../domain/version/app_version.dart';

/// Modern iOS/Material 3 styled categorized Settings panel.
/// Grouped in clean rounded cards with icon badges, category labels,
/// and smooth dialog configuration for theme, language, region, and DNS.
class SettingsPanel extends ConsumerWidget {
  const SettingsPanel({super.key});

  String _regionLabel(AppStrings strings, RoutingRegion region) {
    return switch (region) {
      RoutingRegion.china => strings.regionChina,
      RoutingRegion.russia => strings.regionRussia,
      RoutingRegion.global => strings.regionGlobal,
      RoutingRegion.auto || RoutingRegion.iran => strings.regionIran,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final localeState = ref.watch(localeControllerProvider);
    final activePreset = ref.watch(themePresetProvider);
    final palette = ref.watch(themePaletteProvider);
    final connState = ref.watch(connectionControllerProvider);
    final routing = connState.routingOptions;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 104),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            strings.settingsHeader,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: palette.textPrimary,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 16),

          // Category 1: Appearance & Language (ظاهر و زبان)
          _CategoryLabel(label: strings.appearanceSectionTitle, palette: palette),
          _GroupCard(
            palette: palette,
            children: [
              _SettingsTile(
                icon: Icons.palette_rounded,
                iconColor: const Color(0xFF8B5CF6),
                iconBg: const Color(0xFF8B5CF6).withOpacity(0.14),
                title: strings.themeSettingTitle,
                subtitle: strings.themeSettingSubtitle,
                trailingValue: activePreset.label(strings.isFa),
                palette: palette,
                onTap: () => _showThemeDialog(context, ref, activePreset, palette, strings),
              ),
              _SettingsTile(
                icon: Icons.language_rounded,
                iconColor: const Color(0xFF3B82F6),
                iconBg: const Color(0xFF3B82F6).withOpacity(0.14),
                title: strings.languageSettingTitle,
                trailingValue: localeState.language == AppLanguage.fa
                    ? strings.languagePersian
                    : strings.languageEnglish,
                palette: palette,
                onTap: () => _showLanguageDialog(context, ref, localeState.language, palette, strings),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Category 2: Connection & Servers (اتصال و سرورها)
          _CategoryLabel(label: strings.connectionSectionTitle, palette: palette),
          _GroupCard(
            palette: palette,
            children: [
              _SettingsTile(
                icon: Icons.bolt_rounded,
                iconColor: const Color(0xFFF59E0B),
                iconBg: const Color(0xFFF59E0B).withOpacity(0.14),
                title: strings.enableSmartModeSetting,
                subtitle: strings.smartModeSubtitle,
                palette: palette,
                switchValue: connState.isSmartMode,
                onSwitchChanged: (val) {
                  ref.read(connectionControllerProvider.notifier).setSmartMode(val);
                },
              ),
              _SettingsTile(
                icon: Icons.speed_rounded,
                iconColor: const Color(0xFF10B981),
                iconBg: const Color(0xFF10B981).withOpacity(0.14),
                title: strings.testAllPings,
                subtitle: strings.isFa ? 'تست پینگ موازی تمامی سرورهای ذخیره‌شده' : 'Test latency of all servers',
                palette: palette,
                isLoading: connState.isPingingAll,
                onTap: connState.isPingingAll
                    ? null
                    : () async {
                        await ref.read(connectionControllerProvider.notifier).pingAllProfiles();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(strings.pingingAllCompletedToast),
                              backgroundColor: const Color(0xFF16A34A),
                            ),
                          );
                        }
                      },
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Category 3: Routing & Tunneling (مسیریابی و تونلینگ)
          _CategoryLabel(label: strings.routingSectionTitle, palette: palette),
          _GroupCard(
            palette: palette,
            children: [
              _SettingsTile(
                icon: Icons.public_rounded,
                iconColor: const Color(0xFF06B6D4),
                iconBg: const Color(0xFF06B6D4).withOpacity(0.14),
                title: strings.regionPresetTitle,
                trailingValue: _regionLabel(strings, routing.region),
                palette: palette,
                onTap: () => _showRegionDialog(context, ref, routing, palette, strings),
              ),
              _SettingsTile(
                icon: Icons.flag_circle_rounded,
                iconColor: const Color(0xFF22C55E),
                iconBg: const Color(0xFF22C55E).withOpacity(0.14),
                title: strings.bypassIranDomainsTitle,
                subtitle: strings.bypassIranDomainsSubtitle,
                palette: palette,
                switchValue: routing.region != RoutingRegion.global && routing.bypassIranDomains,
                onSwitchChanged: routing.region == RoutingRegion.global
                    ? null
                    : (val) {
                        ref.read(connectionControllerProvider.notifier).updateRoutingOptions(
                              routing.copyWith(bypassIranDomains: val),
                            );
                      },
              ),
              _SettingsTile(
                icon: Icons.router_rounded,
                iconColor: const Color(0xFF6366F1),
                iconBg: const Color(0xFF6366F1).withOpacity(0.14),
                title: strings.bypassLanTitle,
                subtitle: strings.bypassLanSubtitle,
                palette: palette,
                switchValue: routing.bypassLan,
                onSwitchChanged: (val) {
                  ref.read(connectionControllerProvider.notifier).updateRoutingOptions(
                        routing.copyWith(bypassLan: val),
                      );
                },
              ),
              _SettingsTile(
                icon: Icons.rule_folder_rounded,
                iconColor: const Color(0xFFEC4899),
                iconBg: const Color(0xFFEC4899).withOpacity(0.14),
                title: strings.customDirectRulesTitle,
                trailingValue: '${routing.customDirectDomains.length + routing.customDirectCidrs.length} ${strings.isFa ? "قانون" : "rules"}',
                palette: palette,
                onTap: () => _showCustomDirectRulesDialog(context, ref, routing, palette, strings),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Category 4: Network, Core & Stability (شبکه، هسته و پایداری)
          _CategoryLabel(label: strings.networkAndCoreSectionTitle, palette: palette),
          _GroupCard(
            palette: palette,
            children: [
              _SettingsTile(
                icon: Icons.security_rounded,
                iconColor: const Color(0xFF3B82F6),
                iconBg: const Color(0xFF3B82F6).withOpacity(0.14),
                title: strings.remoteDnsTitle,
                trailingValue: routing.remoteDnsServer,
                palette: palette,
                onTap: () => _showDnsDialog(
                  context: context,
                  ref: ref,
                  isRemote: true,
                  currentDns: routing.remoteDnsServer,
                  palette: palette,
                  strings: strings,
                  routing: routing,
                ),
              ),
              _SettingsTile(
                icon: Icons.near_me_rounded,
                iconColor: const Color(0xFF10B981),
                iconBg: const Color(0xFF10B981).withOpacity(0.14),
                title: strings.directDnsTitle,
                trailingValue: routing.directDnsServer,
                palette: palette,
                onTap: () => _showDnsDialog(
                  context: context,
                  ref: ref,
                  isRemote: false,
                  currentDns: routing.directDnsServer,
                  palette: palette,
                  strings: strings,
                  routing: routing,
                ),
              ),
              _SettingsTile(
                icon: Icons.radar_rounded,
                iconColor: const Color(0xFF8B5CF6),
                iconBg: const Color(0xFF8B5CF6).withOpacity(0.14),
                title: strings.trafficSniffingTitle,
                subtitle: strings.trafficSniffingSubtitle,
                palette: palette,
                switchValue: routing.enableTrafficSniffing,
                onSwitchChanged: (val) {
                  ref.read(connectionControllerProvider.notifier).updateRoutingOptions(
                        routing.copyWith(enableTrafficSniffing: val),
                      );
                },
              ),
              _SettingsTile(
                icon: Icons.alt_route_rounded,
                iconColor: const Color(0xFFF97316),
                iconBg: const Color(0xFFF97316).withOpacity(0.14),
                title: strings.enableMuxTitle,
                subtitle: strings.enableMuxSubtitle,
                palette: palette,
                switchValue: routing.enableMux,
                onSwitchChanged: (val) {
                  ref.read(connectionControllerProvider.notifier).updateRoutingOptions(
                        routing.copyWith(enableMux: val),
                      );
                },
              ),
              _SettingsTile(
                icon: Icons.shield_rounded,
                iconColor: const Color(0xFFEF4444),
                iconBg: const Color(0xFFEF4444).withOpacity(0.14),
                title: strings.killSwitchTitle,
                subtitle: strings.killSwitchSubtitle,
                palette: palette,
                switchValue: routing.killSwitch,
                onSwitchChanged: (val) {
                  ref.read(connectionControllerProvider.notifier).updateRoutingOptions(
                        routing.copyWith(killSwitch: val),
                      );
                },
              ),
              _SettingsTile(
                icon: Icons.language_rounded,
                iconColor: const Color(0xFF0EA5E9),
                iconBg: const Color(0xFF0EA5E9).withOpacity(0.14),
                title: strings.enableIpv6Title,
                subtitle: strings.enableIpv6Subtitle,
                palette: palette,
                switchValue: routing.enableIpv6,
                onSwitchChanged: (val) {
                  ref.read(connectionControllerProvider.notifier).updateRoutingOptions(
                        routing.copyWith(enableIpv6: val),
                      );
                },
              ),
              _SettingsTile(
                icon: Icons.phonelink_setup_rounded,
                iconColor: const Color(0xFF64748B),
                iconBg: const Color(0xFF64748B).withOpacity(0.14),
                title: strings.systemVpnSettingsTitle,
                subtitle: strings.systemVpnSettingsSubtitle,
                palette: palette,
                onTap: () async {
                  await ref.read(connectionControllerProvider.notifier).openSystemVpnSettings();
                },
              ),
              _BatteryOptimizationTile(
                palette: palette,
                strings: strings,
              ),
              if (Platform.isAndroid ||
                  Platform.environment.containsKey('FLUTTER_TEST'))
                _SettingsTile(
                  icon: Icons.tune_rounded,
                  iconColor: const Color(0xFF8B5CF6),
                  iconBg: const Color(0xFF8B5CF6).withOpacity(0.14),
                  title: strings.quickSettingsTileTitle,
                  subtitle: strings.quickSettingsTileSubtitle,
                  palette: palette,
                  onTap: () => _handleAddQuickSettingsTile(
                    context,
                    ref,
                    palette,
                    strings,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),

          // Category 5: About & Diagnostics (درباره و پشتیبانی)
          _CategoryLabel(label: strings.aboutSectionTitle, palette: palette),
          _GroupCard(
            palette: palette,
            children: [
              _SettingsTile(
                icon: Icons.info_rounded,
                iconColor: const Color(0xFF0EA5E9),
                iconBg: const Color(0xFF0EA5E9).withOpacity(0.14),
                title: strings.appVersionLabel,
                trailingValue: AppVersion.fullVersion,
                palette: palette,
              ),
              _SettingsTile(
                icon: Icons.memory_rounded,
                iconColor: const Color(0xFF14B8A6),
                iconBg: const Color(0xFF14B8A6).withOpacity(0.14),
                title: strings.coreEngineLabel,
                trailingValue: AppVersion.coreEngineVersion,
                palette: palette,
              ),
              _SettingsTile(
                icon: Icons.content_copy_rounded,
                iconColor: const Color(0xFFA855F7),
                iconBg: const Color(0xFFA855F7).withOpacity(0.14),
                title: strings.copyDiagnosticsTitle,
                palette: palette,
                onTap: () async {
                  final profiles = ref.read(profilesListProvider);
                  final subscriptions = ref.read(subscriptionsListProvider);
                  final report = [
                    'Speedll Connect ${AppVersion.fullVersion}',
                    'Core: ${AppVersion.coreEngineVersion}',
                    'Phase: ${connState.phase.name}',
                    'SmartMode: ${connState.isSmartMode}',
                    'Profiles: ${profiles.length} (Subscriptions: ${subscriptions.length})',
                    'ActiveProtocol: ${connState.activeProfile?.protocol ?? "none"}',
                    'LivePing: ${connState.livePingMs ?? "n/a"} ms',
                    'Routing: bypassIran=${routing.bypassIranDomains}, bypassLan=${routing.bypassLan}, remoteDns=${routing.remoteDnsServer}, directDns=${routing.directDnsServer}, sniff=${routing.enableTrafficSniffing}, mux=${routing.enableMux}, killSwitch=${routing.killSwitch}',
                    if (connState.diagnosticCode != null) 'LastCode: ${connState.diagnosticCode}',
                  ].join('\n');
                  await Clipboard.setData(ClipboardData(text: report));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(strings.diagnosticsCopiedToast),
                        backgroundColor: const Color(0xFF16A34A),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // --- Dialogs ---

  Future<void> _handleAddQuickSettingsTile(
    BuildContext context,
    WidgetRef ref,
    SpeedllThemePalette palette,
    AppStrings strings,
  ) async {
    final result = await ref
        .read(connectionControllerProvider.notifier)
        .requestAddQuickSettingsTile();
    if (!context.mounted) return;
    if (result == 'added' || result == 'already_added' || result == 'denied') {
      final msg = switch (result) {
        'added' => strings.quickSettingsTileAddedToast,
        'already_added' => strings.quickSettingsTileAlreadyAddedToast,
        _ => strings.quickSettingsTileDeniedToast,
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor:
              result == 'denied' ? const Color(0xFFD97706) : const Color(0xFF16A34A),
        ),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.dialogBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Row(
          children: [
            Icon(Icons.tune_rounded, color: palette.secondaryAccent, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                strings.quickSettingsTileManualGuideTitle,
                style: TextStyle(color: palette.textPrimary, fontSize: 16),
              ),
            ),
          ],
        ),
        content: Text(
          strings.quickSettingsTileManualGuideBody,
          style: TextStyle(
            color: palette.textPrimary.withOpacity(0.86),
            fontSize: 13.5,
            height: 1.55,
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: FilledButton.styleFrom(
              backgroundColor: palette.secondaryAccent,
            ),
            child: Text(strings.quickSettingsGotItButton),
          ),
        ],
      ),
    );
  }

  void _showThemeDialog(
    BuildContext context,
    WidgetRef ref,
    SpeedllThemePreset currentPreset,
    SpeedllThemePalette palette,
    AppStrings strings,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.dialogBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text(strings.themeSettingTitle, style: TextStyle(color: palette.textPrimary, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final preset in SpeedllThemePreset.values) ...[
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: preset.previewColor,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
                title: Text(
                  preset.label(strings.isFa),
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 13.5,
                    fontWeight: preset == currentPreset ? FontWeight.w800 : FontWeight.w500,
                  ),
                ),
                trailing: preset == currentPreset
                    ? Icon(Icons.check_circle_rounded, color: palette.secondaryAccent, size: 20)
                    : null,
                onTap: () {
                  ref.read(themePresetProvider.notifier).setPreset(preset);
                  Navigator.of(ctx).pop();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showLanguageDialog(
    BuildContext context,
    WidgetRef ref,
    AppLanguage currentLang,
    SpeedllThemePalette palette,
    AppStrings strings,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.dialogBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text(strings.languageSettingTitle, style: TextStyle(color: palette.textPrimary, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(strings.languagePersian, style: TextStyle(color: palette.textPrimary)),
              trailing: currentLang == AppLanguage.fa
                  ? Icon(Icons.check_circle_rounded, color: palette.secondaryAccent, size: 20)
                  : null,
              onTap: () {
                ref.read(localeControllerProvider.notifier).setLanguage(AppLanguage.fa);
                Navigator.of(ctx).pop();
              },
            ),
            ListTile(
              title: Text(strings.languageEnglish, style: TextStyle(color: palette.textPrimary)),
              trailing: currentLang == AppLanguage.en
                  ? Icon(Icons.check_circle_rounded, color: palette.secondaryAccent, size: 20)
                  : null,
              onTap: () {
                ref.read(localeControllerProvider.notifier).setLanguage(AppLanguage.en);
                Navigator.of(ctx).pop();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showRegionDialog(
    BuildContext context,
    WidgetRef ref,
    SingboxRoutingOptions routing,
    SpeedllThemePalette palette,
    AppStrings strings,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.dialogBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text(strings.regionPresetTitle, style: TextStyle(color: palette.textPrimary, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final r in [
              RoutingRegion.auto,
              RoutingRegion.iran,
              RoutingRegion.russia,
              RoutingRegion.china,
              RoutingRegion.global,
            ])
              ListTile(
                title: Text(
                  r == RoutingRegion.auto ? strings.regionAutoDetect : _regionLabel(strings, r),
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: routing.region == r ? FontWeight.w800 : FontWeight.w500,
                  ),
                ),
                trailing: routing.region == r
                    ? Icon(Icons.check_circle_rounded, color: palette.secondaryAccent, size: 20)
                    : null,
                onTap: () async {
                  Navigator.of(ctx).pop();
                  if (r == RoutingRegion.auto) {
                    await ref.read(connectionControllerProvider.notifier).detectAndApplyRegion();
                  } else {
                    ref.read(connectionControllerProvider.notifier).updateRoutingOptions(
                          routing.copyWith(
                            region: r,
                            bypassIranDomains: r != RoutingRegion.global,
                            bypassLan: r != RoutingRegion.global,
                          ),
                        );
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showDnsDialog({
    required BuildContext context,
    required WidgetRef ref,
    required bool isRemote,
    required String currentDns,
    required SpeedllThemePalette palette,
    required AppStrings strings,
    required SingboxRoutingOptions routing,
  }) {
    final presets = isRemote
        ? const <String, String>{
            '1.1.1.1': '1.1.1.1 (Cloudflare)',
            '8.8.8.8': '8.8.8.8 (Google)',
            '9.9.9.9': '9.9.9.9 (Quad9)',
            '94.140.14.14': '94.140.14.14 (AdGuard)',
            '2606:4700:4700::1111': '2606:4700:4700::1111 (Cloudflare IPv6)',
            '2001:4860:4860::8888': '2001:4860:4860::8888 (Google IPv6)',
          }
        : const <String, String>{
            '178.22.122.100': '178.22.122.100 (Shecan)',
            '185.51.200.2': '185.51.200.2 (Shecan 2)',
            '10.202.10.202': '10.202.10.202 (Radar)',
            '10.202.10.11': '10.202.10.11 (403)',
            '1.1.1.1': '1.1.1.1 (Cloudflare)',
            '8.8.8.8': '8.8.8.8 (Google)',
            '2606:4700:4700::1111': '2606:4700:4700::1111 (Cloudflare IPv6)',
            '2001:4860:4860::8888': '2001:4860:4860::8888 (Google IPv6)',
          };

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.dialogBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text(
          isRemote ? strings.remoteDnsTitle : strings.directDnsTitle,
          style: TextStyle(color: palette.textPrimary, fontSize: 16),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final entry in presets.entries)
                        ListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          title: Text(
                            entry.value,
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontSize: 13,
                            ),
                          ),
                          trailing: currentDns == entry.key
                              ? Icon(
                                  Icons.check_circle_rounded,
                                  color: palette.secondaryAccent,
                                  size: 20,
                                )
                              : null,
                          onTap: () {
                            ref
                                .read(connectionControllerProvider.notifier)
                                .updateRoutingOptions(
                                  isRemote
                                      ? routing.copyWith(
                                          remoteDnsServer: entry.key,
                                        )
                                      : routing.copyWith(
                                          directDnsServer: entry.key,
                                        ),
                                );
                            Navigator.of(ctx).pop();
                          },
                        ),
                    ],
                  ),
                ),
              ),
              const Divider(),
              ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                leading: Icon(
                  Icons.edit_rounded,
                  color: palette.secondaryAccent,
                  size: 18,
                ),
                title: Text(
                  strings.manualDnsTitle,
                  style: TextStyle(
                    color: palette.secondaryAccent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _showManualDnsInput(
                    context,
                    ref,
                    isRemote,
                    currentDns,
                    palette,
                    strings,
                    routing,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showManualDnsInput(
    BuildContext context,
    WidgetRef ref,
    bool isRemote,
    String currentDns,
    SpeedllThemePalette palette,
    AppStrings strings,
    SingboxRoutingOptions routing,
  ) {
    final controller = TextEditingController(text: currentDns);
    String? errorText;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: palette.dialogBackground,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: Text(strings.manualDnsTitle, style: TextStyle(color: palette.textPrimary)),
          content: TextField(
            controller: controller,
            textDirection: TextDirection.ltr,
            style: TextStyle(color: palette.textPrimary),
            decoration: InputDecoration(
              hintText: '1.1.1.1 / tls://dns.google',
              errorText: errorText,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onChanged: (_) {
              if (errorText != null) {
                setDialogState(() => errorText = null);
              }
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(strings.cancelAction)),
            ElevatedButton(
              onPressed: () {
                final text = controller.text.trim();
                if (!SingboxConverter.isValidDnsServer(text)) {
                  setDialogState(() => errorText = strings.manualDnsInvalid);
                  return;
                }
                ref.read(connectionControllerProvider.notifier).updateRoutingOptions(
                      isRemote ? routing.copyWith(remoteDnsServer: text) : routing.copyWith(directDnsServer: text),
                    );
                Navigator.of(ctx).pop();
                ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                  SnackBar(content: Text(strings.manualDnsSaved)),
                );
              },
              child: Text(strings.selectAction),
            ),
          ],
        ),
      ),
    );
  }

  void _showCustomDirectRulesDialog(
    BuildContext context,
    WidgetRef ref,
    SingboxRoutingOptions routing,
    SpeedllThemePalette palette,
    AppStrings strings,
  ) {
    final domainsController = TextEditingController(text: routing.customDirectDomains.join('\n'));
    final cidrsController = TextEditingController(text: routing.customDirectCidrs.join('\n'));

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.dialogBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text(strings.customDirectRulesTitle, style: TextStyle(color: palette.textPrimary, fontSize: 16)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                strings.isFa ? 'دامنه‌های مستقیم (هر خط یک دامنه):' : 'Direct domains (one per line):',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: palette.textPrimary),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: domainsController,
                maxLines: 3,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  hintText: 'shaparak.ir\ndigikala.com',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                strings.isFa ? 'آدرس‌های IP / CIDR مستقیم:' : 'Direct IP / CIDRs:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: palette.textPrimary),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: cidrsController,
                maxLines: 2,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  hintText: '192.168.1.0/24',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(strings.cancelAction)),
          ElevatedButton(
            onPressed: () {
              final domains = domainsController.text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
              final cidrs = cidrsController.text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
              ref.read(connectionControllerProvider.notifier).updateRoutingOptions(
                    routing.copyWith(customDirectDomains: domains, customDirectCidrs: cidrs),
                  );
              Navigator.of(ctx).pop();
            },
            child: Text(strings.selectAction),
          ),
        ],
      ),
    );
  }
}

// --- Visual Widgets for Settings Group & Tiles ---

class _CategoryLabel extends StatelessWidget {
  const _CategoryLabel({required this.label, required this.palette});

  final String label;
  final SpeedllThemePalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6, left: 6, bottom: 8),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
          color: palette.textPrimary.withOpacity(0.65),
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.children, required this.palette});

  final List<Widget> children;
  final SpeedllThemePalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: palette.isLight ? Colors.white : palette.cardSurface.withOpacity(0.94),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.borderColor.withOpacity(0.70), width: 1.1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              children[i],
              if (i < children.length - 1)
                Divider(
                  height: 1,
                  thickness: 0.8,
                  indent: 58,
                  endIndent: 16,
                  color: palette.borderColor.withOpacity(0.40),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.palette,
    this.subtitle,
    this.trailingValue,
    this.switchValue,
    this.onSwitchChanged,
    this.onTap,
    this.isLoading = false,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String? subtitle;
  final String? trailingValue;
  final bool? switchValue;
  final ValueChanged<bool>? onSwitchChanged;
  final VoidCallback? onTap;
  final bool isLoading;
  final SpeedllThemePalette palette;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: switchValue != null ? (onSwitchChanged != null ? () => onSwitchChanged!(!switchValue!) : null) : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 20, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: palette.textPrimary,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 11,
                          color: palette.textPrimary.withOpacity(0.55),
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isLoading)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: palette.secondaryAccent),
                )
              else if (switchValue != null)
                Switch.adaptive(
                  value: switchValue!,
                  activeColor: palette.secondaryAccent,
                  onChanged: onSwitchChanged,
                )
              else ...[
                if (trailingValue != null)
                  Text(
                    trailingValue!,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: palette.textPrimary.withOpacity(0.60),
                    ),
                  ),
                if (onTap != null) ...[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_left_rounded,
                    size: 20,
                    color: palette.textPrimary.withOpacity(0.40),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BatteryOptimizationTile extends ConsumerStatefulWidget {
  const _BatteryOptimizationTile({
    required this.palette,
    required this.strings,
  });

  final SpeedllThemePalette palette;
  final AppStrings strings;

  @override
  ConsumerState<_BatteryOptimizationTile> createState() =>
      _BatteryOptimizationTileState();
}

class _BatteryOptimizationTileState
    extends ConsumerState<_BatteryOptimizationTile> {
  bool? _isUnrestricted;
  AppLifecycleListener? _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
    _lifecycleListener = AppLifecycleListener(
      onResume: _refreshStatus,
    );
  }

  Future<void> _refreshStatus() async {
    final unrestricted = await ref
        .read(connectionControllerProvider.notifier)
        .isIgnoringBatteryOptimizations();
    if (mounted) {
      setState(() => _isUnrestricted = unrestricted);
    }
  }

  @override
  void dispose() {
    _lifecycleListener?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final badgeText = _isUnrestricted == null
        ? '...'
        : (_isUnrestricted!
            ? widget.strings.batteryUnrestrictedBadge
            : widget.strings.batteryRestrictedBadge);

    return _SettingsTile(
      icon: Icons.battery_saver_rounded,
      iconColor: _isUnrestricted == true
          ? const Color(0xFF10B981)
          : const Color(0xFFF59E0B),
      iconBg: (_isUnrestricted == true
              ? const Color(0xFF10B981)
              : const Color(0xFFF59E0B))
          .withOpacity(0.14),
      title: widget.strings.batteryOptimizationTitle,
      subtitle: widget.strings.batteryOptimizationSubtitle,
      trailingValue: badgeText,
      palette: widget.palette,
      onTap: () async {
        await ref
            .read(connectionControllerProvider.notifier)
            .openBatteryOptimizationSettings();
      },
    );
  }
}
