<#
.SYNOPSIS
  Track B Installer (Zero-Compile, ~5 minutes): Downloads Unsloth's optimized Windows llama.cpp build
  (b12649-mix-c7059d6, CUDA 12 portable - works directly with NVIDIA Driver 580.88) plus the root
  mainline UD-Q4_K_XL GGUF, F16 vision projector, and Q8_0 DSpark drafter.
#>
[CmdletBinding()]
param(
    [string]$EngineRoot = "D:\mojay-engines",
    [string]$ModelDir = "D:\ai-models\inkling-2-mini-mainline",
    [ValidateSet("12", "13")]
    [string]$CudaVersion = "12",
    [string]$ReleaseTag = "b12649-mix-c7059d6",
    [switch]$SkipVisionDownload
)

$ErrorActionPreference = "Stop"

$engineDir = Join-Path $EngineRoot "llamacpp-unsloth-$ReleaseTag"
New-Item -ItemType Directory -Force -Path $engineDir, $ModelDir, (Join-Path $ModelDir "logs") | Out-Null

# 1. Download & extract prebuilt Windows llama.cpp
$assetName = "app-$ReleaseTag-windows-x64-cuda$CudaVersion-portable.zip"
$zipUrl = "https://github.com/unslothai/llama.cpp/releases/download/$ReleaseTag/$assetName"
$zipPath = Join-Path $EngineRoot $assetName
$serverExe = Join-Path $engineDir "llama-server.exe"

if (-not (Test-Path $serverExe)) {
    Write-Host "[1/3] Downloading $assetName ..." -ForegroundColor Cyan
    curl.exe -L --fail --retry 3 -o $zipPath $zipUrl
    Write-Host "Extracting to $engineDir ..." -ForegroundColor Cyan
    Expand-Archive -Force -Path $zipPath -DestinationPath $engineDir
    Remove-Item -Force $zipPath -ErrorAction SilentlyContinue
} else {
    Write-Host "[1/3] Prebuilt llama-server.exe already present: $serverExe" -ForegroundColor Green
}

& $serverExe --version

# 2. Ensure huggingface_hub CLI (hf) is available
Write-Host "[2/3] Checking huggingface_hub CLI ..." -ForegroundColor Cyan
$hfCmd = Get-Command hf -ErrorAction SilentlyContinue
if (-not $hfCmd) {
    python -m pip install -U huggingface_hub
    $hfCmd = Get-Command hf -ErrorAction SilentlyContinue
}
$hfExe = if ($hfCmd) { $hfCmd.Source } else { "hf" }

# 3. Download root mainline GGUF + DSpark Q8_0 drafter + optional vision projector
Write-Host "[3/3] Downloading Inkling-2-Mini-UD-Q4_K_XL.gguf + dspark drafter to $ModelDir ..." -ForegroundColor Cyan
$files = @(
    "Inkling-2-Mini-UD-Q4_K_XL.gguf",
    "dspark-Inkling-2-Mini-Q8_0.gguf"
)
if (-not $SkipVisionDownload) {
    $files += "mmproj-F16.gguf"
}

& $hfExe download unsloth/Inkling-2-Mini-GGUF @files --local-dir $ModelDir

$modelFile = Join-Path $ModelDir "Inkling-2-Mini-UD-Q4_K_XL.gguf"
if (-not (Test-Path $modelFile) -or (Get-Item $modelFile).Length -lt 16GB) {
    throw "Download verification failed for $modelFile"
}

Write-Host "`n[DONE] Track B (Unsloth llama.cpp $ReleaseTag) is ready!" -ForegroundColor Green
Write-Host "Engine: $serverExe" -ForegroundColor White
Write-Host "Model : $modelFile" -ForegroundColor White
Write-Host "Next step: .\04_start_inkling.ps1 -Engine unsloth" -ForegroundColor Cyan
