<div align="center">

# Speedll Connect

**A modern, privacy-focused cross-platform VPN client powered by Flutter & `sing-box` (`libbox v1.14.4`)**

[English](#english) · [فارسی](#persian) · [Changelog](CHANGELOG.md) · [Roadmap (FA)](docs/ROADMAP_FA.md)

</div>

---

<a id="english"></a>

## English

### Overview

**Speedll Connect** is a multi-platform VPN client written in Dart/Flutter and native Kotlin/Go bindings, built around `sing-box` (`libbox v1.14.4`) for Android and a companion Go TUN/proxy host for Windows. It features a clean Persian/English bilingual interface, multiple dark/light themes, real-time TCP ping & Smart Mode failover, region-aware split tunneling, Hiddify/panel subscription parsing, and opt-in IPv6 support.

* **Current App Version:** `1.9.0 (Build 15)`
* **Core Engine:** `sing-box` (`libbox v1.14.4`)
* **UI & App Framework:** Flutter (`Dart SDK >=3.5.0 <4.0.0`, Riverpod)
* **Primary Working Platforms:** Android (native `LibboxVpnService` + `VpnService` TUN) & Windows (companion host in `platform/windows/host`)
* **Target Roadmap Platforms:** Android, Windows, Linux, macOS, iOS

### Key Features

* **Multi-Protocol Subscription & Config Parser (`packages/speedll_subscription`):**
  * Supports `VLESS` (including Reality & Vision), `VMess`, `Trojan`, `Shadowsocks`, `Hysteria2`, `TUIC`, and `WireGuard` (URIs, `.conf`, Clash YAML, and sing-box JSON), plus raw/Base64 subscription feeds and QR code camera scanning.
  * Decodes `base64:` subscription titles (Hiddify/panel style across `profile-title` headers, `#profile-title:` comments inside raw or Base64 payloads, `Content-Disposition`, and URL fragments/queries) and repairs legacy saved titles automatically.
  * Parses quota & expiration metadata (`Subscription-Userinfo` headers, comments, and info nodes) with SSRF protections on subscription fetch redirects and private hosts.
* **Native Android TUN Core (`sing-box` / `libbox v1.14.4`):**
  * Single native TUN inbound with `gvisor` stack, dual-stack tunnel addresses (`172.19.0.1/30`, `fdfe:dcba:9876::1/126`), MTU `9000`, metered-network inheritance, and `LocalResolver` (`Inet4Address`/`Inet6Address` family filtering).
  * Region-aware routing rules (Iran/China/Russia domestic & LAN bypass, plus user-configurable custom direct domains/CIDRs), customizable Remote & Direct DNS presets/manual DNS, optional Traffic Sniffing (off by default), optional Multiplex/smux, and Kill Switch.
* **Opt-In IPv6 Support (Off by Default):**
  * Toggleable in **Settings → IPv6 Support**. When disabled, enforces `ipv4_only` DNS strategy and strict IPv4 latency probing; when enabled, switches core DNS strategy to `prefer_ipv6`, prioritizes AAAA resolution with automatic IPv4 fallback, and displays IPv6 server addresses properly in LTR.
* **UX, Diagnostics & Smart Connection:**
  * Bilingual (Persian / English) interface with first-launch Language & Theme onboarding and 6 theme presets.
  * Real TCP ping probing, one-tap Smart Mode server selection with automatic health-check failover, and redacted diagnostic error reporting (secrets, passwords, UUIDs, and tokens scrubbed).

### Repository Structure

```text
Speedll-Connect/
├── app/                              # Flutter application (Android Kotlin libbox integration, UI, state, tests)
├── packages/
│   ├── speedll_subscription/         # Dart parsers, sing-box converter, routing assets, subscription updater & tests
│   └── flutter_secure_storage/       # Encrypted/vaulted local key-value storage package
├── platform/windows/host/            # Windows Go VPN host runner & local control IPC
├── scripts/                          # Tooling scripts (fetch_libbox_aar.sh, build_libbox_minimal.sh, platform bootstrap)
├── docs/                             # Architecture, roadmap, build & toolchain docs, ADRs, and reports
├── engine/ & subscription/ & tests/  # Core evaluation docs, shared specifications, and sanitized test fixtures
├── backend/                          # Optional Speedll account API draft (decoupled from VPN traffic path)
├── AGENTS.md                         # Engineering, security, and verification guidelines
├── CHANGELOG.md                      # Version history and release notes
└── LICENSE-PENDING.md                # Licensing notice prior to formal open-source license selection
```

### Local Build & Verification

#### Prerequisites
* Flutter SDK (with Dart SDK `>= 3.5.0`)
* Android SDK & Build Tools (for Android builds)
* Go toolchain + `gomobile` (only if rebuilding `libbox.aar` cleanly via `scripts/build_libbox_minimal.sh`)
* Before building Android APKs, ensure `app/android/app/libs/libbox.aar` is present (fetch via `./scripts/fetch_libbox_aar.sh` or build from `sing-box v1.14.4` with `./scripts/build_libbox_minimal.sh`).
* For signed release builds, copy `app/android/key.properties.example` to `app/android/key.properties` with your own local keystore credentials (**never commit `key.properties` or `.jks` files**).

#### Analyze & Test
```bash
# 1. Core subscription parser & sing-box config package
cd packages/speedll_subscription
dart analyze && dart test

# 2. Flutter app analysis & unit/widget tests
cd ../../app
flutter analyze && flutter test
```

#### Build Android Split-ABI Release APKs
```bash
cd app
flutter build apk --release --split-per-abi
```

See [docs/BUILD_AND_TOOLCHAIN_FA.md](docs/BUILD_AND_TOOLCHAIN_FA.md) for detailed Android SDK, NDK, and `libbox.aar` setup notes.

### Security & Non-Negotiable Engineering Rules

* Never commit real server IPs, user UUIDs, private tokens, active subscription links, `.jks` keystores, `key.properties`, `libbox.aar`, or compiled `.apk`/`.exe` binaries.
* Never fake connection states in UI or tests; report diagnostic errors transparently without leaking secrets.
* Keep account/panel API traffic completely separate from the VPN tunnel path.
* Document major architectural changes under `docs/decisions/`.

### License Status

A final open-source or commercial license for **Speedll Connect** has not yet been selected. Do not publish derived releases with an assumed license before reviewing `LICENSE-PENDING.md`, `docs/LEGAL_AND_LICENSE_CHECKLIST_FA.md`, and upstream `sing-box` licensing requirements.

---

<a id="persian"></a>

<div dir="rtl">

## فارسی

### معرفی پروژه

**Speedll Connect** یک کلاینت VPN چندسکویی مدرن و متن‌محور بر پایه **Flutter** و هسته بومی **`sing-box` (`libbox v1.14.4`)** است (به همراه میزبان Go اختصاصی برای ویندوز). این پروژه شامل رابط کاربری دوزبانه (فارسی/انگلیسی)، تم‌های متنوع روشن و تاریک، سنجش پینگ واقعی و انتخاب هوشمند سرور، مسیریابی منطقه‌ای، پشتیبانی کامل از اشتراک‌های Hiddify/پنل‌ها و پشتیبانی اختیاری از **IPv6** است.

* **نسخه فعلی اپلیکیشن:** `1.9.0 (Build 15)`
* **هسته اصلی اندروید:** `sing-box` (`libbox v1.14.4`)
* **رابط کاربری:** Flutter (`Dart SDK >=3.5.0 <4.0.0` و Riverpod)
* **پلتفرم‌های فعال فعلی:** Android (`LibboxVpnService` + TUN بومی) و Windows (`platform/windows/host`)
* **پلتفرم‌های هدف نقشه راه:** Android، Windows، Linux، macOS و iOS

### قابلیت‌های کلیدی

* **پارسر و مدیریت اشتراک چندپروتکلی (`packages/speedll_subscription`):**
  * پشتیبانی از `VLESS` (از جمله Reality و Vision)، `VMess`، `Trojan`، `Shadowsocks`، `Hysteria2`، `TUIC` و `WireGuard` (لینک‌های استاندارد، `.conf`، Clash YAML و sing-box JSON)، به‌همراه خواندن QR Code با دوربین.
  * رمزگشایی نام اشتراک‌های دارای `base64:` مشابه Hiddify (در هدر `profile-title`، کامنت `#profile-title:` حتی داخل بدنه Base64، هدر `Content-Disposition` و query/fragment) و ترمیم خودکار نام‌های قدیمی ذخیره‌شده.
  * استخراج حجم مصرفی و تاریخ انقضا (`Subscription-Userinfo` و info-nodeها) با محافظت SSRF در درخواست‌های اشتراک.
* **هسته TUN بومی اندروید (`sing-box` / `libbox v1.14.4`):**
  * یک ورودی TUN بومی با استک `gvisor`، آدرس‌دهی هم‌زمان IPv4/IPv6 (`172.19.0.1/30` و `fdfe:dcba:9876::1/126`)، MTU `9000`، وراثت وضعیت metered از شبکه زیرین و `LocalResolver` بومی با تفکیک دقیق `IPv4`/`IPv6`.
  * مسیریابی آگاه از منطقه (عبور مستقیم دامنه‌های داخلی و LAN + قوانین مستقیم سفارشی کاربر)، تنظیم DNS راه دور و مستقیم (پریست یا دستی)، سوییچ اختیاری Sniffing (پیش‌فرض خاموش)، Multiplex/smux و Kill Switch.
* **پشتیبانی اختیاری از IPv6 (پیش‌فرض خاموش):**
  * قابل فعال‌سازی از **تنظیمات ← پشتیبانی از IPv6**. در حالت خاموش، استراتژی DNS روی `ipv4_only` می‌ماند و جستجوی پینگ روی IPv4 قفل می‌شود؛ با روشن شدن آن، اولویت `prefer_ipv6` در هسته، DNS و پینگ فعال شده و آدرس IPv6 سرور با چیدمان صحیح LTR در صفحه خانه و لیست سرورها نمایش داده می‌شود.
* **تجربه کاربری و عیب‌یابی:**
  * انتخاب زبان و تم در اولین اجرا با ۶ تم آماده روشن/تاریک، حالت هوشمند (Smart Mode) با جابه‌جایی خودکار هنگام افت سلامت سرور، و کدهای خطای تشخیصی بدون افشای UUID/رمز/توکن.

### ساختار مخزن

```text
Speedll-Connect/
├── app/                              # برنامه Flutter، پیاده‌سازی Kotlin/libbox اندروید، UI و تست‌ها
├── packages/
│   ├── speedll_subscription/         # پارسرها، مبدل sing-box، قوانین مسیریابی، آپدیتر اشتراک و تست‌ها
│   └── flutter_secure_storage/       # ذخیره‌سازی امن کلید-مقدار محلی
├── platform/windows/host/            # سرویس/میزبان Go برای اجرای تونل و پراکسی روی ویندوز
├── scripts/                          # اسکریپت‌های دریافت/ساخت libbox.aar و آماده‌سازی پلتفرم‌ها
├── docs/                             # معماری، نقشه راه، راهنمای بیلد و ابزارها، ADRها و گزارش‌ها
├── engine/ & subscription/ & tests/  # مستندات ارزیابی هسته و نمونه‌های تست Sanitized
├── backend/                          # پیش‌نویس قرارداد API حساب Speedll (جدا از مسیر ترافیک VPN)
├── AGENTS.md                         # قواعد مهندسی، امنیت و تست پروژه
├── CHANGELOG.md                      # تاریخچه تغییرات نسخه‌ها
└── LICENSE-PENDING.md                # وضعیت فعلی مجوز پیش از انتخاب رسمی لایسنس
```

### ساخت و تست محلی

#### پیش‌نیازها
* Flutter SDK و Dart متناسب با `app/pubspec.yaml`
* Android SDK و Build Tools برای ساخت نسخه اندروید
* دریافت فایل باینری `app/android/app/libs/libbox.aar` از طریق `./scripts/fetch_libbox_aar.sh` یا ساخت مستقیم با `./scripts/build_libbox_minimal.sh`
* برای امضای نسخه Release، فایل `app/android/key.properties.example` را به `app/android/key.properties` کپی کرده و اطلاعات keystore محلی خود را وارد کنید (**هرگز `key.properties` و فایل‌های `.jks` را commit نکنید**).

#### اجرای تحلیل کد و تست‌ها
```bash
# ۱. تست و بررسی پکیج اشتراک و مبدل sing-box
cd packages/speedll_subscription
dart analyze && dart test

# ۲. تست و بررسی اپلیکیشن Flutter
cd ../../app
flutter analyze && flutter test
```

#### ساخت فایل‌های APK نسخه Release (تفکیک ABI)
```bash
cd app
flutter build apk --release --split-per-abi
```

جزئیات بیشتر ابزارها و ساخت `libbox.aar` در [docs/BUILD_AND_TOOLCHAIN_FA.md](docs/BUILD_AND_TOOLCHAIN_FA.md) ثبت شده است.

### اصول غیرقابل مذاکره

* هیچ وضعیت اتصال موفقی را شبیه‌سازی یا جعل نکنید.
* هیچ UUID، رمز، کلید امضا، توکن، IP واقعی سرور یا لینک فعال مشتری را وارد Git، تست، لاگ یا Issue نکنید.
* API حساب Speedll نباید در مسیر عبور ترافیک VPN قرار بگیرد.
* تغییرات مهم معماری باید در `docs/decisions/` ثبت شوند.

### وضعیت مجوز (License)

مجوز نهایی خود Speedll Connect هنوز انتخاب نشده است و تا زمان تصمیم رسمی نباید فایل `LICENSE` فرضی اضافه شود. جزئیات الزامات مجوز کدهای بالادستی (`sing-box` و وابستگی‌ها) در [LICENSE-PENDING.md](LICENSE-PENDING.md) و `docs/LEGAL_AND_LICENSE_CHECKLIST_FA.md` ثبت شده است.

</div>
