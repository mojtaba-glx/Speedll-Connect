import 'package:flutter/material.dart';
import '../../domain/connection/connection_phase.dart';

enum AppLanguage {
  fa,
  en;

  bool get isRtl => this == AppLanguage.fa;
  TextDirection get textDirection =>
      this == AppLanguage.fa ? TextDirection.rtl : TextDirection.ltr;
  Locale get locale =>
      this == AppLanguage.fa ? const Locale('fa') : const Locale('en');

  String get code => this == AppLanguage.fa ? 'fa' : 'en';

  static AppLanguage fromCode(String? code,
      {AppLanguage fallback = AppLanguage.fa}) {
    if (code == null) return fallback;
    return code.trim().toLowerCase().startsWith('en')
        ? AppLanguage.en
        : (code.trim().toLowerCase().startsWith('fa')
            ? AppLanguage.fa
            : fallback);
  }
}

/// Complete bilingual (Persian / English) string dictionary for Speedll Connect.
class AppStrings {
  const AppStrings(this.language);

  final AppLanguage language;
  bool get isFa => language == AppLanguage.fa;

  // Header & Connection Status
  String get securedConnectionHeader =>
      isFa ? 'اتصال امن' : 'SECURED CONNECTION';
  String get connectionStatusTitle =>
      isFa ? 'وضعیت اتصال' : 'Connection Status';

  String statusLabel(ConnectionPhase phase) {
    if (isFa) {
      return switch (phase) {
        ConnectionPhase.connected => 'متصل شد',
        ConnectionPhase.connecting => 'در حال اتصال...',
        ConnectionPhase.preparing => 'در حال آماده‌سازی...',
        ConnectionPhase.reconnecting => 'تلاش مجدد اتصال...',
        ConnectionPhase.disconnecting => 'در حال قطع اتصال...',
        ConnectionPhase.failed => 'خطا در برقراری اتصال',
        ConnectionPhase.disconnected => 'قطع شده',
      };
    }
    return switch (phase) {
      ConnectionPhase.connected => 'CONNECTED',
      ConnectionPhase.connecting => 'CONNECTING...',
      ConnectionPhase.preparing => 'PREPARING...',
      ConnectionPhase.reconnecting => 'RECONNECTING...',
      ConnectionPhase.disconnecting => 'DISCONNECTING...',
      ConnectionPhase.failed => 'CONNECTION FAILED',
      ConnectionPhase.disconnected => 'DISCONNECTED',
    };
  }

  // Ping & Location
  String get livePingLabel => isFa ? 'پینگ لحظه‌ای' : 'Live Ping';
  String pingMsValue(int? ms) {
    if (ms == null) return isFa ? '— ms' : '— ms';
    if (ms < 0) return isFa ? 'بدون پاسخ' : 'Timeout';
    return '$ms ms';
  }

  String get testingPing => isFa ? 'در حال تست پینگ...' : 'Testing ping...';
  String get testAllPings => isFa ? 'تست پینگ همه' : 'Ping All';
  String get sortByPing => isFa ? 'مرتب‌سازی پینگ' : 'Sort by Ping';
  String get subscriptionInfoBadge =>
      isFa ? 'اطلاعات اشتراک' : 'Subscription Info';
  String get pingingAllCompletedToast => isFa
      ? 'تست پینگ تمامی کانفیگ‌ها انجام شد.'
      : 'Ping test completed for all configs.';

