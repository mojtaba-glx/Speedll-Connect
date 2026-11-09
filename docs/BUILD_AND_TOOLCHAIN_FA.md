# محیط ساخت و ابزارها

## ثبت محیط توسعه

این جدول باید با نسخه واقعی سیستم توسعه پر شود؛ از حدس‌زدن نسخه‌ها خودداری کنید.

| ابزار | نسخه ثبت‌شده | وضعیت |
|---|---|---|
| OS توسعه | TBD | Pending |
| Flutter | TBD | Pending |
| Dart | TBD | Pending |
| Android SDK | TBD | Pending |
| Android NDK | TBD | Pending |
| JDK | TBD | Pending |
| Xcode | TBD | فقط macOS |
| Go | TBD | پس از انتخاب bridge |
| CMake / Ninja | TBD | بر اساس نیاز platform |

## یادداشت پلتفرم

- Flutter deployment برای پنج سیستم‌عامل هدف UI را فراهم می‌کند، اما VPN tunnel integration و build toolchain برای هر OS مستقل است.
- توسعه/امضای iOS و macOS به محیط macOS و Xcode نیاز دارد.
- نسخه Flutter و حداقل OSها در شروع هر release باید براساس مستندات رسمی جاری قفل شوند.

## دستورات اولیه Flutter

```bash
cd app
flutter doctor -v
flutter pub get
flutter analyze
flutter test
```

خروجی `flutter doctor -v` را بدون مسیرهای خصوصی و اطلاعات حساس در گزارش محیط ثبت کنید.
