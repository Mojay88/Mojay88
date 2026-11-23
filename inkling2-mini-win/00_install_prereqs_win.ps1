<#
.SYNOPSIS
  Installs all prerequisites needed on Windows 11 to build and run the exact Unbiased Bob video setup:
  Git, Python 3.12, Visual Studio 2022 C++ Build Tools, CUDA Toolkit 12.8 (Toolkit ONLY - preserves NVIDIA Driver 580.88),
  and Node.js LTS (for the Pi coding harness).
#>
[CmdletBinding()]
param(
    [switch]$SkipNodeForPi
)

$ErrorActionPreference = "Stop"

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Refresh-ProcessPath {
    $machine = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $user = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:PATH = "$machine;$user"
}

Write-Host "`n=== Step 0: Checking & Installing Windows Build Prerequisites ===`n" -ForegroundColor Cyan

$winget = Get-Command winget -ErrorAction SilentlyContinue
if (-not $winget) {
    throw "winget is not available on this Windows install. Update App Installer from Microsoft Store first."
}

# 1. Git
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "[Install] Git for Windows ..." -ForegroundColor Yellow
    winget install -e --id Git.Git --accept-source-agreements --accept-package-agreements
    Refresh-ProcessPath
} else {
    Write-Host "[OK] Git already installed." -ForegroundColor Green
}

# 2. Python 3.12
if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    Write-Host "[Install] Python 3.12 ..." -ForegroundColor Yellow
    winget install -e --id Python.Python.3.12 --scope user --accept-source-agreements --accept-package-agreements
    Refresh-ProcessPath
} else {
    Write-Host "[OK] Python already installed." -ForegroundColor Green
}

# 3. Visual Studio 2022 Build Tools (MUST be installed BEFORE CUDA Toolkit!)
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$hasVs = $false
if (Test-Path $vswhere) {
    $vsPath = & $vswhere -latest -prerelease -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    $hasVs = [bool]$vsPath
}
if (-not $hasVs) {
    if (-not (Test-IsAdmin)) {
        Write-Warning "Installing VS 2022 Build Tools requires Administrator elevation (UAC prompt may appear)."
    }
    Write-Host "[Install] Visual Studio 2022 Build Tools (C++ x64 + Windows SDK) - this can take 5-15 min ..." -ForegroundColor Yellow
    winget install -e --id Microsoft.VisualStudio.2022.BuildTools `
        --accept-source-agreements --accept-package-agreements `
        --override "--wait --passive --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
    Refresh-ProcessPath
} else {
    Write-Host "[OK] Visual Studio C++ x64 Build Tools already installed." -ForegroundColor Green
}

# 4. CUDA Toolkit (Toolkit ONLY - never overwrite pinned NVIDIA Display Driver!)
$nvcc = Get-Command nvcc -ErrorAction SilentlyContinue
if (-not $nvcc) {
    $cudaFound = Get-ChildItem "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v*\bin\nvcc.exe" -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending | Select-Object -First 1
    if ($cudaFound) { $nvcc = $cudaFound }
}
if (-not $nvcc) {
    Write-Host "[Install] NVIDIA CUDA Toolkit 12.8 (Toolkit ONLY - Display Driver untouched) ..." -ForegroundColor Yellow
    winget install -e --id Nvidia.CUDA --version 12.8 `
        --accept-source-agreements --accept-package-agreements `
        --override "-s nvcc_12.8 cudart_12.8 cublas_dev_12.8 cublas_12.8 cuda_cccl_12.8 curand_dev_12.8 cusolver_dev_12.8 cusparse_dev_12.8 visual_studio_integration_12.8"
    Refresh-ProcessPath
    $cudaVerify = Get-ChildItem "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v*\bin\nvcc.exe" -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending | Select-Object -First 1
    if (-not $cudaVerify) {
        throw "CUDA Toolkit 12.8 did not register nvcc.exe yet. Install CUDA Toolkit 12.8 manually (Custom -> UNCHECK Display Driver) and re-run."
    }
} else {
    Write-Host "[OK] CUDA Toolkit (nvcc) already installed." -ForegroundColor Green
}

# 5. Node.js LTS (for Pi coding harness from the video)
if (-not $SkipNodeForPi) {
    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        Write-Host "[Install] Node.js LTS (for Pi coding harness) ..." -ForegroundColor Yellow
        winget install -e --id OpenJS.NodeJS.LTS --accept-source-agreements --accept-package-agreements
        Refresh-ProcessPath
    } else {
        Write-Host "[OK] Node.js / npm already installed." -ForegroundColor Green
    }
}

Write-Host "`n[DONE] All prerequisites verified!" -ForegroundColor Green
