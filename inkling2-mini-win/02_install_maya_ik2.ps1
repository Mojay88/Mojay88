<#
.SYNOPSIS
  Track A Installer: Builds alesha-pro/maya-inkling-mini (maya-ik2) natively on Windows 11 for RTX 3090 (sm_86),
  downloads the exact compatible Unsloth Old_Support UD-Q4_K_XL GGUF (fixing Issue #15) + Thinking Machines DSpark drafter,
  generates the tokenizer, and writes a Windows-tuned 24GB config (max-context 131072, FP8 KV, resident=1).
#>
[CmdletBinding()]
param(
    [string]$EngineRoot = "D:\mojay-engines",
    [string]$ModelDir = "D:\ai-models\inkling-2-mini",
    [string]$CudaArch = "86",
    [int]$MaxContext = 131072,
    [int]$BuildJobs = 16,
    [switch]$SkipVisionDownload
)

$ErrorActionPreference = "Stop"

function Import-VsDevEnv {
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vswhere)) {
        throw "Visual Studio Build Tools (vswhere.exe) not found. Install VS 2022 Build Tools with C++ x64 tools, or use .\03_install_unsloth_llamacpp.ps1."
    }
    $vsPath = & $vswhere -latest -prerelease -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (-not $vsPath) {
        throw "MSVC C++ x64 build tools not found in Visual Studio installation."
    }
    $vcvars = Join-Path $vsPath "VC\Auxiliary\Build\vcvars64.bat"
    if (-not (Test-Path $vcvars)) {
        throw "vcvars64.bat not found at $vcvars"
    }
    Write-Host "[1/6] Loading MSVC x64 environment from $vsPath ..." -ForegroundColor Cyan
    $envLines = cmd /c "`"$vcvars`" >nul 2>&1 && set"
    foreach ($line in $envLines) {
        if ($line -match "^([^=]+)=(.*)$") {
            [System.Environment]::SetEnvironmentVariable($matches[1], $matches[2], "Process")
        }
    }
}

function Find-CudaRoot {
    if ($env:CUDA_PATH -and (Test-Path (Join-Path $env:CUDA_PATH "bin\nvcc.exe"))) {
        return $env:CUDA_PATH
    }
    $candidates = Get-ChildItem "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v*" -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending
    foreach ($dir in $candidates) {
        if (Test-Path (Join-Path $dir.FullName "bin\nvcc.exe")) {
            return $dir.FullName
        }
    }
    throw "CUDA Toolkit (nvcc.exe) not found. Install CUDA Toolkit 12.8 (Custom install -> uncheck Display Driver), or use .\03_install_unsloth_llamacpp.ps1."
}

New-Item -ItemType Directory -Force -Path $EngineRoot, $ModelDir, (Join-Path $ModelDir "logs") | Out-Null

# 1. Load MSVC & locate CUDA
Import-VsDevEnv
$cudaRoot = Find-CudaRoot
$nvccExe = Join-Path $cudaRoot "bin\nvcc.exe"
Write-Host "Using CUDA Toolkit: $cudaRoot" -ForegroundColor Green

# 2. Clone or update maya-inkling-mini
$repoDir = Join-Path $EngineRoot "maya-inkling-mini"
Write-Host "[2/6] Fetching alesha-pro/maya-inkling-mini ..." -ForegroundColor Cyan
if (-not (Test-Path (Join-Path $repoDir ".git"))) {
    git clone https://github.com/alesha-pro/maya-inkling-mini.git $repoDir
} else {
    git -C $repoDir pull --ff-only
}
Set-Location $repoDir

# 3. Python virtual environment + dependencies
Write-Host "[3/6] Setting up Python venv & dependencies ..." -ForegroundColor Cyan
$venvDir = Join-Path $repoDir ".venv"
$venvPy = Join-Path $venvDir "Scripts\python.exe"
$venvPip = Join-Path $venvDir "Scripts\pip.exe"
$venvScripts = Join-Path $venvDir "Scripts"
if (-not (Test-Path $venvPy)) {
    python -m venv $venvDir
}
& $venvPip install -U pip wheel
& $venvPip install -U numpy jinja2 regex pyyaml tqdm requests pillow psutil "jsonschema>=4.18,<5" huggingface_hub cmake ninja
$env:PATH = "$venvScripts;$env:PATH"

# 4. Build maya-ik2.exe
Write-Host "[4/6] Building maya-ik2.exe for sm_$CudaArch (CUDA_ARCHITECTURES=$CudaArch) ..." -ForegroundColor Cyan
$cudaRootCmake = $cudaRoot -replace '\\', '/'
$nvccCmake = $nvccExe -replace '\\', '/'
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release `
    -DSTRATA_ENABLE_CUDA=ON `
    "-DCMAKE_CUDA_ARCHITECTURES=$CudaArch" `
    "-DCUDAToolkit_ROOT=$cudaRootCmake" `
    "-DCMAKE_CUDA_COMPILER=$nvccCmake" `
    -DSTRATA_NATIVE_EXPERTS=OFF `
    -DSTRATA_BUILD_TESTS=OFF

cmake --build build -j $BuildJobs --target maya-ik2

$mayaExe = Join-Path $repoDir "build\maya-ik2.exe"
if (-not (Test-Path $mayaExe)) {
    throw "Build finished but maya-ik2.exe not found at $mayaExe"
}
Write-Host "Built successfully: $mayaExe" -ForegroundColor Green

# 5. Download compatible GGUF (Old_Support per Issue #15) + Drafter + optional mmproj
Write-Host "[5/6] Downloading Inkling 2 Mini weights + official DSpark drafter to $ModelDir ..." -ForegroundColor Cyan
$hfExe = Join-Path $venvScripts "hf.exe"
$finalModel = Join-Path $ModelDir "Inkling-2-Mini-UD-Q4_K_XL.gguf"

if (-not (Test-Path $finalModel) -or (Get-Item $finalModel).Length -lt 16GB) {
    $oldSupportRel = "Old_Support/Inkling-2-Mini-UD-Q4_K_XL.gguf_file"
    Write-Host "Downloading $oldSupportRel (maya-ik2 compatible NVFP4 layout) ..." -ForegroundColor Yellow
    & $hfExe download unsloth/Inkling-2-Mini-GGUF $oldSupportRel --local-dir $ModelDir
    $downloadedOld = Join-Path $ModelDir "Old_Support\Inkling-2-Mini-UD-Q4_K_XL.gguf_file"
    if (-not (Test-Path $downloadedOld)) {
        throw "Expected downloaded file not found at $downloadedOld"
    }
    Move-Item -Force $downloadedOld $finalModel
} else {
    Write-Host "Model already present: $finalModel" -ForegroundColor Green
}

if (-not $SkipVisionDownload) {
    $mmprojFile = Join-Path $ModelDir "mmproj-BF16.gguf"
    if (-not (Test-Path $mmprojFile)) {
        & $hfExe download unsloth/Inkling-2-Mini-GGUF mmproj-BF16.gguf --local-dir $ModelDir
    }
}

$drafterFile = Join-Path $ModelDir "mtp.safetensors"
if (-not (Test-Path $drafterFile) -or (Get-Item $drafterFile).Length -lt 500MB) {
    Write-Host "Downloading official Thinking Machines mtp.safetensors (636 MB) ..." -ForegroundColor Yellow
    & $hfExe download thinkingmachines/Inkling-2-Mini mtp.safetensors --local-dir $ModelDir
} else {
    Write-Host "Drafter already present: $drafterFile" -ForegroundColor Green
}

# 6. Extract tokenizer & write Windows-tuned config JSON
Write-Host "[6/6] Extracting tokenizer & writing Windows 11 24GB config ..." -ForegroundColor Cyan
$tokOut = Join-Path $ModelDir "ik2"
& $venvPy tools\strata_tokenizer.py `
    --gguf $finalModel `
    --out $tokOut `
    --chat-template tools\ik2\chat_template.jinja `
    --check

$cfgPath = Join-Path $ModelDir "ik2-mini-win3090.json"
$cfgObj = [ordered]@{
    exe = ($mayaExe -replace '\\', '/')
    args = @(
        "--model", ($finalModel -replace '\\', '/'),
        "--max-context", "$MaxContext",
        "--draft", ($drafterFile -replace '\\', '/')
    )
    env = [ordered]@{
        CUDA_DEVICE_ORDER = "PCI_BUS_ID"
        CUDA_VISIBLE_DEVICES = "0"
        IK2_KV = "fp8"
        IK2_GATE_TILE = "64"
        IK2_GATE_BF16 = "1"
        IK2_Q8_UNROLL = "1"
        IK2_BATCH_PREFILL = "1"
        IK2_DRAFT_CTX = "65536"
    }
    tokenizer = ((Join-Path $tokOut "tokenizer") -replace '\\', '/')
    model_name = "inkling-2-mini"
}
$cfgObj | ConvertTo-Json -Depth 5 | Set-Content -Path $cfgPath -Encoding UTF8

Write-Host "`n[DONE] Track A (maya-ik2) is built and configured!" -ForegroundColor Green
Write-Host "Config: $cfgPath" -ForegroundColor White
Write-Host "Next step: .\04_start_inkling.ps1 -Engine maya" -ForegroundColor Cyan
