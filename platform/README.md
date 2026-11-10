# مستندات و الزامات بومی سیستم‌عامل‌ها (Native Platform Specifications)

## تفکیک مسئولیت و رفع دوگانگی معماری
این پوشه (`platform/`) صرفاً محل نگهداری مستندات معماری، چک‌لیست‌های امنیتی، نیازمندی‌های مجوز و الزامات اختصاصی هر سیستم‌عامل است. 

کدهای اجرایی و فایل‌های پروژه بومی هر سیستم‌عامل مستقیماً درون ساختار استاندارد Flutter در مسیر `app/` (مانند `app/android`، `app/windows`، `app/ios`، `app/macos` و `app/linux`) یا در قالب پلاگین‌های مستقل فلاتر قرار می‌گیرند. این جداسازی مانع از بروز تداخل و سردرگمی در نگهداری کدهای بیلد می‌شود.

- Android: `platform/android/README.md`
- iOS: `platform/ios/README.md`
- Windows: `platform/windows/README.md`
- macOS: `platform/macos/README.md`
- Linux: `platform/linux/README.md`
