# امنیت و حریم خصوصی

## دارایی‌های حساس

- لینک subscription و query token آن
- UUID، password، private key، obfuscation password و credentialهای پروفایل
- pairing code و access/refresh token حساب Speedll
- metadata مصرف و تاریخچه اتصال کاربر

## اصول ذخیره‌سازی

- Secretها فقط در secure storage بومی OS؛ metadata غیرمحرمانه در دیتابیس محلی.
- Secret خام در log، crash report، clipboard history یا analytics ممنوع.
- export پروفایل باید هشدار محرمانگی داشته باشد و به‌صورت پیش‌فرض secretها را mask کند.
- حذف پروفایل باید secret مرتبط را هم طبق سیاست retention حذف کند.
- قفل صفحه/biometric می‌تواند اختیاری باشد، اما نباید برای اتصال پایه اجباری شود مگر نیاز امنیتی مستند داشته باشد.

## دریافت لینک اشتراک

- فقط schemeهای مجاز و پروتکل‌های مورد پشتیبانی پذیرفته شوند.
- برای fetch لینک اشتراک: timeout، محدودیت حجم، تعداد redirect و content type اعمال شود.
- جلوگیری از SSRF: private IP، loopback، link-local، metadata endpoint و schemeهای غیرمجاز مسدود شوند؛ DNS rebinding نیز بررسی شود.
- فایل/پاسخ ورودی بدون اعتبارسنجی به Engine پاس داده نشود.
- خطاها نباید URL کامل و tokenدار را نمایش دهند.

## اتصال و شبکه

- TLS certificate validation خاموش نشود.
- DNS، IPv4، IPv6، route و leak test برای هر OS انجام شود.
- بازیابی اتصال باید دارای سقف retry و backoff باشد.
- server auto-select نباید بین چند سرور flapping ایجاد کند.
- در زمان disconnect، routeهای ساخته‌شده باید پاک شوند.

## گزارش خطا

- ابتدا sanitization محلی، سپس رضایت برای ارسال.
- حداقل داده لازم؛ بدون پروفایل خام یا credential.
- retention و حذف گزارش مستند شود.

## Threat model

- سرقت دستگاه یا backup
- لینک اشتراک مخرب یا دستکاری‌شده
- subscription endpoint آلوده یا compromise شده
- اجرای کد/کانفیگ با ساختار غیرمنتظره
- دسترسی غیرمجاز به حساب Speedll
- MITM در دریافت اشتراک یا به‌روزرسانی برنامه
- crash/hang در Engine و باقی‌ماندن route یا tunnel
- log leakage و diagnostics leakage

برای هر تهدید، likelihood، impact، mitigation، test و owner ثبت شود.
