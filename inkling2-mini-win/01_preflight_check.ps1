<#
.SYNOPSIS
  Preflight check for Inkling 2 Mini on Windows 11 (RTX 3090 24GB).
  Read-only: inspects GPUs, VRAM, disk space, driver, CUDA Toolkit, VS Build Tools, Python, Git, and active port 8092.
#>
[CmdletBinding()]
param(
    [string]$ModelDrive = "D",
    [int]$ConflictPort = 8092
)

$ErrorActionPreference = "Continue"

function Write-Status($Label, $State, $Detail) {
    $color = switch ($State) {
        "PASS" { "Green" }
        "WARN" { "Yellow" }
        "FAIL" { "Red" }
        default { "Cyan" }
    }
    Write-Host ("[{0,-4}] {1,-26} {2}" -f $State, $Label, $Detail) -ForegroundColor $color
}

Write-Host "`n=== Inkling 2 Mini — Windows RTX 3090 Preflight Check ===`n" -ForegroundColor Cyan

# 1. Disk Space
$drive = Get-PSDrive -Name $ModelDrive -ErrorAction SilentlyContinue
if ($drive) {
    $freeGB = [math]::Round($drive.Free / 1GB, 1)
    if ($freeGB -ge 35) {
        Write-Status "Disk ${ModelDrive}:" "PASS" "${freeGB} GB free (need ~22 GB for model + drafter + build)"
    } elseif ($freeGB -ge 22) {
        Write-Status "Disk ${ModelDrive}:" "WARN" "${freeGB} GB free (tight; enough for 1 track only)"
    } else {
        Write-Status "Disk ${ModelDrive}:" "FAIL" "${freeGB} GB free (need at least 22 GB)"
    }
} else {
    Write-Status "Disk ${ModelDrive}:" "FAIL" "Drive ${ModelDrive}: not found. Pass -ModelDrive <letter>."
}

# 2. NVIDIA GPU & Driver
$nvsmi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
if ($nvsmi) {
    $gpuLines = & nvidia-smi --query-gpu=index,name,driver_version,memory.used,memory.free,memory.total --format=csv,noheader
    foreach ($line in $gpuLines) {
        Write-Status "GPU" "PASS" $line.Trim()
    }
    $gpu0 = ($gpuLines | Select-Object -First 1)
    if ($gpu0 -match "3090|4090|5090|A6000|6000") {
        Write-Status "24GB+ Ampere/Newer" "PASS" "GPU0 supports resident NVFP4/FP8 fast path (sm_86+)"
    } else {
        Write-Status "GPU0 Architecture" "WARN" "Verify GPU0 is >= 24GB Ampere (sm_86) or adjust -MaxContext"
    }
} else {
    Write-Status "nvidia-smi" "FAIL" "NVIDIA driver not detected on PATH"
}

# 3. Conflict Port (e.g., 8092 holding GPU0 VRAM)
$conflictProc = Get-CimInstance Win32_Process -Filter "Name='llama-server.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match "--port\s+$ConflictPort\b" }
if ($conflictProc) {
    Write-Status "Port $ConflictPort (GPU0)" "WARN" "Active PID=$($conflictProc.ProcessId). 04_start_inkling.ps1 can safely stop it and 05_rollback_to_finance.ps1 restores it."
} else {
    Write-Status "Port $ConflictPort (GPU0)" "PASS" "No llama-server holding port $ConflictPort right now"
}

# 4. Python & Git
$py = Get-Command python -ErrorAction SilentlyContinue
if ($py) {
    $pyVer = (& python --version 2>&1) -join " "
    Write-Status "Python" "PASS" "$pyVer ($($py.Source))"
} else {
    Write-Status "Python" "FAIL" "Python 3.10+ required (winget install Python.Python.3.12)"
}

$git = Get-Command git -ErrorAction SilentlyContinue
if ($git) {
    $gitVer = (& git --version 2>&1) -join " "
    Write-Status "Git" "PASS" $gitVer
} else {
    Write-Status "Git" "WARN" "Git missing (required for Track A maya-ik2; Track B Unsloth zip does not need Git)"
}

# 5. Track A Build Tools (CUDA Toolkit nvcc + Visual Studio Build Tools)
$nvcc = Get-Command nvcc -ErrorAction SilentlyContinue
if (-not $nvcc) {
    $cudaFound = Get-ChildItem "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v*\bin\nvcc.exe" -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending | Select-Object -First 1
    if ($cudaFound) { $nvcc = $cudaFound }
}
$hasNvcc = $false
if ($nvcc) {
    $nvccPath = if ($nvcc.Source) { $nvcc.Source } else { $nvcc.FullName }
    $nvccVer = (& $nvccPath --version 2>&1 | Select-String "release") -join " "
    Write-Status "CUDA Toolkit (nvcc)" "PASS" "$nvccVer ($nvccPath)"
    $hasNvcc = $true
} else {
    Write-Status "CUDA Toolkit (nvcc)" "WARN" "Not installed (needed ONLY for Track A maya-ik2 build; Track B needs NO toolkit)"
}

$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$hasVs = $false
if (Test-Path $vswhere) {
    $vsPath = & $vswhere -latest -prerelease -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if ($vsPath) {
        Write-Status "VS C++ Build Tools" "PASS" $vsPath
        $hasVs = $true
    } else {
        Write-Status "VS C++ Build Tools" "WARN" "VS Installer found, but C++ x64 tools (MSVC) missing"
    }
} else {
    Write-Status "VS C++ Build Tools" "WARN" "Not installed (needed ONLY for Track A maya-ik2 build; Track B needs NO VS)"
}

# 6. Recommendation
Write-Host "`n=== Recommendation ===" -ForegroundColor Cyan
if ($hasNvcc -and $hasVs -and $git -and $py) {
    Write-Host "READY FOR TRACK A (maya-ik2, 130-210 tok/s)! Run:" -ForegroundColor Green
    Write-Host "  .\02_install_maya_ik2.ps1" -ForegroundColor White
} else {
    Write-Host "Track A build tools missing (CUDA Toolkit and/or VS C++ Build Tools)." -ForegroundColor Yellow
    Write-Host "You can run Track B RIGHT NOW (5 minutes, zero compile, 75-105 tok/s):" -ForegroundColor Green
    Write-Host "  .\03_install_unsloth_llamacpp.ps1" -ForegroundColor White
    Write-Host "Or install VS 2022 Build Tools + CUDA Toolkit 12.8 (Custom install -> UNCHECK Display Driver!) then run .\02_install_maya_ik2.ps1." -ForegroundColor Gray
}
Write-Host ""
