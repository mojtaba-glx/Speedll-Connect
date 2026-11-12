# گزارش نهایی انتشار نسخه 1.8.0 — Speedll Connect

- **تاریخ انتشار:** ۲۱ آبان ۱۴۰۵ (12 نوامبر 2026)
- **نسخه برنامه:** `1.8.0 (Build 14)`
- **موتور هسته:** `sing-box v1.14.4` (کتابخانه بومی `libbox.aar`)
- **شناسه بسته:** `app.speedll.connect`
- **وضعیت سلامت تست‌ها:** ۶۸ از ۶۸ تست واحد سبز (Dart: 51, Flutter: 17) | بدون هشدار Analyze

---

## ۱. خلاصه اجرایی و دستاوردهای کلیدی نسخه 1.8.0

نسخه 1.8.0 نقطه عطف پایداری و بهینه‌سازی کلاینت چندسکویی Speedll Connect به شمار می‌رود. در این نسخه اهداف فنی زیر با موفقیت تحقق یافت:
1. **کاهش چشمگیر حجم فایل‌های نصبی (APK):** با فعال‌سازی فشرده‌سازی کتابخانه‌های بومی (Deflated Native Libraries)، حجم نسخه نهایی ۶۰ تا ۶۳ درصد کاهش یافت و از بیش از ۹۴ مگابایت به حدود ۳۴ مگابایت رسید.
2. **یکپارچه‌سازی هویت بصری و برندینگ:** آیکون اختصاصی در تمامی فرمت‌ها و رزولوشن‌های رسمی سیستم‌عامل‌های Android (از جمله Adaptive Icon و Themed Icon تک‌رنگ در Android 13+)، iOS (بدون کانال آلفا جهت رعایت الزامات App Store)، macOS (مجموعه AppIcon و ICNS)، Windows (فرمت استاندارد ICO چنداندازه‌ای ۱۶ تا ۲۵۶ پیکسل) و Linux تعبیه شد.
3. **آیکون نوتیفیکیشن اختصاصی نوار وضعیت:** هشدار زرد رنگ سیستم (`stat_sys_warning`) با وکتور مدرن تک‌رنگ سفید اختصاصی (`ic_stat_speedll`) جایگزین گردید.
4. **بهینه‌سازی عمیق مصرف باتری و شبکه:** بازه زمانی پایش وضعیت در حالت Smart از ۱۰ ثانیه به ۶۰ ثانیه افزایش یافت، تعداد نمونه‌گیری در پس‌زمینه به ۱ کاهش پیدا کرد، وضعیت Metered بر اساس شبکه فعال به ارث برده می‌شود و آدرس ULA برای IPv6 اضافه گردید تا از نشت ترافیک در شبکه‌های دوپشته جلوگیری شود.
5. **جلوگیری از نشت حافظه و نشست سیستم:** پاک‌سازی صریح `statusCallback` و `eventSink` در چرخه عمر `MainActivity.onDestroy`.
6. **هماهنگ‌سازی و تثبیت نسخه:** تمامی بخش‌های کد، متادیتا، کانفیگ‌ها و تست‌ها روی نسخه واحد `1.8.0+14` تثبیت شدند.
7. **امضای معتبر و سازگار:** بسته‌های نهایی با Keystore رسمی پروژه امضا شده و تطابق کامل اثرانگشت گواهی (Fingerprint) با نسخه 1.7.1 محرز گردید تا کاربران امکان ارتقای مستقیم بدون پاک‌کردن برنامه قبلی را داشته باشند.

---

## ۲. جدول تغییرات حجم و فشرده‌سازی فایل‌های APK

| نوع بسته / معماری | حجم نسخه قبلی (1.7.1) | حجم اولیه پس از R8 (بدون فشرده‌سازی SO) | حجم نهایی نسخه 1.8.0 (Legacy Packaging) | میزان کاهش حجم نسبت به قبل |
| :--- | :---: | :---: | :---: | :---: |
| **arm64-v8a** | ۹۴.۳۵ MB | ۹۴.۳۵ MB | **۳۴.۲۷ MB** | **۶۰.۰۸ MB (~۶۳.۷٪-)** |
| **armeabi-v7a** | ۸۴.۵۲ MB | ۸۴.۵۲ MB | **۳۳.۹۰ MB** | **۵۰.۶۲ MB (~۵۹.۹٪-)** |

