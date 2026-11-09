# برنامه تست و تضمین کیفیت

## دسته‌های تست

### Unit
- parser هر URI و JSON
- normalizer و serializer
- capability detection
- انتخاب Engine
- status transition و reconnect policy
- redact کردن log و خطا

### Integration
- Flutter ↔ Native bridge
- Flutter ↔ Engine Adapter
- Engine ↔ TUN/VpnService/Packet Tunnel
- Subscription fetch ↔ Parser
- App ↔ Speedll API

### Network
- DNS leak و DNS fallback
- IPv4/IPv6 route
- Wi-Fi ↔ mobile data
- captive portal
- offline / server unavailable
- packet loss / latency variation
- sleep/resume و reconnect

### Security
- ورودی مخرب و parser fuzzing
- SSRF و redirect policy
- secure storage
- log redaction
- TLS validation
- tampered update / binary integrity

### UX / Accessibility
- متن و دکمه بزرگ
- contrast روشن/تاریک
- TalkBack و VoiceOver
- keyboard navigation دسکتاپ
- RTL و فونت فارسی
- پیام‌های قابل درک برای فرد غیرمتخصص
- سنجش usability با کاربران مبتدی و سالمند

## تست‌های انتشار بحرانی

هیچ release عمومی بدون Pass شدن موارد زیر منتشر نشود:

- [ ] اتصال واقعی و disconnect واقعی روی OS مقصد
- [ ] پس از disconnect، route و VPN permission state صحیح باقی بماند
- [ ] قطع API حساب باعث قطع اتصال فعال نشود
- [ ] هیچ secret در log/crash report وجود نداشته باشد
- [ ] DNS و IPv6 leak test Pass باشد
- [ ] تغییر شبکه و sleep/resume رفتار قابل پیش‌بینی داشته باشد
- [ ] parser ورودی خراب را رد کند و app crash نکند
- [ ] Engine failure پیام قابل فهم بدهد و reconnect loop ایجاد نکند
- [ ] privacy disclosure و permission disclosure کامل باشد

## قالب ثبت تست

```text
Test ID:
Date/time:
App commit:
OS + version:
Device / architecture:
Engine + version + build flags:
Profile fixture ID (sanitized):
Steps:
Expected:
Actual:
Result: Pass / Partial / Fail
Logs (sanitized):
Known limitations:
Tester:
```
