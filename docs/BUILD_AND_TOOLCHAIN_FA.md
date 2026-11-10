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

# بیلد APK اندروید
flutter build apk --debug
```