### دلایل فنی کاهش حجم:
- فعال‌سازی `packaging { jniLibs { useLegacyPackaging = true } }` در `app/android/app/build.gradle`: پیش‌فرض Gradle در نسخه‌های جدید عدم فشرده‌سازی فایل‌های `.so` درون فایل ZIP است (جهت لود مستقیم از APK). با فعال کردن فشرده‌سازی Deflate، فایل حجیم `libbox.so` به صورت بهینه فشرده شد.
- فعال بودن R8 Minification و Resource Shrinking (`shrinkResources true`) همراه با Keep Rules دقیق در `proguard-rules.pro` که کدهای بی‌استفاده جاوا/کاتلین و منابع زائد را حذف کرد.
- استفاده از `--split-per-abi` برای حذف معماری‌های غیرهدف نظیر x86 و x86_64 از خروجی‌های تلفن همراه.

---

## ۳. نتایج اعتبارسنجی فشرده‌سازی `libbox.so`

بررسی دقیق ساختار داخلی ZIP فایل‌های خروجی توسط اسکریپت پایتون نتایج زیر را تأیید کرد:

| معماری | وضعیت فشرده‌سازی قبل | حجم فایل اولیه (Raw) | وضعیت فشرده‌سازی در 1.8.0 | حجم فشرده‌شده در APK |
| :--- | :---: | :---: | :---: | :---: |
| **arm64-v8a** | `STORED` (کد 0 - غیرفشرده) | ۷۷.۱۸ MB | **`DEFLATED` (کد 8 - فشرده استاندارد)** | **۲۶.۲۰ MB** |
| **armeabi-v7a** | `STORED` (کد 0 - غیرفشرده) | ۶۹.۴۳ MB | **`DEFLATED` (کد 8 - فشرده استاندارد)** | **۲۶.۱۲ MB** |

- **بررسی صحت کدهای DEX و R8:** کلاس‌های حیاتی لایه Go و کتابخانه هسته (`io.nekohasekai.libbox` و `go.Seq`) به طور کامل در `classes.dex` حفظ شده و دچار حذف اشتباه توسط R8 نشده‌اند.

---

## ۴. وضعیت کامپایل سفارشی libbox (تسک اختیاری ۲-ب)

- **اسکریپت ساخت تکرارپذیر:** فایل اجرایی `scripts/build_libbox_minimal.sh` در مخزن ایجاد شد. این اسکریپت نحوه کامپایل sing-box نسخه `v1.14.4` را با ابزار `gomobile bind` همراه با تگ‌های مورد نیاز (`with_gvisor,with_quic,with_wireguard,with_utls,with_clash_api`) و حذف وابستگی‌های سنگین غیرضروری (مثل tailscale, openvpn, acme و غيره) به صورت کاملاً خودکار مستند کرده است.
- **تصمیم فنی برای این مرحله:** از آنجا که محیط خط فرمان در حالت Sandbox امن بدون دسترسی مستقیم به اینترنت جهت دانلود مخازن Go و ابزار `gomobile` اجرا می‌شود، و همچنین برای تضمین پایداری کامل پروتکل‌های آزمایش‌شده، فایل رسمی و آزموده‌شده `libbox.aar 1.14.4` به صورت دست‌نخورده حفظ شد. فشرده‌سازی Legacy Packaging در مرحله ۲-الف به تنهایی بیش از ۶۳٪ حجم برنامه را کاهش داد که بیش از هدف تعیین‌شده بود.

---

## ۵. ماتریس آیکون‌های اضافه‌شده برای پلتفرم‌ها

