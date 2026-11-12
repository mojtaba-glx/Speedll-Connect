# گزارش نهایی بهینه‌سازی، ارتقا به libbox و پاک‌سازی فنی (Gemini Fix Report)

این گزارش مستندات و نتایج اجرایی مربوط به تسک‌های محوله روی کلاینت VPN چندپلتفرمی **Speedll Connect** را ثبت می‌کند.

---

## ۱. فهرست کامیت‌های ایجادشده (به ترتیب اجرا)

| هش کامیت | پیام کامیت (Conventional Commits) | موضوع و تسک |
|---|---|---|
| `8b831ac` | `feat(subscription): expand parsers, routing rules, and subscription management` | تسک ۰ (ثبت ماژول اشتراک و پارسرها) |
| `ca5bd97` | `feat(windows): add windows vpn host and platform runner support` | تسک ۰ (ثبت هاست بومی و رانر ویندوز) |
| `21a2f80` | `feat(engine): implement libbox native runtime and android vpn service` | تسک ۰ (ثبت اولیه ران‌تایم libbox و Keystore) |
| `ae042f3` | `feat(ui): update home screen widgets, localization, diagnostics, and tests` | تسک ۰ (ثبت ویجت‌ها، تست‌ها و زبان برنامه) |
| `89c1df2` | `docs: update roadmap, changelog, and toolchain documentation` | تسک ۰ (ثبت به‌روزرسانی اسناد و لاگ‌ها) |
| `22d37d7` | `feat(engine): optimize libbox battery and network settings` | تسک ۱ (اصلاحات باتری، IPv6، MTU و Multiplex) |
| `0e68f37` | `feat(application): optimize smart health check intervals and sample counts` | تسک ۲ (بهینه‌سازی تایمر Health Check به ۶۰ ثانیه و ۱ نمونه) |
| `d1ba0fd` | `feat(android): enable r8 minification, abi filtering, and release hardening` | تسک ۳ (فعال‌سازی R8، پروگارد، فیلتر ABI و متدهای Release) |
| `b0912cc` | `refactor(android): remove legacy binary service, tun2socks bridge, and jniLibs binaries` | تسک ۴ (حذف مسیر legacy، بیش از ۱۵۰MB باینری و پل کاربری) |
| `ccee038` | `docs: document libbox migration in adr 0003, update roadmap, and changelog` | تسک ۵ (نگارش ADR 0003، نقشه راه و CHANGELOG) |

---

## ۲. وضعیت انجام تسک‌ها و جزئیات تصمیمات فنی

### تسک ۰ — ذخیره کار فعلی
- **وضعیت:** انجام شد (کامل)
- **فایل‌های مدیریت‌شده:** ۹۰ فایل تغییریافته یا اضافه شده.
- **توضیحات و تصمیم:** فایل‌های بزرگ (`libbox.aar`)، فایل‌های پیکربندی امضا (`key.properties`)، خروجی‌های ساخت (`build/`, `*.apk`, `*.exe`, `*.aar`) در `.gitignore` اعتبارسنجی شدند. بدون تغییر کد در این مرحله، تمامی فایل‌ها در ۵ کامیت موضوعی و تمیز ثبت شدند.

### تسک ۱ — اصلاحات باتری و شبکه در مسیر libbox
- **وضعیت:** انجام شد (کامل)
- **فایل‌های تغییرکرده:**
  - `app/android/app/src/main/kotlin/app/speedll/connect/LibboxPlatformInterface.kt`
  - `app/android/app/src/main/kotlin/app/speedll/connect/LibboxVpnService.kt`
  - `packages/speedll_subscription/lib/src/converters/singbox_converter.dart`
  - `packages/speedll_subscription/test/android_libbox_config_test.dart`
- **اقدامات انجام‌شده:**
  1. حذف `builder.setMetered(false)` در `openTun` جهت ارث‌بری دقیق وضعیت metered از شبکه فیزیکی فعال.
  2. اضافه شدن رنج IPv6 به این‌باند TUN (`['172.19.0.1/30', 'fdfe:dcba:9876::1/126']`) به منظور مسدودسازی نشت ترافیک IPv6.
  3. تغییر مقدار پیش‌فرض MTU به ۹۰۰۰ مطابق استانداردهای Sing-box برای رابط بومی TUN.
  4. حذف گزینه `auto_redirect` از پیکربندی TUN و همچنین از کلاس `OverrideOptions()` در متدهای `startOrReloadService` (هم در start و هم در reload).
  5. بهینه‌سازی بخش multiplex با قرار دادن `padding: false`، حذف `min_streams` و نگهداری `max_connections: 4`.
  6. به‌روزرسانی و افزودن تست‌های جامع در `android_libbox_config_test.dart`.

### تسک ۲ — health check و تایمرها
- **وضعیت:** انجام شد (کامل)
- **فایل‌های تغییرکرده:**
  - `app/lib/application/connection/connection_controller.dart`
