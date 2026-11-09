# چک‌لیست انتشار

## پیش از ساخت نسخه
- [ ] تمام تست‌های بحرانی مقصد Pass هستند.
- [ ] نسخه Engine و build flags ثبت شده است.
- [ ] مجوز و notices تمام dependencies بازبینی شده‌اند.
- [ ] SBOM تولید و نگهداری شده است.
- [ ] اسرار و signing keys خارج از مخزن هستند.
- [ ] privacy policy و data disclosure تأیید شده است.
- [ ] تغییرات schema و migration قابل rollback هستند.

## بسته‌بندی
- [ ] امضای معتبر و secure update
- [ ] checksum / artifact provenance
- [ ] بررسی installer و uninstall behavior
- [ ] crash reporting و log redaction
- [ ] release notes و known issues
- [ ] تست روی clean install و upgrade از نسخه قبلی

## انتشار تدریجی
- [ ] کانال داخلی
- [ ] گروه آزمایشی محدود
- [ ] rollout محدود
- [ ] پایش crash و خطاهای اتصال بدون جمع‌آوری secrets
- [ ] معیار توقف و rollback مشخص
- [ ] انتشار عمومی پس از تأیید
