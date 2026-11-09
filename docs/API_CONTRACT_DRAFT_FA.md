# پیش‌نویس قرارداد API حساب Speedll

این API اختیاری و control-plane است؛ ترافیک VPN از این سرویس عبور نمی‌کند. قرارداد تا زمان نیاز واقعی و بررسی امنیتی، فقط پیش‌نویس است.

## اصول

- SellBot و دیتابیس پنل مستقیماً در اختیار اپ قرار نگیرند.
- Pairing code یک‌بارمصرف، کوتاه‌عمر و قابل revoke باشد.
- Access token کوتاه‌عمر؛ refresh token در secure storage و قابل لغو باشد.
- تمام endpointها مالکیت کاربر را سمت سرور بررسی کنند.
- metadata حجم و انقضا فقط از منبع معتبر نمایش داده شود.
- API down باشد، پروفایل محلی و اتصال جاری از کار نیفتند.

## Endpointهای پیشنهادی (نام‌ها provisional)

| Method | Path | هدف |
|---|---|---|
| POST | `/v1/pairing/request` | درخواست pairing code یا آغاز فرایند اتصال |
| POST | `/v1/pairing/claim` | claim از طریق کد تأییدشده |
| POST | `/v1/auth/refresh` | تمدید token |
| POST | `/v1/auth/revoke` | لغو نشست |
| GET | `/v1/me` | اطلاعات پایه حساب |
| GET | `/v1/subscriptions` | فهرست اشتراک‌های مجاز کاربر |
| GET | `/v1/subscriptions/{id}/metadata` | حجم/انقضا، فقط در صورت دسترسی معتبر |

## محدودیت‌ها

- URL کانفیگ خام یا credential را در پاسخ API قرار ندهید مگر نیاز و مدل امنیتی آن جداگانه تأیید شده باشد.
- Pairing نباید با کد ثابت یا بدون expiry پیاده‌سازی شود.
- هیچ secret در query string لاگ‌شونده ارسال نشود.
- rate limit، anti-replay، idempotency و audit log باید طراحی شوند.
- قرارداد OpenAPI نهایی پس از تعیین Backend stack ایجاد شود.
