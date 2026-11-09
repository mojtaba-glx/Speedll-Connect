# چک‌لیست حقوقی و مجوزها

> این سند مشاوره حقوقی نیست. برای توزیع عمومی/تجاری، بررسی حقوقی تخصصی لازم است.

- [ ] مجوز نسخه دقیق هر Core از فایل LICENSE همان tag/commit ذخیره شود.
- [ ] تمامی dependencyهای مستقیم و transitive و مجوزشان در SBOM ثبت شوند.
- [ ] بررسی شود Engine به‌صورت executable، dynamic library، static link، subprocess یا source integration بسته‌بندی می‌شود.
- [ ] تکلیف انتشار source متناظر، patchها، build scripts و notices روشن شود.
- [ ] شرایط استفاده از نام، لوگو، trademark و عبارت‌های وابستگی/تأیید upstream روشن شود.
- [ ] مجوز Flutter packages، Go modules، native libraries، drivers و installer tools بررسی شود.
- [ ] متن مجوز Speedll Connect جداگانه تصویب شود؛ تا آن زمان `LICENSE` نهایی اضافه نشود.
- [ ] Google Play VPN/VpnService policy، disclosure و data safety بررسی شود.
- [ ] Apple VPN app rules، Network Extension entitlement، organization account و privacy disclosures بررسی شوند.
- [ ] سیاست حریم خصوصی، data retention، analytics و پشتیبانی قبل از انتشار آماده شود.
- [ ] به‌روزرسانی موتور و notices در هر release دوباره بررسی شود.

منابع شروع بررسی:

- Google Play policy center: https://support.google.com/googleplay/android-developer/topic/9877467
- Apple App Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
- Apple Network Extension: https://developer.apple.com/documentation/networkextension
- sing-box: https://github.com/SagerNet/sing-box
- Xray-core: https://github.com/XTLS/Xray-core
