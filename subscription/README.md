# Subscription Pipeline

ساختار موردنظر:

```text
Input
  → Source detector
  → Parser
  → Raw model
  → Validator
  → Normalized profile
  → Engine capability inspection
  → Secure secret storage
```

Parser فقط ساختار ورودی را تشخیص می‌دهد؛ تضمین اتصال نیست. در فاز P4 برای هر فرمت تست مثبت، منفی، malformed، oversized و fuzz اضافه شود.