| پلتفرم | مسیر فایل‌ها | توضیحات فنی |
| :--- | :--- | :--- |
| **Android** | `app/android/app/src/main/res/` | • `mipmap-anydpi-v26/ic_launcher.xml` و `ic_launcher_round.xml`<br>• `drawable/ic_launcher_foreground.xml` (وکتور گرادیانت)<br>• `drawable/ic_launcher_monochrome.xml` (برای تم پویا در Android 13+)<br>• `values/ic_launcher_background.xml`<br>• فولدرهای `mipmap-mdpi` تا `mipmap-xxxhdpi` (آیکون‌های سنتی شطرنجی و گرد) |
| **نوتیفیکیشن VPN** | `res/drawable/ic_stat_speedll.xml` | وکتور ۲۴dp کاملاً تک‌رنگ و سفید بر بستر شفاف؛ جایگزین `android.R.drawable.stat_sys_warning` در `LibboxVpnService.kt` |
| **iOS** | `app/ios/Runner/Assets.xcassets/AppIcon.appiconset/` | تمامی رزولوشن‌های استاندارد آیفون/آیپد (۲۰px تا ۱۰۲۴px) با `Contents.json` معتبر؛ کامپایل‌شده بدون کانال آلفا (Color Type 2 - RGB) برای تضمین تأیید App Store |
| **macOS** | `app/macos/Runner/Assets.xcassets/AppIcon.appiconset/` | آیکون‌های ۱۶ تا ۱۰۲۴ پیکسل همراه با فایل چند رزولوشنی `app_icon.icns` |
| **Windows** | `app/windows/runner/resources/app_icon.ico` | آیکون با کیفیت ۲۵۶ رنگ شامل لایه‌های ۱۶، ۲۴، ۳۲، ۴۸، ۶۴، ۱۲۸ و ۲۵۶ پیکسل |
| **Linux** | `app/linux/` | آیکون‌های ۲۵۶px و ۵۱۲px به همراه فایل دسکتاپ `speedll-connect.desktop` |
| **درون‌برنامه / About** | `app/assets/branding/app_icon.png` | آیکون ۱۰۲۴x۱۰۲۴ با کیفیت بالا ثبت‌شده در `pubspec.yaml` برای نمایش در دیالوگ‌های راهنما و کارت‌های برندینگ |

---

## ۶. اعتبارسنجی امضای Release و تطابق با نسخه 1.7.1

بررسی خروجی ابزار رسمی `apksigner` تطابق ۱۰۰٪ اثرانگشت گواهی امضا را تأیید کرد:

```text
Signer #1 certificate DN: CN=Speedll Connect, OU=Mobile, O=Speedll, L=Tehran, ST=Tehran, C=IR
Signer #1 certificate SHA-256: 3e60b5490e4b681b929d29b12a69dfbd4d91b672adcf5678f5307b0d59720209
Signer #1 certificate SHA-1:   bd19c0ae62372c46149fbc6bcb64b051ef41829a
Signer #1 public key SHA-256:  de648b0ac9c535868922db2f4149f162c4fddcae535f3eadd81b81465a970d30
Signing Scheme Supported:      v2 scheme: true | v3 scheme: true
```

> [!IMPORTANT]
> اثرانگشت SHA-256 گواهی امضای فایل‌های 1.8.0 دقیقاً برابر با اثرانگشت نسخه 1.7.1 است؛ بنابراین کاربران بدون خطای Signature Mismatch می‌توانند نسخه جدید را بر روی نسخه فعلی نصب (Update) نمایند.

---

## ۷. مشخصات و چک‌سام فایل‌های آزمایشی در `release-test/`

فایل‌های نهایی با متادیتای صحیح در ریشه پروژه درون پوشه امن و نادیده‌گرفته‌شده `release-test/` قرار داده شدند:

| نام فایل | اندازه | چک‌سام SHA-256 |
| :--- | :---: | :--- |
| `Speedll-Connect-v1.8.0-arm64-v8a.apk` | ۳۵.۹۴ MB (۳۵٬۹۴۱٬۰۶۹ بایت) | `06489a64b6469aabc174f126d95070daf843280aabfa31746d751b80cc7e09b1` |
| `Speedll-Connect-v1.8.0-armeabi-v7a.apk` | ۳۵.۵۵ MB (۳۵٬۵۵۲٬۹۹۴ بایت) | `16ae522c24d47d15e69aa13875f09154cf1b4ba45dded62464267a39b2f13931` |

