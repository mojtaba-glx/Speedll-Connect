# Speedll Account API

Backend فقط برای account/control plane است. در حال حاضر هیچ کد سروری وجود ندارد؛ قرارداد اولیه در `docs/API_CONTRACT_DRAFT_FA.md` است.

اصول:
- API مستقل از SellBot production و دیتابیس پنل
- pairing کوتاه‌عمر و یک‌بارمصرف
- مجوز دسترسی سمت سرور
- secretهای کوتاه‌عمر و قابل revoke
- قطع API نباید تونل فعال را متوقف کند
- API نباید ترافیک VPN را حمل کند