  // Profiles & Smart Mode (replacing "موقعیت سرور")
  String get profilesTitle => isFa ? 'پروفایل‌ها' : 'Profiles';
  String get myProfilesTitle => isFa ? 'پروفایل‌های من' : 'My Profiles';
  String get viewConfigsLabel => isFa ? 'مشاهده کانفیگ‌ها' : 'View Configs';
  String get hideConfigsLabel => isFa ? 'بستن کانفیگ‌ها' : 'Hide Configs';
  String get selectAction => isFa ? 'انتخاب' : 'Select';
  String get activeStatus => isFa ? 'فعال' : 'Active';
  String get deleteSubscriptionTitle =>
      isFa ? 'حذف اشتراک' : 'Delete Subscription';
  String deleteSubscriptionPrompt(String name) => isFa
      ? 'آیا از حذف اشتراک «$name» و تمامی کانفیگ‌های آن مطمئن هستید؟'
      : 'Are you sure you want to delete "$name" and all its servers?';
  String get confirmDelete => isFa ? 'حذف قطعی' : 'Delete';
  String get cancelAction => isFa ? 'انصراف' : 'Cancel';
  String get manualConfigsSectionTitle =>
      isFa ? 'کانفیگ‌های دستی / تکی' : 'Manual Configs';
  String get clearManualConfigsPrompt => isFa
      ? 'آیا از حذف تمامی کانفیگ‌های دستی مطمئن هستید؟'
      : 'Are you sure you want to delete all manual configs?';
  String get allProfilesHeader =>
      isFa ? 'همه کانفیگ‌ها و پروفایل‌ها' : 'All Profiles & Configs';
  String get smartModeTitle =>
      isFa ? 'حالت هوشمند (اتوماتیک)' : 'Smart Mode (Auto Select)';
  String get smartModeSubtitle => isFa
      ? 'انتخاب خودکار سریع‌ترین سرور بر اساس کمترین پینگ'
      : 'Automatically selects fastest server with lowest ping';
  String get smartBadge => isFa ? 'هوشمند' : 'SMART';
  String get manualBadge => isFa ? 'دستی' : 'MANUAL';
  String get selectProfilePrompt => isFa ? 'انتخاب پروفایل' : 'Select Profile';
  String get noProfilesYet =>
      isFa ? 'هنوز سروری اضافه نشده است' : 'No server profiles added yet';
  String get searchProfilesHint => isFa
      ? 'جستجوی نام سرور، کشور یا پروتکل...'
      : 'Search profile, country or protocol...';
  String get switchedWhileConnectedToast => isFa
      ? 'سرور در حین اتصال با موفقیت تعویض شد.'
      : 'Active server switched seamlessly.';

  // Import & Subscription
  String get addSubscriptionOrConfig =>
      isFa ? 'افزودن اشتراک یا کانفیگ' : 'Add Subscription or Config';
  String get scanQrWithCamera =>
      isFa ? 'اسکن بارکد QR با دوربین' : 'Scan QR Code with Camera';
  String get refreshSubscriptionsTooltip =>
      isFa ? 'به‌روزرسانی اشتراک‌ها' : 'Refresh Subscriptions';
  String get subscriptionsUpdatedToast => isFa
      ? 'اشتراک‌ها با موفقیت به‌روزرسانی شدند.'
      : 'Subscriptions updated successfully.';
  String get subscriptionsUpdateFailedToast => isFa
      ? 'خطا در به‌روزرسانی اشتراک‌ها.'
      : 'Failed to update subscriptions.';
  String get subscriptionLabel => isFa ? 'اشتراک' : 'Subscription';

  // Subscription Usage Card
  String get subscriptionUsageActive =>
      isFa ? 'اشتراک فعال' : 'Active Subscription';
  String get subscriptionUsageUsed => isFa ? 'حجم مصرف‌شده' : 'Data Used';
  String get subscriptionUsageRemaining =>
      isFa ? 'حجم باقی‌مانده' : 'Data Left';
  String get subscriptionUsageDaysLeft => isFa ? 'روز باقی‌مانده' : 'Days Left';
  String get subscriptionUsageExpiry => isFa ? 'تاریخ انقضا' : 'Expires';
  String get subscriptionUsageNoData => isFa
      ? 'برای نمایش دقیق حجم و روز، اشتراک را به‌روزرسانی کنید.'
      : 'Refresh the subscription to load usage and expiry details.';
  String get subscriptionUsageExpired => isFa ? 'منقضی شده' : 'Expired';
  String get subscriptionUsageUnlimited => isFa ? 'نامحدود' : 'Unlimited';
  String get subscriptionUsageToday => isFa ? 'امروز' : 'Today';

