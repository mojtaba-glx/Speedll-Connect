# ماتریس سازگاری نمونه کانفیگ‌ها و پارسرها

این ماتریس با استفاده از داده‌های ساختگی محافظت‌شده (Sanitized Fixtures) در مسیر `tests/fixtures/sanitized/samples.json` و تست‌های خودکار `packages/speedll_subscription/test/` به‌روزرسانی شده است. هیچ اطلاعات محرمانه یا فعالی در این فایل ثبت نشده است.

| Sample ID | منبع | پروتکل | قابلیت‌های مهم | Parser Status | sing-box Outbound Gen | آزمون منفی / امنیت | نتیجه |
|---|---|---|---|---|---|---|---|
| HDF-DE-01 | Hiddify آلمان | VLESS | Reality, Vision (xtls-rprx-vision), Chrome FP | Pass | Pass | Pass | آماده ارزیابی Native |
| HDF-TR-01 | Hiddify ترکیه | VMess | WebSocket Transport, TLS, JSON Base64 | Pass | Pass | Pass | آماده ارزیابی Native |
| SAN-FR-01 | Sanaei فرانسه | Trojan | gRPC Transport, ServiceName, TLS | Pass | Pass | Pass | آماده ارزیابی Native |
| XNET-FR-01 | X-Net فرانسه | Hysteria2 | Salamander obfs, mport (20000-30000), TLS | Pass | Pass | Pass | آماده ارزیابی Native |
| SS-NL-01 | Shadowsocks | Shadowsocks | SIP002 AEAD, aes-256-gcm | Pass | Pass | Pass | آماده ارزیابی Native |

## روش ارزیابی

- تست‌های Unit Parser با ورودی‌های خراب (Malformed) و فاقد هاست/پورت.
- تست تشخیص و رمزگشایی چندخطی و Base64 در `SubscriptionDetector`.
- تست حفاظتی جلوگیری از حملات DoS از طریق اعمال سقف ۲ مگابایت بر حجم ورودی.
- تست اعتبارسنجی خروجی Outbound در مبدل `SingboxConverter`.