- **اقدامات انجام‌شده:**
  1. تغییر فاصله زمانی `_smartHealthTimer` از ۱۰ ثانیه به ۶۰ ثانیه و انتساب آن به ثابت نام‌دار `_smartHealthInterval`. امکان تزریق اختیاری این بازه از طریق سازنده `ConnectionController` جهت تسهیل تست‌های آینده فراهم شد.
  2. اصلاح `pingActiveProfile` برای پذیرش پارامتر اختیاری `{int samples = 3}` با حفظ مقدار پیش‌فرض ۳ نمونه برای پینگ‌های تعاملی UI؛ در متد `checkSmartConnectionHealth` مقدار `samples: 1` فراخوانی شد تا مصرف باتری و پکت‌های شبکه پس‌زمینه به یک‌سوم کاهش یابد.
  3. حفظ منطق توقف تایمرها هنگام رفتن اپ به پس‌زمینه از طریق `AppLifecycleListener`.
  4. اعتبارسنجی و پاس شدن کامل تست‌های ویجت و حالت Smart Mode در `app/test/widget_test.dart`.

### تسک ۳ — Hardening نسخه release
- **وضعیت:** انجام شد (کامل)
- **فایل‌های تغییرکرده:**
  - `app/android/app/src/main/kotlin/app/speedll/connect/LibboxVpnService.kt`
  - `app/android/app/build.gradle`
  - `app/android/app/proguard-rules.pro` (ایجاد شد)
  - `docs/BUILD_AND_TOOLCHAIN_FA.md`
- **اقدامات انجام‌شده:**
  1. در `LibboxVpnService.kt` اجرای متد `triggerNativeCrash` و ثبت لاگ در `writeDebugMessage` به بررسی `BuildConfig.DEBUG` محدود شد؛ همچنین `buildFeatures { buildConfig true }` در `build.gradle` فعال شد.
  2. در نوع بیلد `release`، مقادیر `minifyEnabled true` و `shrinkResources true` تنظیم و فایل `proguard-rules.pro` با Keep Rules کامل برای `io.nekohasekai.libbox.**`, `go.**`, `app.speedll.connect.**`, `com.google.zxing.**` ایجاد و متصل شد.
  3. فیلترگذاری NDK و Splits برای محدودسازی بیلدها صرفاً به `arm64-v8a` و `armeabi-v7a`.
  4. به‌روزرسانی سند ساخت و ثبت دستور انتشار با پرچم‌های بهینه.
  5. اجرای بیلد موفق Release و بررسی درستی حفظ کلاس‌های libbox بعد از R8 با ابزار پایتون در `classes.dex`.

### تسک ۴ — حذف مسیر legacy
- **وضعیت:** انجام شد (کامل، در کامیت کاملاً مجزا جهت امکان Revert سریع)
- **فایل‌های تغییرکرده:**
  - حذف: `SpeedllVpnService.kt`
  - حذف: `Tun2SocksBridge.kt`
  - حذف: پوشه `app/android/app/src/main/jniLibs` (شامل باینری‌های ۱۶۰ مگابایتی `libsingbox.so`)
  - اصلاح: `AndroidManifest.xml` (حذف سرویس `SpeedllVpnService` و ویژگی `android:extractNativeLibs="true"`)
  - اصلاح: `app/android/app/build.gradle` (حذف بلاک `packagingOptions.jniLibs.useLegacyPackaging`)
  - اصلاح: `MainActivity.kt` (حذف کلیه ارجاعات به سرویس legacy و پرچم `nativeLibbox`)
  - اصلاح: `android_vpn_engine_adapter.dart` (حذف پرچم محیطی `SPEEDLL_NATIVE_LIBBOX` و هدایت مستقیم به `buildAndroidLibboxConfig`)
- **بررسی و حفظ متدها:** با بررسی دقیق grep مشخص گردید که `windows_vpn_engine_adapter.dart` از متد `buildFullConfig` استفاده می‌کند؛ لذا این متد به درستی حفظ شد.

### تسک ۵ — به‌روزرسانی اسناد
- **وضعیت:** انجام شد (کامل)
- **فایل‌های تغییرکرده:**
  - ایجاد `docs/decisions/0003-android-libbox-native-tun-migration.md` (ADR جدید شماره 0003)
  - اصلاح `docs/ROADMAP_FA.md` و اضافه شدن ۳ تسک بدون تیک به بخش P3
  - ثبت تغییرات نگارش جدید ۱.۷.۲ در `CHANGELOG.md`

---

## ۳. خلاصه خروجی Analyze و تست‌ها

### پکیج `speedll_subscription`:
```text
$ dart analyze
Analyzing speedll_subscription...
No issues found!

$ dart test
00:00 +47: All tests passed!
```
- **نتیجه:** **۴۷ از ۴۷ تست پاس شدند** (تست‌های جدید مربوط به TUN IPv6، MTU=9000، عدم وجود auto_redirect و multiplex padding=false بدون خطا تأیید شدند).