  // Bottom Navigation
  String get navHome => isFa ? 'خانه' : 'Home';
  String get navProfiles => isFa ? 'پروفایل‌ها' : 'Profiles';
  String get navStatistics => isFa ? 'آمار' : 'Statistics';
  String get navSettings => isFa ? 'تنظیمات' : 'Settings';

  // Statistics Screen
  String get statisticsHeader => isFa ? 'آمار و وضعیت' : 'STATISTICS';
  String get downloadLabel => isFa ? 'دریافت (Download)' : 'Download';
  String get uploadLabel => isFa ? 'ارسال (Upload)' : 'Upload';
  String get connectionDetailsHeader =>
      isFa ? 'جزئیات اتصال' : 'Connection Details';
  String get countryLabel => isFa ? 'کشور و موقعیت' : 'Country';
  String get protocolAndModeLabel => isFa ? 'پروتکل و حالت' : 'Protocol & Mode';
  String get routingModeLabel => isFa ? 'حالت مسیریابی' : 'Routing Mode';
  String get routingIranBypassValue =>
      isFa ? 'مستقیم برای .ir و LAN' : 'Bypass .ir & LAN';
  String get routingDomesticBypassValue => isFa
      ? 'مستقیم برای دامنه‌های داخلی و LAN'
      : 'Bypass domestic domains & LAN';
  String get routingGlobalValue =>
      isFa ? 'تونل کامل (Global)' : 'Global Tunnel';

