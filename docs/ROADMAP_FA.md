# نقشه راه اجرایی Speedll Connect

این سند منبع اصلی وضعیت و ترتیب اجراست. هر Task باید شواهد، تست و معیار خروج داشته باشد. تیک‌زدن بدون پیاده‌سازی و تست واقعی ممنوع است.

## وضعیت کلی

- [x] P0 — ایجاد اسکلت مخزن و اسناد پایه
- [ ] P1 — بررسی امکان‌سنجی، مجوزها و نمونه‌های واقعی Sanitized
- [ ] P2 — تثبیت معماری و Proof of Concept موتور
- [ ] P3 — نسخه Android آزمایشی با اتصال واقعی
- [ ] P4 — Import و مدیریت اشتراک قابل اتکا
- [ ] P5 — API و امکانات حساب Speedll
- [ ] P6 — Windows و Linux
- [ ] P7 — macOS و iOS
- [ ] P8 — امنیت، کیفیت، بسته‌بندی و انتشار عمومی

---

## P0 — زیرساخت مخزن (شروع شده)

- [x] ایجاد ساختار پوشه‌ها
- [x] ایجاد README و قواعد دستیارهای AI
- [x] ایجاد نقشه راه و اسناد معماری/امنیت/تست
- [x] ایجاد Flutter UI preview
- [x] ایجاد قرارداد اولیه Engine Adapter و مدل پروفایل
- [ ] اجرای `flutter pub get`, `flutter analyze`, `flutter test` در محیط دارای Flutter
- [ ] ثبت نسخه Flutter/Dart/Go و ابزارهای Native در `docs/BUILD_AND_TOOLCHAIN_FA.md`

**معیار خروج:** پروژه روی یک محیط توسعه مشخص باز شود، analyze و test موفق باشند و UI preview بدون ادعای اتصال واقعی اجرا شود.

## P1 — امکان‌سنجی فنی و حقوقی

### ورودی‌ها
- [ ] نمونه Sanitized از VLESS Reality تولیدشده توسط Hiddify آلمان
- [ ] نمونه Sanitized از VLESS یا VMess ترکیه
- [ ] نمونه Sanitized از Sanaei فرانسه
- [ ] نمونه Sanitized از Hysteria2 در X-Net
- [ ] شناسایی پارامترهای transport، TLS، SNI، ALPN، fingerprint، flow، Reality، obfs و port hopping در نمونه‌ها
- [ ] نمونه لینک اشتراک و فرمت محتوای خروجی آن (بدون URL فعال مشتری)

### Engine audit
- [ ] بررسی نسخه پایدار فعلی sing-box و مخزن/مجوز دقیق آن
- [ ] بررسی نسخه پایدار فعلی Xray-core و مخزن/مجوز دقیق آن
- [ ] فهرست وابستگی‌های مستقیم و transitive هر Engine
- [ ] بررسی روش build و packaging برای Android، iOS، Windows، macOS و Linux
- [ ] بررسی API و bridge مناسب، چرخه عمر، crash handling و ارتقای نسخه
- [ ] تعیین قابلیت واقعی هر Core برای هر پروفایل نمونه
- [ ] بررسی مجوز تجاری، ارائه سورس، notices، نام/علامت تجاری و شرایط فروشگاه‌ها
- [ ] دریافت نظر حقوقی برای ترکیب، توزیع و مدل تجاری محصول

### معیار خروج P1

- گزارش Compatibility با نتیجه Pass/Partial/Fail برای هر ویژگی و هر سیستم‌عامل.
- ماتریس مجوز با منبع رسمی، نسخه، تعهدات و مسئول هر اقدام.
- تصمیم رسمی درباره اینکه هر دو Core لازم‌اند یا یک Core برای MVP کافی است.
- فهرست محدودیت‌ها و قابلیت‌های خارج از MVP.

## P2 — Proof of Concept و تثبیت معماری

- [ ] ساخت PoC مستقل اتصال با sing-box روی Android
- [ ] ساخت PoC مستقل اتصال با Xray روی Android، در صورت نیاز واقعی
- [ ] ساخت PoC مستقل Windows برای TUN و چرخه start/stop
- [ ] مقایسه پایداری، مصرف حافظه، latency، زمان اتصال و پیچیدگی بسته‌بندی
- [ ] تست حداقل نمونه‌های Hiddify/Sanaei/X-Net
- [ ] تعریف Normalized Profile Schema نسخه‌دار
- [ ] تعریف Engine Adapter API و Native VPN Adapter API
- [ ] ثبت ADR انتخاب Core و روش packaging
- [ ] تعیین حداقل نسخه OS و معماری CPU پشتیبانی‌شده

**معیار خروج:** حداقل یک پروفایل واقعی Sanitized در PoC هر پلتفرم MVP متصل شود، disconnect واقعی تست شود و تصمیم موتور با شواهد ثبت شود.

## P3 — Android MVP

- [ ] ساخت Android application shell و package ID رسمی
- [ ] پیاده‌سازی VpnService و permission flow
- [ ] مدیریت start/stop و foreground service notification
- [ ] مدیریت lifecycle و جلوگیری از اجرای دو نشست
- [ ] اتصال Engine Adapter منتخب
- [ ] Secure Storage برای پروفایل و اسرار
- [ ] صفحه خانه با وضعیت واقعی Engine
- [ ] انتخاب سرور و فهرست پروفایل‌ها
- [ ] پشتیبانی تغییر Wi-Fi/mobile و بازیابی کنترل‌شده
- [ ] نمایش پیام خطای قابل فهم و کد تشخیصی بدون secret
- [ ] تست Android API/ABIهای مصوب
- [ ] تست battery، background، reboot و crash recovery

