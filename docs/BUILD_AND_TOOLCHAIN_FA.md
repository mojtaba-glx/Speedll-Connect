# محیط ساخت و ابزارها

## ثبت محیط توسعه واقعی

این جدول با نسخه‌های واقعی و تست‌شده روی سیستم توسعه ثبت شده است.

| ابزار | نسخه ثبت‌شده | وضعیت | یادداشت |
|---|---|---|---|
| OS توسعه | Ubuntu 24.04.5 LTS (WSL2 x86_64) | Active | هماهنگ با ویندوز میزبان |
| Flutter SDK | 3.24.5 (stable) | Active | مستقر در `~/.flutter-sdk` |
| Dart SDK | 3.5.4 (stable) | Active | همراه با پکیج منیجر و ابزار تست |
| Android SDK | 35.0.0 (Platform android-35) | Active | مستقر در `~/.android-sdk` |
| Android Build Tools | 35.0.0 / 34.0.0 | Active | لایسنس‌ها تماماً تأیید شدند |
| JDK | OpenJDK 17.0.21 (Temurin-17) | Active | مستقر در `~/.jdk` |
| Gradle | 8.9 | Active | استفاده از کش محلی |
| Android Gradle Plugin | 8.7.2 | Active | سازگار با جاوا ۱۷ و کاتلین ۲ |
| Kotlin | 2.0.21 | Active | تنظیم جاوای هدف ۱۷ |

## دستورات آزموده‌شده و فعال

```bash
# تست پکیج سابسکرپشن
cd packages/speedll_subscription
dart analyze
dart test

# تحلیل و تست اپلیکیشن فلاتر
cd app
flutter analyze
flutter test

# دریافت AAR بومی libbox (برای checkout تازه یا پس از پاک‌شدن فایل بزرگ)
cd ..
scripts/fetch_libbox_aar.sh

# بیلد APK اندروید
cd app
flutter build apk --debug
```

فایل `app/android/app/libs/libbox.aar` به دلیل حجم بیش از ۱۰۰ مگابایت در git نگهداری نمی‌شود؛ پیش از هر بیلد اندروید اسکریپت بالا باید یک بار اجرا شود.

## بیلد هسته بومی و مسیر استاندارد

APK اندروید با شناسه `app.speedll.connect` و با استفاده از هسته بومی libbox ساخته می‌شود:

```bash
cd app
flutter build apk --release
```

- مسیر قدیمی و پرمصرف legacy (`SpeedllVpnService`, `Tun2SocksBridge` و باینری‌های مجزای `jniLibs`) در نسخه ۱.۸.۰ به‌طور کامل حذف شده است.
- برای انجام تست‌های مقایسه‌ای باتری و ارزیابی تفاوت عملکرد، نسخه مبنا (Baseline) فایل `Speedll-Connect-v1.7.1.apk` در ریشه مخزن است.

## روش انتشار رسمی (Release Distribution)

برای کاهش چشم‌گیر حجم فایل نصبی، حذف معماری‌های غیرضروری (مانند x86/x86_64) و اعمال بهینه‌سازی R8/Proguard:

```bash
cd app
flutter build apk --release --split-per-abi
```

در صورت عدم پیکربندی `key.properties` برای بیلد تستی:
```bash
flutter build apk --release --split-per-abi -PallowDebugRelease=true
```
خروجی‌ها در مسیر `app/build/app/outputs/flutter-apk/` تولید می‌شوند:
- `app-arm64-v8a-release.apk`
- `app-armeabi-v7a-release.apk`