  // Settings Screen ()
  String get settingsHeader => isFa ? 'تنظیمات' : 'SETTINGS';
  String get generalSectionTitle =>
      isFa ? 'ظاهر و زبان' : 'Appearance & Language';
  String get appearanceSectionTitle =>
      isFa ? 'ظاهر و زبان' : 'Appearance & Language';
  String get connectionSectionTitle =>
      isFa ? 'اتصال و سرورها' : 'Connection & Servers';
  String get networkAndCoreSectionTitle =>
      isFa ? 'شبکه، هسته و پایداری' : 'Network, Core & Stability';
  String get systemVpnSettingsTitle =>
      isFa ? 'تنظیمات Always-on VPN سیستم اندروید' : 'Android System VPN Settings';
  String get systemVpnSettingsSubtitle => isFa
      ? 'فعال‌سازی Kill Switch در سطح سیستم‌عامل برای جلوگیری از هرگونه نشت'
      : 'Enable OS-level Kill Switch to block non-VPN traffic completely';
  String get languageSettingTitle => isFa ? 'زبان برنامه' : 'App Language';
  String get languagePersian => 'فارسی (Persian)';
  String get languageEnglish => 'English (انگلیسی)';
  String get themeSettingTitle =>
      isFa ? 'تم و رنگ‌بندی برنامه' : 'App Theme Palette';
  String get themeSettingSubtitle => isFa
      ? 'انتخاب پوسته دلخواه (بنفش، دارک، فیروزه‌ای، سبز، آبی، لایت)'
      : 'Choose theme (Purple, Dark, Cyan, Green, Blue, Light)';
  String get smartSelectionSectionTitle =>
      isFa ? 'حالت اتصال و انتخاب سرور' : 'Connection & Server Selection';
  String get enableSmartModeSetting =>
      isFa ? 'انتخاب هوشمند سرور (Smart Mode)' : 'Smart Auto Server Selection';
  String get routingSectionTitle =>
      isFa ? 'مسیریابی و قوانین منطقه' : 'Routing & Region Rules';
  String get regionPresetTitle =>
      isFa ? 'منطقه و مسیریابی داخلی' : 'Region & Domestic Routing';
  String get regionAutoDetect => isFa ? 'تشخیص خودکار' : 'Auto Detect';
  String get regionIran => isFa ? 'ایران' : 'Iran';
  String get regionChina => isFa ? 'چین' : 'China';
  String get regionRussia => isFa ? 'روسیه' : 'Russia';
  String get regionGlobal => isFa ? 'جهانی' : 'Global';
  String get currentRegionLabel => isFa ? 'منطقه فعال' : 'Active Region';
  String regionDetectedToast(String label) => isFa
      ? 'منطقه $label تشخیص داده شد و قوانین مسیریابی اعمال شد.'
      : '$label region detected and routing rules applied.';
  String get bypassChinaDomainsTitle => isFa
      ? 'عبور مستقیم سایت‌ها و سرویس‌های چین'
      : 'Bypass Chinese Domestic Sites';
  String get bypassChinaDomainsSubtitle => isFa
      ? 'دسترسی مستقیم به دامنه‌ها و IPهای چین هنگام فعال بودن تونل'
      : 'Route Chinese domains and IP ranges directly while connected';
  String get bypassRussiaDomainsTitle => isFa
      ? 'عبور مستقیم سایت‌ها و سرویس‌های روسیه'
      : 'Bypass Russian Domestic Sites';
  String get bypassRussiaDomainsSubtitle => isFa
      ? 'دسترسی مستقیم به دامنه‌ها و IPهای روسیه هنگام فعال بودن تونل'
      : 'Route Russian domains and IP ranges directly while connected';
  String get bypassDomesticGlobalTitle =>
      isFa ? 'مسیریابی داخلی غیرفعال است' : 'Domestic Routing Disabled';
  String get bypassDomesticGlobalSubtitle => isFa
      ? 'برای فعال‌سازی، یکی از منطقه‌های ایران، چین یا روسیه را انتخاب کنید.'
      : 'Select Iran, China, or Russia to enable domestic bypass.';
  String get presetIranSplit =>
      isFa ? 'ایران (.ir + LAN مستقیم)' : 'Iran (.ir + LAN)';
  String get presetGlobalTunnel =>
      isFa ? 'تونل کامل (Global)' : 'Global Tunnel';
  String get presetLanOnly => isFa ? 'فقط شبکه محلی (LAN)' : 'LAN Only';
  String get bypassIranDomainsTitle => isFa
      ? 'عبور مستقیم سایت‌ها و بانک‌های داخلی (.ir)'
      : 'Bypass Domestic (.ir) Domains';
  String get bypassIranDomainsSubtitle => isFa
      ? 'باز شدن مستقیم سایت‌های .ir بدون نیاز به قطع VPN'
      : 'Route .ir websites directly without disconnecting VPN';
  String get bypassLanTitle => isFa
      ? 'عبور مستقیم شبکه محلی (LAN / Private IP)'
      : 'Bypass Local Network (LAN)';
  String get bypassLanSubtitle => isFa
      ? 'دسترسی مستقیم به مودم و دستگاه‌های شبکه خانگی'
      : 'Allow direct access to local router and LAN devices';
  String get customDirectRulesTitle =>
      isFa ? 'دامنه‌ها و IPهای مستقیم سفارشی' : 'Custom Direct Domains & IPs';
  String get dnsAndCoreSectionTitle =>
      isFa ? 'تنظیمات پیشرفته هسته و DNS' : 'Advanced Core & DNS';
  String get remoteDnsTitle =>
      isFa ? 'سرور DNS راه دور (Remote DNS)' : 'Remote DNS Server';
  String get directDnsTitle =>
      isFa ? 'سرور DNS مستقیم (Direct DNS)' : 'Direct DNS Server';
  String get manualDnsTitle => isFa ? 'DNS دستی' : 'Manual DNS';
  String get manualDnsHint => isFa
      ? 'آدرس IP سرور DNS را وارد کنید (مثال: 178.22.122.100)'
      : 'Enter the DNS server IP address (e.g. 178.22.122.100)';
  String get manualDnsInvalid => isFa
      ? 'آدرس DNS معتبر نیست؛ یک IP معتبر وارد کنید.'
      : 'Invalid DNS address; enter a valid IP.';
  String get manualDnsSaved =>
      isFa ? 'سرور DNS دستی ذخیره شد.' : 'Manual DNS server saved.';
  String get trafficSniffingTitle =>
      isFa ? 'تشخیص هوشمند ترافیک (Sniffing)' : 'Traffic Sniffing';
  String get trafficSniffingSubtitle => isFa
      ? 'تشخیص دامنه واقعی برای مسیریابی دقیق و جلوگیری از نشت DNS'
      : 'Detects domain names from traffic for accurate routing';
  String get enableMuxTitle => isFa
      ? 'تجمیع اتصالات (Multiplex / Mux)'
      : 'Connection Multiplexing (Mux)';
  String get enableMuxSubtitle => isFa
      ? 'کاهش تاخیر دست‌دهی در اتصالات چندگانه'
      : 'Reduces latency across concurrent streams';
  String get killSwitchTitle =>
      isFa ? 'قطع اضطراری ترافیک (Kill Switch)' : 'Kill Switch';
  String get killSwitchSubtitle => isFa
      ? 'در صورت قطع ناگهانی هسته، ترافیک تا قطع یا اتصال مجدد مسدود می‌ماند'
      : 'Blocks traffic if the core crashes until you disconnect or reconnect';
  String get subscriptionsSectionTitle =>
      isFa ? 'مدیریت اشتراک‌ها و کانفیگ‌ها' : 'Subscriptions & Profiles';
  String get savedSubscriptionsHeader =>
      isFa ? 'لینک‌های اشتراک ثبت‌شده' : 'Saved Subscription Links';
  String get noSavedSubscriptions => isFa
      ? 'هنوز لینک اشتراکی ثبت نشده است'
      : 'No subscription links saved yet';
  String get clearAllProfilesTitle =>
      isFa ? 'پاک‌سازی همه پروفایل‌ها' : 'Clear All Profiles';
  String get clearAllProfilesClearedToast =>
      isFa ? 'تمامی پروفایل‌ها پاک‌سازی شدند.' : 'All profiles cleared.';
  String get copyDiagnosticsTitle => isFa
      ? 'کپی گزارش وضعیت و عیب‌یابی (Sanitized)'
      : 'Copy Diagnostic Status Report';
  String get diagnosticsCopiedToast => isFa
      ? 'گزارش وضعیت در کلیپ‌بورد کپی شد.'
      : 'Diagnostic status copied to clipboard.';
  String get aboutSectionTitle =>
      isFa ? 'درباره برنامه و اطلاعات نسخه' : 'About & Version Info';
  String get appVersionLabel => isFa ? 'نسخه داخلی برنامه' : 'App Version';
  String get coreEngineLabel => isFa ? 'موتور هسته' : 'Core Engine';
  String get coreStatusFooter => isFa
      ? 'هسته متصل: sing-box · آماده اتصال واقعی'
      : 'Connected Core: sing-box · Ready for Real Tunnel';

  // First-Launch Language Onboarding Dialog
  String get onboardingTitle => 'انتخاب زبان برنامه / Choose Language';
  String get onboardingSubtitle => isFa
      ? 'زبان پیش‌فرض بر اساس زبان گوشی شما تشخیص داده شد. لطفاً زبان مورد نظر خود را تایید یا انتخاب کنید:'
      : 'Default language was detected from your device. Please confirm or choose your preferred language:';
  String get confirmAndContinue =>
      isFa ? 'تایید و ورود به برنامه' : 'Confirm & Continue';
  String get detectedFromDeviceBadge =>
      isFa ? 'تشخیص از زبان گوشی' : 'Detected from device';

  // First-Launch Theme Onboarding Dialog
  String get themeOnboardingTitle =>
      isFa ? 'انتخاب تم پیش‌فرض برنامه' : 'Choose Default Theme';
  String get themeOnboardingSubtitle => isFa
      ? 'تم و رنگ‌بندی پیش‌فرض برنامه را انتخاب کنید (هر زمان از بخش تنظیمات قابل تغییر است):'
      : 'Choose your default app theme palette (you can change it anytime in Settings):';
}