**معیار خروج:** اتصال واقعی و پایدار به سرور آزمایشی، قطع واقعی اتصال، بازیابی، تست نشت و QA روی حداقل دو دستگاه/نسخه Android.

## P4 — Import و Subscription Manager

- [ ] Parser جداگانه برای VLESS URI
- [ ] Parser جداگانه برای VMess URI
- [ ] Parser جداگانه برای Trojan URI
- [ ] Parser جداگانه برای Shadowsocks URI
- [ ] Parser جداگانه برای Hysteria2 URI
- [ ] تشخیص Base64 subscription با محدودیت اندازه و timeout
- [ ] Parser محدود و امن برای JSONهای Xray و sing-box
- [ ] QR import
- [ ] اعتبارسنجی syntax و semantics
- [ ] Normalized Profile و round-trip tests در صورت امکان
- [ ] گزارش قابلیت‌های پشتیبانی‌نشده بدون حذف بی‌صدای تنظیمات
- [ ] به‌روزرسانی اشتراک و رفتار در صورت پاسخ خراب/خالی
- [ ] حذف/ویرایش/نام‌گذاری پروفایل
- [ ] جلوگیری از SSRF در fetch اشتراک و محدودیت redirect/host/scheme

**معیار خروج:** مجموعه fixtureهای Sanitized، تست منفی/مثبت، تست payload بزرگ/بدخواه و تست حفظ پارامترهای امنیتی.

## P5 — حساب و خدمات Speedll

- [ ] تعریف API مستقل از SellBot و دیتابیس پنل
- [ ] طراحی Pairing Code یک‌بارمصرف و کوتاه‌عمر
- [ ] احراز هویت امن و rotation/revocation
- [ ] API فهرست اشتراک‌های مجاز
- [ ] API metadata حجم/انقضا در صورت موجودبودن داده معتبر
- [ ] push/local notifications با رضایت کاربر
- [ ] مدیریت خطای API بدون قطع نشست VPN
- [ ] پنل/ابزار پشتیبانی و کد تشخیص قابل Redact
- [ ] تست دسترسی کاربر به فقط حساب خودش

**معیار خروج:** Threat model و تست مجوز دسترسی، انقضای کد اتصال، revoke و offline behavior تکمیل شوند.

## P6 — Windows و Linux

- [ ] Windows native service و TUN adapter
- [ ] نصب/حذف driver و مجوز administrator به روش امن
- [ ] امضای باینری/installer و به‌روزرسانی امن Windows
- [ ] Linux TUN، capabilities و system service
- [ ] پشتیبانی حداقل توزیع‌های مصوب و معماری‌های مصوب
- [ ] مدیریت conflict با firewall و شبکه
- [ ] UI responsive desktop و دسترسی‌پذیری کیبورد
- [ ] تست suspend/resume، logout و crash

## P7 — macOS و iOS

- [ ] بررسی Apple Developer organization/account و entitlementهای لازم
- [ ] پیاده‌سازی Packet Tunnel Provider و lifecycle
- [ ] ارتباط امن Flutter host و extension
- [ ] بررسی محدودیت حافظه/زمان/بسته‌بندی Engine در extension
- [ ] تست iPhone و iPad و نسخه‌های مصوب iOS
- [ ] macOS Network Extension یا معماری مصوب و امضا/notarization
- [ ] بررسی App Store Review Guidelines و privacy disclosures
- [ ] تست upgrade، reconnect، on-demand و حذف پروفایل

**معیار خروج:** build و اتصال واقعی روی سخت‌افزار Apple؛ تأیید entitlementها، signing، extension و مسیر انتشار.

## P8 — امنیت، QA و انتشار

- [ ] threat model نهایی و مرور کد امنیتی
- [ ] DNS leak / IPv6 leak / route leak tests
- [ ] تست TLS، certificate validation و update integrity
- [ ] تست parser fuzzing و ورودی‌های مخرب
- [ ] تست تغییر شبکه، sleep/resume، crash و offline
- [ ] تست عدم افشای اطلاعات در log/crash reports
- [ ] دسترس‌پذیری و UX تست‌شده با کاربران مبتدی/سالمند
- [ ] سیاست حریم خصوصی و data inventory
- [ ] notices و SBOM و سورس متناظر با مجوزها
- [ ] Google Play VpnService disclosures و الزامات رمزنگاری
- [ ] Apple privacy / VPN / entitlement review
- [ ] وب‌سایت و راهنمای نصب/حذف/عیب‌یابی
- [ ] امضای نسخه‌ها، checksum و کانال به‌روزرسانی امن
- [ ] انتشار staged و قابلیت rollback

**معیار خروج:** Release checklist کامل، تمام تست‌های بحرانی Pass، مجوزها مستند و انتشار آزمایشی قابل بازگشت باشد.

---

## سیاست اولویت‌بندی

- MVP اولیه: Android + یک پلتفرم دسکتاپ PoC (ترجیحاً Windows).
- هدف محصول نهایی: پنج سیستم‌عامل؛ اما توسعه و انتشار هم‌زمان و بدون تست ممنوع.
- Web نسخه VPN نیست و نباید به‌عنوان پلتفرم تونل VPN در Scope شمرده شود.
- امکانات عمومی و اتصال حساب Speedll باید از هم جدا باشند.
- هیچ تاریخ تحویل تخمینی تا زمانی که Phase 1 و 2 تمام نشده‌اند ثبت نشود.
