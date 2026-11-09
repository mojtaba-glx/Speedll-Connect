# ماتریس سازگاری نمونه کانفیگ‌ها

این ماتریس تا دریافت نمونه‌های Sanitized واقعی خالی/در انتظار است. هیچ اطلاعات محرمانه‌ای در این فایل ثبت نشود.

| Sample ID | منبع | پروتکل | قابلیت‌های مهم | sing-box | Xray | Android | Windows | نتیجه |
|---|---|---|---|---|---|---|---|---|
| HDF-DE-01 | Hiddify آلمان | VLESS | Reality/flow/transport TBD | Not tested | Not tested | Not tested | Not tested | Pending |
| HDF-TR-01 | Hiddify ترکیه | TBD | TBD | Not tested | Not tested | Not tested | Not tested | Pending |
| SAN-FR-01 | Sanaei فرانسه | VLESS/TBD | TBD | Not tested | Not tested | Not tested | Not tested | Pending |
| XNET-FR-01 | X-Net فرانسه | Hysteria2 | obfs/ports/TLS TBD | Not tested | Not tested | Not tested | Not tested | Pending |

## روش ثبت

- فقط ساختار Sanitized؛ UUID/password/token حذف شود.
- نسخه و تاریخ تولید نمونه ثبت شود.
- هر پروفایل با Engine و نسخه دقیق آن تست شود.
- Parser acceptance و actual connection دو نتیجه جدا هستند.
- هر بار که Core به‌روزرسانی می‌شود، regression test تکرار شود.
