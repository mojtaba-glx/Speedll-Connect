# معماری Speedll Connect

## اصول

1. رابط کاربری (Flutter UI) و موتور اتصال (VPN Engine) کاملاً مستقل‌اند.
2. هیچ کدی از Coreها نباید مستقیماً وارد ویجت‌های فلاتر شود.
3. مدیریت وضعیت رابط کاربری با الگوی واکنشی Riverpod پیاده‌سازی می‌شود.
4. ماژول اشتراک به صورت یک پکیج مجزا (`packages/speedll_subscription`) از UI تفکیک شده است.
5. پروفایل‌ها دارای `schemaVersion` بوده و از طریق لایه Migration ارتقا می‌یابند.
6. برای نسخه MVP، استراتژی تک‌موتوره مبتنی بر sing-box به کار گرفته می‌شود تا پیچیدگی به حداقل برسد.
7. کدهای بومی پلتفرم‌ها در ساختار رسمی Flutter در `app/` قرار دارند و پوشه `platform/` در ریشه صرفاً حاوی اسناد و مشخصات فنی است.

## نمای منطقی

```text
Flutter UI (Presentation Layer)
   │
   ▼
Application Layer (Riverpod Controllers)
   ├── ConnectionController (Status, Uptime, Actions)
   ├── ThemeController (Light / Dark / System)
   └── ProfileManager (Active Profile, List)
          │
          ▼
Domain Contracts (App) & Packages
   ├── speedll_subscription Package (Models with schemaVersion, Migration, Parsers, Validators)
   ├── ConnectionEngine Interface (inspectProfile, connect, disconnect, connectionPhases)
   └── EngineCapabilityReport
          │
          ▼
Engine Adapter Layer (Isolated)
   └── sing-box Adapter (MVP candidate)
          │
          ▼
Native Platform Integration (Standard app/<platform>)
   ├── Android: VpnService
   ├── Windows: TUN + Service
   ├── Linux: TUN + network integration
   ├── macOS: Network Extension
   └── iOS: Packet Tunnel Provider
```

## مدیریت وضعیت (State Management)

- استفاده از `flutter_riverpod` به عنوان استاندارد مدیریت وضعیت برای پشتیبانی از حالت‌های تست‌پذیر و واکنشی بدون ایجاد وابستگی متقابل در ویجت‌ها.
- جداسازی ویجت‌های نمایشی از کنترلرها در لایه‌های مجزا.

## ماژول مستقل اشتراک (`speedll_subscription`)

پایپ‌لاین مدیریت اشتراک:
`Input URI/Raw → SubscriptionParser → Raw Map → ProfileMigrator → ServerProfile (schemaVersion) → ProfileValidator → EngineCapabilityInspection → Secure Storage`
