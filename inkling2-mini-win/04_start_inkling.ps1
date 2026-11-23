<#
.SYNOPSIS
  Safe launcher for Inkling 2 Mini on GPU0 (RTX 3090 24GB) with automatic GPU0 port conflict release,
  strict GPU0 pinning (never touches GPU1), Unbiased Bob's optimal sampling/reasoning defaults,
  resident=1 verification, and live smoke test.
#>
[CmdletBinding()]
param(
    [ValidateSet("auto", "maya", "unsloth")]
    [string]$Engine = "auto",
    [string]$EngineRoot = "D:\mojay-engines",
    [string]$MayaModelDir = "D:\ai-models\inkling-2-mini",
    [string]$UnslothModelDir = "D:\ai-models\inkling-2-mini-mainline",
    [string]$UnslothReleaseTag = "b12649-mix-c7059d6",
    [string]$HostAddr = "0.0.0.0",
    [int]$Port = 8094,
    [int]$MaxContext = 131072,
    [int]$StopConflictPort = 8092,
    [switch]$KeepConflictPort,
    [switch]$SkipSmokeTest
)

$ErrorActionPreference = "Stop"

# Auto-detect installed engine (prefer maya-ik2 for 130-210 tok/s)
$mayaExe = Join-Path $EngineRoot "maya-inkling-mini\build\maya-ik2.exe"
$mayaCfg = Join-Path $MayaModelDir "ik2-mini-win3090.json"
$unslothExe = Join-Path $EngineRoot "llamacpp-unsloth-$UnslothReleaseTag\llama-server.exe"
$unslothModel = Join-Path $UnslothModelDir "Inkling-2-Mini-UD-Q4_K_XL.gguf"

if ($Engine -eq "auto") {
    if ((Test-Path $mayaExe) -and (Test-Path $mayaCfg)) {
        $Engine = "maya"
    } elseif ((Test-Path $unslothExe) -and (Test-Path $unslothModel)) {
        $Engine = "unsloth"
    } else {
        throw "No Inkling 2 Mini installation found. Run .\02_install_maya_ik2.ps1 or .\03_install_unsloth_llamacpp.ps1 first."
    }
}

Write-Host "`n=== Launching Inkling 2 Mini (Engine: $Engine, Port: $Port) ===" -ForegroundColor Cyan

# 1. Stop any prior Inkling server on $Port
Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { ($_.Name -in @("python.exe", "llama-server.exe", "maya-ik2.exe")) -and ($_.CommandLine -match "--port\s+$Port\b") } |
    ForEach-Object {
        Write-Host "Stopping previous Inkling process PID=$($_.ProcessId) on port $Port ..." -ForegroundColor Yellow
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }

# 2. Safely release GPU0 conflict port (default 8092) without touching GPU1
if (-not $KeepConflictPort -and $StopConflictPort -gt 0) {
    $conflicts = Get-CimInstance Win32_Process -Filter "Name='llama-server.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match "--port\s+$StopConflictPort\b" }
    foreach ($p in $conflicts) {
        Write-Host "Temporarily stopping GPU0 service PID=$($p.ProcessId) on port $StopConflictPort (use .\05_rollback_to_finance.ps1 to restore) ..." -ForegroundColor Yellow
        Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
    }
    if ($conflicts) { Start-Sleep -Seconds 3 }
}

# Verify GPU0 free VRAM
$vramFree = & nvidia-smi --id=0 --query-gpu=memory.free --format=csv,noheader,nounits
Write-Host "GPU0 free VRAM: $vramFree MiB" -ForegroundColor Cyan
if ([int]$vramFree -lt 20500) {
    Write-Warning "GPU0 has less than 20,500 MiB free ($vramFree MiB). Ensure no other process is using GPU0 or lower -MaxContext."
}

# Pin strictly to GPU0
$env:CUDA_DEVICE_ORDER = "PCI_BUS_ID"
$env:CUDA_VISIBLE_DEVICES = "0"

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"