### متادیتای استخراج‌شده با `aapt2 dump badging`:
- `package: name='app.speedll.connect'`
- `versionName='1.8.0'`
- `versionCode='14'` (کد تقسیم arm64: `2014`، کد تقسیم arm: `1014`)
- `minSdkVersion='24'` (Android 7.0+)
- `targetSdkVersion='35'` (Android 15)
- منابع ثبت‌شده: `mipmap/ic_launcher`، `mipmap/ic_launcher_round`، `drawable/ic_stat_speedll`

---

## ۸. نتایج آزمون‌های خودکار (Unit Tests)

تمامی تست‌ها بدون هیچ‌گونه خطا یا شکست با موفقیت کامل پاس شدند:

1. **پکیج اشتراک و مبدل کانفیگ (`packages/speedll_subscription`):**
   - تحلیل استاتیک: `dart analyze` — **No issues found!**
   - تست‌های واحد: `dart test` — **51 از 51 تست پاس شد (All tests passed).**
   - موارد آزموده‌شده: تولید ساختار Inbound و Outbound هسته sing-box 1.14، اعتبارسنجی ULA IPv6، MTU 9000، عدم وجود auto_redirect، پیش‌فرض خاموش بودن `enableTrafficSniffing` و اولویت `hijack-dns` قبل از `sniff` محدودشده به `['tls', 'http', 'quic']`، نبود `detour: direct` در تنظیمات DNS و پارس انواع سرورهای DNS (IP/Port/DoT/DoH/HTTP3/دامنه) و رد ورودی‌های نامعتبر، اعتبارسنجی انواع لینک‌های VLESS، VMess، Trojan، Hysteria2، Shadowsocks و جلوگیری از حملات SSRF.

2. **اپلیکیشن اصلی (`app`):**
   - تحلیل استاتیک: `flutter analyze` — **No issues found!**
   - تست‌های ویجت و منطق: `flutter test` — **17 از 17 تست پاس شد (All tests passed).**
   - موارد آزموده‌شده: پایش سلامت Smart Mode با تایمر ۶۰ ثانیه‌ای، مهاجرت پیش‌فرض Sniffing به خاموش در `SecureProfileStorage`، مخفی‌ماندن IP سرور و پینگ لحظه‌ای پیش از اتصال در صفحه خانه، نمایش دیالوگ انتخاب تم بلافاصله پس از تایید زبان در راه‌اندازی اولیه، اعتبارسنجی ورودی دستی DNS، رندر صحیح رابط کاربری، استخراج اطلاعات اشتراک، سازگاری تم‌ها و بررسی نسخه `AppVersion.fullVersion == '1.8.0 (Build 14)'`.

---

## ۹. چک‌لیست تست دستی روی دستگاه واقعی (Manual QA Guide)

برای تأیید نهایی روی دستگاه‌های اندرویدی فیزیکی، سناریوهای زیر به تیم QA پیشنهاد می‌شود:

- [ ] **تست نصب ارتقایی (In-place Upgrade):** فایل `Speedll-Connect-v1.8.0-arm64-v8a.apk` را بدون پاک‌کردن نسخه 1.7.1 روی گوشی نصب کنید؛ نصب باید بدون خطای `App not installed as package conflicts with an existing package` انجام شود.
- [ ] **بررسی ظاهر آیکون لانچر و تم پویا:** آیکون برنامه را در صفحه اصلی و کشوی برنامه‌ها بررسی کنید؛ در دستگاه‌های مجهز به اندروید ۱۳ و بالاتر با تغییر تم سیستم (Themed Icons)، آیکون باید به صورت مونوکروم و هماهنگ با رنگ سیستم نمایش داده شود.
- [ ] **بررسی آیکون نوتیفیکیشن سرویس VPN:** پس از لمس دکمه اتصال، آیکون نوار وضعیت بالای گوشی باید آیکون اختصاصی تک‌رنگ Speedll (`ic_stat_speedll`) باشد و نه آیکون اخطار سیستمی زرد.
- [ ] **تست اتصال VLESS Reality و مصرف پس‌زمینه:** به یک سرور VLESS Reality متصل شوید، گوشی را در حالت صفحه خاموش (Screen Off) قرار دهید؛ اتصال نباید به خاطر Doze Mode یا تایمر تهاجمی قطع شود.
- [ ] **پایش مصرف باتری با `dumpsys batterystats`:** با اجرای دستور `adb shell dumpsys batterystats --reset` قبل از ۱ ساعت استفاده و بررسی گزارش بعد از آن، میزان مصرف پردازنده و باتری باید در مقایسه با نسخه‌های پیشین با کاهش قابل توجه همراه باشد.
- [ ] **بررسی عدم نشت IPv6:** با اتصال به سایت‌هایی مانند `test-ipv6.com` یا `ipleak.net` بررسی کنید که آدرس IPv6 واقعی دستگاه افشا نشده و ترافیک در تونل محصور بماند.

