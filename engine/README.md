# Engine Layer

این پوشه محل adapterها، build notes و ارزیابی Coreهاست. در نسخه فعلی هیچ Engine binary/source وارد نشده است.

ساختار پیشنهادی پس از POC:

```text
engine/
├── common/                 # contracts, errors, capability model
├── singbox/                # adapter و build metadata در صورت تصویب
├── xray/                   # adapter و build metadata در صورت تصویب
└── test_fixtures/          # فقط داده Sanitized
```

قبل از اضافه‌کردن کد upstream، commit/tag و مجوز دقیق را ثبت کنید.