if ($Engine -eq "maya") {
    $repoDir = Join-Path $EngineRoot "maya-inkling-mini"
    $venvPy = Join-Path $repoDir ".venv\Scripts\python.exe"
    $logDir = Join-Path $MayaModelDir "logs"
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $outLog = Join-Path $logDir "maya_ik2_$stamp.out.log"
    $errLog = Join-Path $logDir "maya_ik2_$stamp.err.log"

    # Update --max-context in JSON if overridden
    $cfg = Get-Content $mayaCfg -Raw | ConvertFrom-Json
    for ($i = 0; $i -lt $cfg.args.Count - 1; $i++) {
        if ($cfg.args[$i] -eq "--max-context") { $cfg.args[$i + 1] = "$MaxContext" }
    }
    $cfg | ConvertTo-Json -Depth 5 | Set-Content -Path $mayaCfg -Encoding UTF8

    $proc = Start-Process -FilePath $venvPy `
        -ArgumentList @("serve/server.py", "--engine", "maya", "--config", $mayaCfg, "--host", $HostAddr, "--port", "$Port") `
        -WorkingDirectory $repoDir `
        -RedirectStandardOutput $outLog `
        -RedirectStandardError $errLog `
        -PassThru
} else {
    $logDir = Join-Path $UnslothModelDir "logs"
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $outLog = Join-Path $logDir "unsloth_ik2_$stamp.out.log"
    $errLog = Join-Path $logDir "unsloth_ik2_$stamp.err.log"

    $args = @(
        "--model", $unslothModel,
        "-ngl", "99",
        "-fa", "on",
        "-c", "$MaxContext",
        "-ctk", "q8_0",
        "-ctv", "q8_0",
        "--temp", "1.0",
        "--top-p", "1.0",
        "--top-k", "0",
        "--min-p", "0.0",
        "--chat-template-kwargs", '{\"reasoning_effort\":\"minimal\"}',
        "--alias", "inkling-2-mini",
        "--host", $HostAddr,
        "--port", "$Port"
    )
    $mmproj = Join-Path $UnslothModelDir "mmproj-F16.gguf"
    if (Test-Path $mmproj) { $args += @("--mmproj", $mmproj) }
    $drafter = Join-Path $UnslothModelDir "dspark-Inkling-2-Mini-Q8_0.gguf"
    if (Test-Path $drafter) {
        $args += @("--model-draft", $drafter, "--spec-type", "draft-dspark", "--spec-draft-n-max", "2", "--n-gpu-layers-draft", "99")
    }

    $proc = Start-Process -FilePath $unslothExe `
        -ArgumentList $args `
        -WorkingDirectory (Split-Path $unslothExe) `
        -RedirectStandardOutput $outLog `
        -RedirectStandardError $errLog `
        -PassThru
}

Write-Host "Started PID=$($proc.Id). Logs: $outLog" -ForegroundColor Gray

# 3. Wait for /health == 200
$ready = $false
for ($i = 1; $i -le 45; $i++) {
    if ($proc.HasExited) {
        Write-Host "`nServer exited early! Last stderr lines:" -ForegroundColor Red
        Get-Content $errLog -Tail 30 -ErrorAction SilentlyContinue
        throw "Server failed to start (exit code $($proc.ExitCode))."
    }
    try {
        $resp = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/health" -UseBasicParsing -TimeoutSec 2
        if ($resp.StatusCode -eq 200) {
            $ready = $true
            break
        }
    } catch { }
    Start-Sleep -Seconds 2
}

if (-not $ready) {
    throw "Timed out waiting for http://127.0.0.1:$Port/health. Check $errLog"
}
Write-Host "[PASS] Health endpoint HTTP 200 at http://127.0.0.1:$Port/health" -ForegroundColor Green

# 4. Verify resident=1 on maya-ik2
if ($Engine -eq "maya") {
    try {
        $report = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/api/report" -TimeoutSec 5
        $reportJson = $report | ConvertTo-Json -Compress -Depth 4
        $logHit = $false
        try {
            $logHit = [bool](Select-String -Path $errLog,$outLog -Pattern "resident=1|every expert in VRAM" -Quiet -ErrorAction SilentlyContinue)
        } catch { }
        if ($reportJson -match '"resident"\s*:\s*(1|true)' -or $logHit) {
            Write-Host "[PASS] VRAM Resident Check: EVERY EXPERT IN VRAM (resident=1)" -ForegroundColor Green
        } else {
            Write-Warning "Could not confirm resident=1! Check logs ($errLog) and lower -MaxContext (e.g., 98304) if experts spilled to RAM."
        }
    } catch {
        Write-Warning "Could not query /api/report: $_"
    }
}

# 5. Live Smoke Test with Unbiased Bob's winning settings (reasoning_effort=minimal / 0.1)
if (-not $SkipSmokeTest) {
    Write-Host "Running live smoke test (reasoning_effort=minimal, temp=1.0, top_p=1.0, top_k=0, min_p=0.0) ..." -ForegroundColor Cyan
    $payload = @{
        model = "inkling-2-mini"
        temperature = 1.0
        top_p = 1.0
        top_k = 0
        min_p = 0.0
        reasoning_effort = "minimal"
        max_tokens = 256
        messages = @(
            @{ role = "user"; content = "What is 17 * 19? Reply with the exact number and a 3-line Python function is_prime(n)." }
        )
    } | ConvertTo-Json -Depth 5

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $res = Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:$Port/v1/chat/completions" `
        -ContentType "application/json" -Body $payload -TimeoutSec 60
    $sw.Stop()

    $text = $res.choices[0].message.content
    $compTok = $res.usage.completion_tokens
    $tps = if ($compTok -and $sw.Elapsed.TotalSeconds -gt 0) { [math]::Round($compTok / $sw.Elapsed.TotalSeconds, 1) } else { "n/a" }

    Write-Host "`n--- Smoke Test Output ($compTok tokens in $([math]::Round($sw.Elapsed.TotalSeconds,2))s ~ $tps tok/s) ---" -ForegroundColor Cyan
    Write-Host $text
    if ($text -match "323") {
        Write-Host "`n[PASS] Golden math gate (17*19=323) PASSED!" -ForegroundColor Green
    } else {
        Write-Warning "Golden math gate did not find '323' in final content (check reasoning_content)."
    }
}

Write-Host "`nEndpoint Ready: http://127.0.0.1:$Port/v1 (model: inkling-2-mini)" -ForegroundColor Green
Write-Host "To rollback to finance :8092 anytime, run: .\05_rollback_to_finance.ps1`n" -ForegroundColor Gray