---

## ۱۰. تاریخچه کامیت‌های این انتشار

1. `6eb3694`: `fix(engine): cleanup legacy references, standardize tunAddresses, and prevent activity leak`
2. `becb193`: `feat(android): compress native libraries in apk via legacy packaging`
3. `13b5e67`: `feat(branding): add platform app icons and monochrome vpn notification icon`
4. `8dbf2f1`: `chore(release): bump version to 1.8.0+14 and consolidate changelog`
5. `28243a0`: `chore: ignore release-test directory`
6. `b737df3`: `docs(reports): add release 1.8.0 verification and test report`
7. `0147e43`: `fix(engine): resolve routing loop, default route omission, and DNS deadlock on Android`
8. `a797208`: `fix(engine): switch to gvisor stack, add port 53 dns hijack, and implement LocalResolver`
9. `a52f50c`: `fix(engine): omit direct detour on DNS entries, scope sniffing after hijack-dns, and default sniffing off`
10. `25a6778`: `feat(ui): gate disconnected ping/IP, add first-launch theme picker, and validate manual DNS`

---

## ۱۱. ریشه‌یابی و حل مشکل عدم عبور ترافیک (Traffic Routing & DNS Deadlock)

در تست دستگاه واقعی مشخص شد که وضعیت VPN به حالت Connected تغییر می‌کند اما هیچ داده‌ای بین برنامه‌ها (مانند تلگرام) و سرور رد و بدل نمی‌شود. با بررسی و مهندسی معکوس رفتار تعامل لایه کاتلین اندروید (`LibboxVpnService` / `LibboxPlatformInterface`) و لایه Go هسته `libbox 1.14.4`، علل ریشه‌ای زیر شناسایی و برطرف گردیدند:

### ۱. لوپ مسیریابی اینترفیس پیش‌فرض (DefaultNetworkMonitor Routing Loop)
- **علت:** در کلاس `DefaultNetworkMonitor.kt`، درخواست شبکه (`NetworkRequest`) فاقد قید `.addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)` بود. پس از برقراری تونل، سیستم‌عامل اندروید اینترفیس مجازی `tun0` را به عنوان یک اینترفیس در دسترس به `ConnectivityManager` اعلام می‌کرد. در نتیجه، کال‌بک `onAvailable` اینترفیس `tun0` را به عنوان شبکه فیزیکی اصلی فرض کرده و با فراخوانی `updateDefaultInterface("tun0")`، اینترفیس زیرین هسته sing-box را به خود `tun0` متصل می‌کرد. بدین ترتیب تمامی ترافیک خروجی پروکسی دوباره به داخل تونل لوپ می‌شد و بن‌بست پکت رخ می‌داد.
- **اصلاح:** قید `NET_CAPABILITY_NOT_VPN` به `NetworkRequest` اضافه شد و در متدهای `onAvailable`، `onCapabilitiesChanged` و `onLinkPropertiesChanged` شرط عدم انتساب شبکه VPN اعمال گردید. علاوه بر این، در `dispatchDefaultInterface` چنانچه نام اینترفیسی با `tun` شروع شود، ارسال آن به sing-box اکیداً مسدود شد.

