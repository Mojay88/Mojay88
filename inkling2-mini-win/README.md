# Inkling 2 Mini — Exact Video Setup Kit (Windows 11 + RTX 3090 24GB)

حزمة مؤتمتة 100% تطبق **نفس إعداد فيديو Unbiased Bob حرفياً** على جهاز Windows 11 بكرت **RTX 3090 (24GB, `sm_86`)**:

- **المحرك:** `alesha-pro/maya-inkling-mini` (`maya-ik2.exe` — وليس `llama.cpp`) + `maya-vision.exe` على CPU (صفر استهلاك من VRAM).
- **الموديل:** `Inkling-2-Mini-UD-Q4_K_XL.gguf` (يسحب تلقائياً نسخة `Old_Support` المتوافقة مع `maya-ik2` بعد تعديل Unsloth بتاريخ 23 نوفمبر).
- **المُسرّع (Drafter):** `thinkingmachines/Inkling-2-Mini` → `mtp.safetensors` (DSpark الرسمي).
- **إعدادات الفيديو الحرفية:** `--max-context 131072` · `IK2_KV=fp8` · `IK2_GATE_TILE=64` · `IK2_GATE_BF16=1` · `IK2_Q8_UNROLL=1` · `IK2_BATCH_PREFILL=1` · `IK2_DRAFT_CTX=65536`.
- **الـ Sampling والتفكير:** `reasoning_effort = minimal (0.1)` · `temp 1.0` · `top_p 1.0` · `top_k 0` · `min_p 0.0`.
- **وكيل البرمجة:** `Pi` (`@earendil-works/pi-coding-agent`) مضبوط تلقائياً في `~/.pi/agent/models.json`.

---

## التشغيل بأمر واحد (PowerShell كمسؤول Administrator)

```powershell
.\RUN_ME_FIRST.ps1
```
*(أو دبل-كليك / Run as Administrator على `START_SETUP.bat`).*

### ماذا يفعل `RUN_ME_FIRST.ps1` بالترتيب؟
1. [`01_preflight_check.ps1`](01_preflight_check.ps1) — يفحص القرص `D:` وكرت الـ 3090 والتعريف والمنافذ.
2. [`00_install_prereqs_win.ps1`](00_install_prereqs_win.ps1) — يثبّت أي أداة ناقصة تلقائياً (Git، Python، VS 2022 C++ Build Tools، CUDA Toolkit 12.8 **بدون لمس تعريف الشاشة `580.88`**، وNode.js لـ Pi).
3. [`02_install_maya_ik2.ps1`](02_install_maya_ik2.ps1) — يبني `maya-ik2.exe` (`sm_86`) و`maya-vision.exe` (CPU)، وينزّل الأوزان + `mtp.safetensors` + `mmproj-BF16.gguf` + Tokenizer ويكتب `ik2-mini-win3090.json`.
4. [`06_setup_pi_harness.ps1`](06_setup_pi_harness.ps1) — يثبّت `Pi` ويربطه تلقائياً بالسيرفر المحلي `http://127.0.0.1:8094/v1`.
5. [`04_start_inkling.ps1`](04_start_inkling.ps1) — يعزل GPU0 فقط، يحرر `:8092` مؤقتاً دون لمس GPU1، يشغّل `maya-ik2` على `:8094`، يتحقق من `resident=1`، ويجري اختباراً حياً (`17*19=323`).

### العودة الفورية (Rollback) للخدمة السابقة على `:8092`
```powershell
.\05_rollback_to_finance.ps1
```
