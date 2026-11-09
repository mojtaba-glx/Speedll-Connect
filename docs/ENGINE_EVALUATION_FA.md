# ارزیابی موتورهای VPN — تصمیم هنوز قطعی نیست

## موضع فعلی

- sing-box: نامزد اصلی به‌دلیل گستردگی پروتکل‌ها و مسیرهای build/library برای چند پلتفرم.
- Xray-core: نامزد مکمل برای پروفایل‌ها و قابلیت‌های مبتنی بر Xray.
- هیچ تضمینی برای اجرای همه قابلیت‌های هر کانفیگ یا هر OS داده نمی‌شود تا POC همان feature انجام شود.

## نکات مجوزی اولیه (باید در زمان ادغام دوباره بررسی شوند)

- مخزن رسمی sing-box در زمان تهیه این اسکلت، GPL-3.0-or-later را اعلام کرده و در متن مجوز آن محدودیتی درباره استفاده از نام/القای وابستگی به پروژه اصلی بدون اجازه قبلی دیده می‌شود. این موضوع برای بسته‌بندی محصول تجاری، انتشار source متناظر، وابستگی‌ها و برند باید بررسی حقوقی شود.
- مخزن رسمی Xray-core در زمان تهیه این اسکلت MPL-2.0 را اعلام کرده است. MPL نیز تعهدات مشخصی برای فایل‌های تحت پوشش و تغییرات آن‌ها دارد؛ آن را مجوز بدون تعهد فرض نکنید.
- مجوز کل برنامه Flutter، روش linking/bundling، کتابخانه‌های واسط، dependency tree، build scripts، binary notices و شرایط فروشگاه‌های Apple/Google باید با هم بررسی شوند.

منابع رسمی برای بازبینی:

- sing-box: https://github.com/SagerNet/sing-box
- sing-box build docs: https://sing-box.sagernet.org/installation/build-from-source/
- Xray-core: https://github.com/XTLS/Xray-core
- Flutter supported platforms: https://docs.flutter.dev/reference/supported-platforms
- Apple Packet Tunnel Provider: https://developer.apple.com/documentation/networkextension/packet-tunnel-provider

## جدول ارزیابی اجباری

برای هر پروفایل نمونه، موارد زیر جدا ثبت شود:

| Feature | sing-box Android | sing-box Windows | Xray Android | Xray Windows | یادداشت |
|---|---|---|---|---|---|
| VLESS basic | Pending | Pending | Pending | Pending |  |
| VLESS + Reality + Vision | Pending | Pending | Pending | Pending | پارامترهای دقیق ثبت شوند |
| VMess | Pending | Pending | Pending | Pending | نوع security و transport مهم است |
| Trojan | Pending | Pending | Pending | Pending |  |
| Shadowsocks | Pending | Pending | Pending | Pending | cipher باید بررسی شود |
| Hysteria2 | Pending | Pending | Pending | Pending | وجود parser به معنی engine support نیست |
| DNS strategy | Pending | Pending | Pending | Pending | DNS leak test لازم است |
| IPv6 routing | Pending | Pending | Pending | Pending |  |
| Subscription refresh | App layer | App layer | App layer | App layer | engine-specific نیست مگر قالب خاص باشد |

Status فقط یکی از این مقادیر باشد: `Pass`, `Partial`, `Fail`, `Not tested`, `Not applicable`.

## سؤالات فنی که باید پاسخ داده شوند

1. آیا هر Core برای پلتفرم مقصد API library پایدار و نگهداری‌شده دارد؟
2. فرآیند start/stop، log stream، crash و update چگونه انجام می‌شود؟
3. کدام قابلیت‌ها در نسخه موبایل و دسکتاپ تفاوت دارند؟
4. آیا Hysteria2 موردنیاز X-Net با پارامترهای واقعی اجرا می‌شود؟
5. در پروفایل‌های Reality، flow، fingerprint، SNI، ALPN و transport عیناً حفظ می‌شوند؟
6. آیا بسته‌بندی دو Core حجم، پیچیدگی و سطح حمله را بی‌دلیل بالا می‌برد؟
7. هر Engine چه الزاماتی برای انتشار سورس، notices و علامت/نام دارد؟

## قانون تصمیم

تا پایان فاز P2، وابستگی Engine وارد برنامه انتشارپذیر نشود. ابتدا POC مستقل، گزارش سازگاری، SBOM و بازبینی مجوز. ممکن است نتیجه درست برای MVP استفاده از یک Engine باشد و Engine دوم بعداً اضافه شود.