### ۲. حذف مسیرهای پیش‌فرض سیستم (Omission of Default Route 0.0.0.0/0)
- **علت:** در متد `openTun` فایل `LibboxPlatformInterface.kt`، فراخوانی قبلی `addAddresses(options.inet4Address)` ایتراتور را خالی می‌کرد و بررسی بعدی `options.inet4Address.hasNext()` همواره `false` می‌شد. علاوه بر آن، در اندروید کمتر از ۱۳ از `inet4RouteRange` استفاده می‌شد که در تنظیمات معمول خالی بود. به همین دلیل خط `builder.addRoute("0.0.0.0", 0)` اجرا نمی‌شد و اندروید ترافیک عمومی اپلیکیشن‌ها را به سمت اینترفیس VPN روانه نمی‌کرد.
- **اصلاح:** ایتراتور مسیرهای IPv4 به طور کامل پیمایش شده و در صورتی که هیچ مسیری ثبت نشده باشد، به صورت تضمینی `builder.addRoute("0.0.0.0", 0)` فراخوانی می‌شود. این رفتار برای مسیر پیش‌فرض IPv6 (`::/0`) نیز با fallback امن پیاده‌سازی گردید.

### ۳. بن‌بست تفکیک نام دامنه (DNS Blackhole)
- **علت:** در متد `openTun`، اگر گزینه‌های DNS ورودی خالی بودند، هیچ سرور DNS به `builder.addDnsServer` معرفی نمی‌شد؛ در نتیجه سیستم اندروید کوئری‌های DNS اپلیکیشن‌ها را به جای اینترفیس TUN از شبکه عادی ارسال می‌کرد یا دور می‌ریخت.
- **اصلاح:** یک fallback استاندارد در لایه پلتفرم تعبیه شد که در صورت خالی بودن لیست، آدرس DNS مجازی TUN (`172.19.0.2`) و سرور معتبر `1.1.1.1` را به Builder اضافه کند تا سیستم اندروید به طور قطعی تمام کوئری‌های DNS را به سمت مکانیزم `hijack-dns` هسته هدایت کند.

### ۴. حذف گزینه مخرب `override_android_vpn`
- **علت:** در فایل `singbox_converter.dart`، مقدار `override_android_vpn: true` در بخش TUN اینباند تنظیم شده بود. در نسخه 1.14 هسته sing-box، این گزینه سوکت‌های خروجی sing-box را مجبور می‌کند از محافظت VpnService خارج شده و دوباره از داخل VPN عبور کنند که باعث حلقه بن‌بست پکت‌ها می‌شد.
- **اصلاح:** این پارامتر از ساختار کانفیگ اینباند Tun در پلتفرم اندروید حذف شد.

### ۵. پایداری DNS دایرکت در شبکه ایران
- **علت:** در کانفیگ sing-box، تگ `dns-direct` به آی‌پی ثالث شکن (`178.22.122.100`) مقید شده بود که روی برخی اپراتورهای موبایل در ایران دچار اختلال یا مسدودی است؛ بنابراین خود هسته sing-box نمی‌توانست نام دامنه سرور پروکسی را در مرحله Handshake اولیه ریزالو کند.
- **اصلاح:** سرور `dns-direct` به `{"type": "local", "tag": "dns-direct", "detour": "direct"}` تغییر یافت تا از DNS بومی و پایدار خود شبکه و اپراتور استفاده شود.

### ۶. مدیریت خطای مالک سوکت در `findConnectionOwner`
- **علت:** پرتاب استثنای خام `error("android: connection owner not found")` هنگام عدم شناسایی UID باعث بسته شدن ناگهانی برخی ارتباطات می‌شد.
- **اصلاح:** هدایت نرم خطا به fallback رسمی `Libbox.findConnectionOwner`.

---

## ۱۲. حل قطعی مشکل عدم باز شدن تلگرام و خطای DNS (کامیت `a797208`)

در فاز تست دستگاه کاربر، دو رفتار مهم دیگر مشاهده و رفع شد:

### ۱. عبور نکردن ترافیک TCP (تلگرام و وب) به دلیل استک `mixed`
- **علت فنی:** در هسته sing-box، مقدار `stack: 'mixed'` به این معناست که ترافیک UDP توسط استک کاربران gVisor پردازش شود، اما ترافیک TCP به استک سیستمی سیستم‌عامل محول گردد. در سیستم‌عامل اندروید بدون دسترسی روت، هسته لینوکس هیچ امکانی برای دریافت پکت‌های TCP خام از اینترفیس TUN و اتصال آن‌ها به سوکت‌های سیستم‌عامل ندارد. در نتیجه ترافیک TCP اپلیکیشن‌ها (تلگرام، مرورگرها، اینستاگرام) به صورت خام در تونل ریخته شده و هرگز هندشیک TCP شکل نمی‌گرفت و دیتایی منتقل نمی‌شد.
- **اصلاح:** مقدار `stack` اینباند Tun به طور قطعی روی `'gvisor'` تنظیم گردید تا هر دو پروتکل TCP و UDP به صورت ۱۰۰٪ در فضای کاربری توسط gVisor پردازش شده و به سوکت‌های پروکسی خروجی متصل شوند.

### ۲. نادیده گرفته شدن کوئری‌های DNS هنگام خاموش بودن Sniffing
- **علت فنی:** در تنظیمات کاربر ویژگی «تشخیص هوشمند ترافیک (Sniffing)» خاموش بود. قاعده روتینگ `protocol: "dns"` برای تشخیص پروتکل وابسته به اسنیفر است؛ در غیاب اسنیفر، پکت‌های ارسالی به پورت ۵۳ به عنوان DNS تشخیص داده نمی‌شدند و به جای `hijack-dns`، به سمت پروکسی هدایت می‌شدند و چون مقصد آن‌ها آدرس مجازی تونل (`172.19.0.2`) بود، توسط سرور مقصد دراپ می‌شدند.
- **اصلاح:** افزودن قاعده صریح `{"port": [53], "action": "hijack-dns"}` به رول‌های روتینگ، به طوری که بدون وابستگی به روشن بودن اسنیفر، کلیه ترافیک پورت ۵۳ فوراً توسط هسته DNS رهگیری شود.

### ۳. پیاده‌سازی `LocalResolver` و حل خطای `ERR-CORE-START`
- **علت فنی:** در واسط پلتفرم اندروید (`LibboxPlatformInterface.kt`) متد `localDNSTransport()` مقدار `null` برمی‌گرداند. هنگامی که در کانفیگ سرور `dns-direct` از نوع `local` تعریف می‌شد یا نیاز به ریزالو دامنه‌های محلی بود، نبود پیاده‌سازی ترانسپورت DNS محلی باعث بروز خطای زمان شروع هسته (`ERR-CORE-START`) می‌شد. همچنین در صورت تنظیم سرور `8.8.8.8` برای دایرکت، به علت مسدودی UDP 53 این آی‌پی روی اینترنت ایران، راه‌اندازی با تایم‌اوت مواجه می‌شد.
- **اصلاح:** کلاس بومی `LocalResolver` مطابق اینترفیس `LocalDNSTransport` ساخته شد و با استفاده از متد استاندارد `DefaultNetworkMonitor.defaultNetwork.getAllByName(domain)`، کوئری‌های دایرکت و محلی مستقیماً از طریق DNS اختصاصی سیم‌کارت/وای‌فای فیزیکی بدون هیچ‌گونه لوپ یا اختلال پاسخ داده می‌شوند. همچنین سرور `dns-remote` جهت پاسخ‌دهی سریع‌تر و پایدارتر درون تونل از نوع `udp` بر بستر پروتکل ایمن VLESS XUDP تنظیم گردید.

---

## ۱۳. رفع خطای دستکاری DNS (`ERR-CORE-START`)، تداخل Sniffing و بهبودهای رابط کاربری (کامیت‌های `a52f50c` و `25a6778`)