### اپلیکیشن `app`:
```text
$ flutter analyze
Analyzing app...
No issues found! (ran in 1.7s)

$ flutter test
00:04 +13: All tests passed!
```
- **نتیجه:** **۱۳ از ۱۳ تست پاس شدند** (شامل تست‌های ویجت، پینگ، Smart Mode، QR scanner و تشخیص منطقه).

---

## ۴. حجم APKهای نسخه Release (تفکیک‌شده بر اساس معماری)

دستور اجرا: `flutter build apk --release --split-per-abi --target-platform=android-arm,android-arm64`

| فایل خروجی APK | حجم دقیق (بایت) | حجم تقریبی | وضعیت R8 / Keep Rules |
|---|---|---|---|
| `app-arm64-v8a-release.apk` | ۹۸,۹۳۶,۶۶۴ بایت | **۹۸.۹ مگابایت** | کلاس‌های `io.nekohasekai.libbox` و کدهای بومی حفظ شدند |
| `app-armeabi-v7a-release.apk` | ۸۸,۶۲۹,۲۹۰ بایت | **۸۸.۶ مگابایت** | کلاس‌های `io.nekohasekai.libbox` و کدهای بومی حفظ شدند |

> **نکته بهینه‌سازی:** با حذف باینری‌های مجزای ۱۵۸ مگابایتی `libsingbox.so` و لایه `Tun2SocksBridge`، حجم کلی برنامه به شدت مهار شده و کتابخانه‌های بومی اکنون بدون نیاز به استخراج در دیسک، مستقیماً از حافظه مپ می‌شوند (`android:extractNativeLibs="true"` و `useLegacyPackaging` حذف شدند).

---

## ۵. موارد نیازمند تست روی دستگاه واقعی (Real Device QA)

موارد زیر نیازمند سخت‌افزار واقعی و اتصال فیزیکی به اپراتورها/سیم‌کارت و Wi-Fi هستند:
1. **تست مقایسه‌ای باتری:** اجرای سناریوی ۱ ساعت صفحه خاموش + ۱ ساعت استفاده فعال با گرفتن خروجی `dumpsys batterystats` روی حداقل ۲ نسخه اندروید (اندروید ۱۰ تا ۱۴).
2. **بررسی عدم نشت IPv6 و DNS:** بررسی نشت ترافیک در شبکه‌های دارای Dual-Stack IPv4/IPv6 از طریق وب‌سایت‌های تست نشت (مانند browserleaks.com).
3. **تست جابه‌جایی شبکه (Handover):** جابه‌جایی زنده میان Wi-Fi و داده همراه (Cellular) و تأیید اتصال مجدد خودکار کنترل‌شده با `DefaultNetworkMonitor`.
4. **تست قابلیت‌های Always-on VPN و Kill Switch:** آزمایش رفتار سیستم‌عامل در صورت فعال‌سازی گزینه Block connections without VPN در تنظیمات اندروید.

---

## ۶. انحراف از دستورات پرامپت و دلایل فنی

1. **مدیریت تداخل `ndk.abiFilters` و `splits.abi` در Gradle AGP 8.7+:**
   - *دستور پرامپت:* اضافه کردن مستقیم `ndk { abiFilters 'arm64-v8a', 'armeabi-v7a' }` به `defaultConfig`.
   - *چالش:* در پلاگین Gradle اندروید نگارش ۸ به بالا، در صورتی که هر دو پارامتر `splits.abi` (تولیدشده توسط `--split-per-abi`) و `ndk.abiFilters` هم‌زمان فعال باشند، گریدل با خطای صریح ساختاری مواجه می‌شود:
     `Conflicting configuration : 'armeabi-v7a,arm64-v8a' in ndk abiFilters cannot be present when splits abi filters are set`.
   - *راه‌حل پیاده‌سازی‌شده:* در فایل `app/android/app/build.gradle` شرط بررسی پرچم `split-per-abi` اعمال شد؛ اگر بیلد fat باشد فیلتر `ndk.abiFilters` اعمال می‌شود تا معماری‌های x86 در APK نیاید و اگر بیلد `split-per-abi` باشد، پیکربندی `splits.abi` فیلترها را ریست و به `arm64-v8a` و `armeabi-v7a` محدود می‌کند. این تصمیم هر دو هدف پرامپت را محقق ساخت.
2. **افزودن آرگومان `--target-platform=android-arm,android-arm64` به دستور Flutter CLI:**
   - به این دلیل که دستور پیش‌فرض فلاتر برای `--split-per-abi` به دنبال فایل `app-x86_64-release.apk` نیز می‌گردد و در صورت نیافتن آن کد خروج غیرصفر می‌دهد، پلتفرم‌های هدف به دو معماری تعیین‌شده در تسک محدود شدند.
3. **حفظ متد `buildFullConfig` در `SingboxConverter`:**
   - مطابق شرط پرامپت مبنی بر عدم حذف این متد در صورت نیاز ویندوز، با جستجوی کد مشخص شد که ماژول `windows_vpn_engine_adapter.dart` از این متد بهره می‌برد، بنابراین متد فوق بدون تغییر حفظ گردید.
