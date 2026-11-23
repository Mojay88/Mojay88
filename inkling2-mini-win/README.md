# Inkling 2 Mini — Windows 11 RTX 3090 (24GB) Deployment Kit

حزمة جاهزة ومؤتمتة لتنزيل وتشغيل **Inkling 2 Mini (`UD-Q4_K_XL`)** بأعلى سرعة وأمان كامل على جهاز Windows 11 بكرت **RTX 3090 (24GB, `sm_86`)** دون تعديل تعريف الشاشة أو التأثير على GPU1.

---

## الترتيب السريع (3 أوامر فقط في PowerShell)

```powershell
# 1) فحص العتاد والمساحة وبيئة البناء (قراءة فقط — آمن 100%)
.\01_preflight_check.ps1

# 2) اختر مسار التثبيت:
#    - المسار A (الأسرع — 130 إلى 210 tok/s مثل فيديو Unbiased Bob):
.\02_install_maya_ik2.ps1
#    - أو المسار B (تشغيل خلال 5 دقائق بدون Compile — 75 إلى 105 tok/s):
.\03_install_unsloth_llamacpp.ps1

# 3) تشغيل السيرفر على GPU0 (مع تحرير مؤقت آمن لمنفذ 8092 + فحص resident=1 + اختبار حي):
.\04_start_inkling.ps1 -Engine auto

# 4) العودة الفورية (Rollback) إلى الخدمة السابقة على 8092 في أي وقت:
.\05_rollback_to_finance.ps1
```

---

## لماذا هذه الإعدادات بالذات؟
- **`--max-context 131072` + `IK2_KV=fp8`:** على Windows 11 المساحة الفعلية الحرة في RTX 3090 هي ~22.5–22.8 GiB. السياق الافتراضي (`262144`) في `maya-ik2` يخرج من وضع `resident=1` وتهبط السرعة لـ ~38 tok/s، بينما `131072` يستهلك ~21.6 GiB ويُبقي كل الـ 3,072 expert داخل الـ VRAM بسرعة كاملة (`resident=1`).
- **إعداد التفكير (`reasoning_effort: minimal` / `0.1`):** الافتراضي (`high=0.9` أو `medium=0.7`) يجعل الموديل يهدر عشرات الآلاف من التوكنات. ضبطه على `minimal` (`0.1`) حقق **94.0% في 3.1 ساعات** في اختبار Unbiased Bob (مقابل 86.1% في 8.4 ساعات).
- **إعدادات الـ Sampling:** `temperature=1.0`, `top_p=1.0`, `top_k=0`, `min_p=0.0`.
- **معالجة نقل ملفات Unsloth (23 نوفمبر 2026):**
  - `02_install_maya_ik2.ps1` ينزّل تلقائياً `Old_Support/Inkling-2-Mini-UD-Q4_K_XL.gguf_file` المتوافق مع `maya-ik2` ويعيد تسميته + ينزّل `mtp.safetensors` من `thinkingmachines/Inkling-2-Mini`.
  - `03_install_unsloth_llamacpp.ps1` ينزّل النسخة الجديدة من الجذر `Inkling-2-Mini-UD-Q4_K_XL.gguf` + `dspark-Inkling-2-Mini-Q8_0.gguf` مع البناء الجاهز `b12649-mix-c7059d6` (CUDA 12 portable).
- **عزل GPU0 بالكامل:** كل السكربتات تفرض `CUDA_DEVICE_ORDER=PCI_BUS_ID` و`CUDA_VISIBLE_DEVICES=0` ولا تلمس GPU1 نهائياً.