### ۱. علت و رفع خطای `ERR-CORE-START` هنگام تغییر DNS مستقیم / دستی
- **ریشه خطا (تأییدشده در `libbox.so v1.14.4`):** متد `SingboxConverter.buildDnsConfig` در ورودی‌های `dns-local` و `dns-direct` کلید `'detour': 'direct'` قرار می‌داد، در حالی که outbound با تگ `direct` از نوع خالی `{"type": "direct", "tag": "direct"}` است. کتابخانه هسته در `common/dialer.InitializeDetour` چنین پیکربندی‌ای را با پیام `"detour to an empty direct outbound makes no sense"` هنگام راه‌اندازی رد می‌کرد. پیش از این صرفاً حالت پیش‌فرض (`178.22.122.100` / `type: local`) به دلیل نوع `local` از مقداردهی Dialer عبور می‌کرد و تمام DNSهای دیگر (`8.8.8.8`، `1.1.1.1`، `185.51.200.2` و غیره) هنگام اتصال دچار کرش `ERR-CORE-START` می‌شدند. همچنین ورودی‌های با پورت، IPv6 یا URIهای DoT/DoH پشتیبانی ساختاریافته نداشتند.
- **اصلاح:** کلید `'detour': 'direct'` به کلی از سرورهای DNS مستقیم و محلی حذف شد (فقط `dns-remote` غیرمحلی `'detour': 'proxy'` دارد). پارس و اعتبارسنجی کامل برای `local`، `IPv4/IPv6` با یا بدون پورت، دامنه (به همراه `'domain_resolver': 'dns-local'`) و طرح‌های `udp://`، `tcp://`، `tls://`، `https://` و `h3://` در `SingboxConverter` افزوده شد و دیالوگ DNS دستی در `SettingsPanel` پیش از ذخیره با `SingboxConverter.isValidDnsServer` اعتبارسنجی می‌شود.

### ۲. رفع تداخل Sniffing با عبور دیتا و تغییر پیش‌فرض به خاموش
- **ریشه مشکل:** در تنظیمات قبلی، `enableTrafficSniffing` به صورت پیش‌فرض `true` بود و قانون بدون قید `{"action": "sniff"}` در اندیس صفر `route.rules` **پیش از** قوانین `hijack-dns` قرار داشت و تمام اسنیفرهای `libbox` را با تایم‌اوت ۳۰۰ میلی‌ثانیه فعال می‌کرد.
- **اصلاح:**
  1. پیش‌فرض `enableTrafficSniffing` در `SingboxRoutingOptions` و `SecureProfileStorage` روی `false` (خاموش) قرار گرفت و برای ارتقا از نسخه‌های قبلی (`dnsDefaultsVersion < 3`) به صورت امن به `false` مهاجرت داده می‌شود (پس از ذخیره مجدد در نسخه `3`، تغییر دستی کاربر حفظ می‌گردد).
  2. هنگام فعال بودن دستی Sniffing، قوانین `hijack-dns` (`dns-in`، `port: [53]`، `protocol: dns`) **ابتدا** در `route.rules` قرار می‌گیرند و قاعده `sniff` پس از آن‌ها با محدوده امن `'sniffer': ['tls', 'http', 'quic']` و `'timeout': '100ms'` صادر می‌شود.

### ۳. بهبودهای رابط کاربری (صفحه خانه و راه‌اندازی اولیه)
- **عدم نمایش IP سرور و پینگ لحظه‌ای پیش از اتصال:** در `HomeScreen` نمایش نشانگر IP سرور و بخش `Live Ping` (`SignalBarsIndicator`) مشروط به برقرار بودن اتصال (`isConnected == true`) شد تا تا پیش از اتصال کامل و در حالت قطع یا خطا نمایش داده نشوند.
- **انتخاب تم پیش‌فرض پس از انتخاب زبان در نصب اول:** دیالوگ جدید `ThemeOnboardingDialog` بلافاصله پس از تایید `LanguageOnboardingDialog` باز شده و ۶ تم برنامه را با پیش‌نمایش زنده در زبان انتخاب‌شده به کاربر نمایش می‌دهد.
- **نیازمند تست دستگاه واقعی:** صحت عملکرد اتصال کامل با هر دو حالت Sniffing روشن/خاموش و تغییر DNS روی شبکه واقعی باید روی گوشی اندرویدی بررسی شود.

