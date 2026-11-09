# معماری پیشنهادی Speedll Connect

## اصول

1. UI و Engine مستقل‌اند.
2. هیچ Core نباید مستقیماً در Widgetهای Flutter استفاده شود.
3. اتصال VPN به API حساب Speedll وابسته نیست.
4. هر پروفایل قبل از اجرا parse، normalize و validate می‌شود.
5. انتخاب Core براساس feature-level compatibility است، نه صرفاً نام protocol.
6. هر OS یک adapter بومی و lifecycle مشخص دارد.

## نمای منطقی

```text
Flutter UI
   │
   ▼
Application / Use Cases
   ├── Connection Manager
   ├── Profile Manager
   ├── Subscription Manager
   ├── Theme / Localization / Accessibility
   └── Speedll Account Client (optional)
          │
          ▼
Domain Contracts
   ├── Normalized Profile
   ├── Engine Capability Report
   ├── Connection Engine interface
   └── Native VPN Adapter interface
          │
          ▼
Engine Adapter Layer
   ├── sing-box Adapter (candidate)
   └── Xray Adapter (candidate)
          │
          ▼
Native Platform Integration
   ├── Android: VpnService + supported engine bridge
   ├── iOS: Network Extension / Packet Tunnel Provider
   ├── Windows: service + TUN integration
   ├── macOS: approved Network Extension / system integration
   └── Linux: TUN + capabilities/service
          │
          ▼
Remote VPN endpoints

Separate control plane:
SellBot / Speedll systems ⇄ Speedll Account API ⇄ App
```

## اجزای مسئولیت‌دار

### Flutter UI

نمایش وضعیت واقعی، سرورها، اشتراک، onboarding، theme، language و پیام‌ها. UI نباید اسرار را parse یا در log چاپ کند.

### Application layer

سناریوهای کاربر مانند Connect، Disconnect، Import Subscription، Select Server و Refresh Subscription را اجرا می‌کند. این لایه engine-specific نیست.

### Subscription pipeline

`Input → Parser → Raw Model → Validator → Normalizer → Capability Check → Secure Store`

Parser باید اطلاعات ناشناخته را حفظ یا صریحاً گزارش کند؛ حذف بی‌صدای تنظیمات TLS، Reality، transport یا routing ممنوع است.

### Connection Manager

- فقط یک نشست فعال برای هر app instance، مگر معماری OS خلاف آن را الزام کند.
- انتخاب Engine براساس capability report.
- timeout، cancellation، status stream و recovery policy.
- جلوگیری از reconnect loop و server flapping.
- تفکیک خطای permission، config، engine، network و server.

### Engine Adapter

برای هر Core یک Adapter مستقل. Adapter مسئول lifecycle، تبدیل کانفیگ نرمال‌شده به ساختار Engine، دریافت رویدادها و گزارش قابلیت است. تبدیل باید deterministic و تست‌پذیر باشد.

### Native VPN Adapter

مدیریت permission، ایجاد تونل، route/DNS، foreground/background lifecycle، stop و پاک‌سازی سیستم‌عامل. جزئیات و محدودیت هر OS باید مستقل مستند شود.

### Speedll Account API

فقط کنترل حساب و metadata اشتراک. نباید ترافیک کاربر را relay یا proxy کند. در قطع API، profile ذخیره‌شده و اتصال فعال نباید بی‌دلیل از کار بیفتد.

## مدل داده حداقلی

- `Profile`: شناسه داخلی، نام نمایشی، protocol، source، metadata کشور، reference به secret store، نسخه schema.
- `SecretRef`: شناسه امن محلی؛ نه UUID/Password خام در مدل UI.
- `Subscription`: منبع، زمان آخرین به‌روزرسانی، etag/hash، وضعیت sync، اطلاعات معتبر حجم/انقضا در صورت وجود.
- `ConnectionSession`: profileId، engineId، phase، timestamps، خطای sanitized.
- `CapabilityReport`: ویژگی‌های تشخیص‌داده‌شده، پشتیبانی‌شده، نامشخص و ردشده همراه دلیل.

## پیشنهاد فناوری

- UI: Flutter/Dart.
- هسته‌ها: ارزیابی sing-box و Xray-core؛ هیچ‌کدام قبل از فاز 1 و 2 تثبیت نشوند.
- bridge: روش رسمی و قابل نگهداری هر Engine؛ POC پیش از توسعه کامل.
- Backend: فعلاً اختیاری؛ در صورت نیاز API مستقل، پیاده‌سازی می‌تواند FastAPI باشد.
- Storage: secure storage بومی برای secrets و database محلی برای metadata غیرمحرمانه.

## محدودیت‌های پلتفرم

Flutter از نظر UI چندسکویی است؛ این به معنی وجود یک پیاده‌سازی VPN مشترک برای همه سیستم‌عامل‌ها نیست. هر پلتفرم entitlement، permission، lifecycle، installer و تست مستقل دارد. مستندات رسمی Flutter: https://docs.flutter.dev/reference/supported-platforms

برای Apple، Packet Tunnel Provider در Network Extension یک مسیر رسمی برای اپلیکیشن VPN بسته‌محور است: https://developer.apple.com/documentation/networkextension/packet-tunnel-provider
