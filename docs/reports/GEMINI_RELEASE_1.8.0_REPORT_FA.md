# گزارش نهایی انتشار نسخه 1.8.0 — Speedll Connect

- **تاریخ انتشار:** ۲۱ آبان ۱۴۰۵ (12 نوامبر 2026)
- **نسخه برنامه:** `1.8.0 (Build 14)`
- **موتور هسته:** `sing-box v1.14.4` (کتابخانه بومی `libbox.aar`)
- **شناسه بسته:** `app.speedll.connect`
- **وضعیت سلامت تست‌ها:** ۶۰ از ۶۰ تست واحد سبز (Dart: 47, Flutter: 13) | بدون هشدار Analyze

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
| `Speedll-Connect-v1.8.0-arm64-v8a.apk` | ۳۴.۲۷ MB | `e4724ad118869c91f0882ca107cdc7ab3394a0c980b409ceacb21449c2a6d90c` |
| `Speedll-Connect-v1.8.0-armeabi-v7a.apk` | ۳۳.۹۰ MB | `f21cbcb9ff3eb6512bdeeb9acfa6cce18eccd0ee4e00598a41e308612432c021` |

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
   - تست‌های واحد: `dart test` — **47 از 47 تست پاس شد (All tests passed).**
   - موارد آزموده‌شده: تولید ساختار Inbound و Outbound هسته sing-box 1.14، اعتبارسنجی ULA IPv6، MTU 9000، عدم وجود auto_redirect، اعتبارسنجی انواع لینک‌های VLESS، VMess، Trojan، Hysteria2، Shadowsocks و جلوگیری از حملات SSRF.

2. **اپلیکیشن اصلی (`app`):**
   - تحلیل استاتیک: `flutter analyze` — **No issues found!**
   - تست‌های ویجت و منطق: `flutter test` — **13 از 13 تست پاس شد (All tests passed).**
   - موارد آزموده‌شده: پایش سلامت Smart Mode با تایمر ۶۰ ثانیه‌ای، رندر صحیح رابط کاربری، استخراج اطلاعات اشتراک، سازگاری تم‌ها و بررسی نسخه `AppVersion.fullVersion == '1.8.0 (Build 14)'`.

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
