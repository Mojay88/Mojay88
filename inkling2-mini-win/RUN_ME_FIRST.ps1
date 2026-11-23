<#
.SYNOPSIS
  1-Click Master Orchestrator for Inkling 2 Mini on Windows 11 (RTX 3090 24GB).
  1) Runs preflight check.
  2) Auto-picks Track A (maya-ik2, 130-210 tok/s) if VS C++ Build Tools + CUDA Toolkit are present,
     otherwise runs Track B (Unsloth llama.cpp b12649, zero-compile, 75-105 tok/s) immediately.
  3) Launches Inkling 2 Mini on GPU0 (:8094) with safe GPU0 swap + live smoke test.
#>
[CmdletBinding()]
param(
    [ValidateSet("auto", "maya", "unsloth")]
    [string]$Mode = "auto",
    [int]$MaxContext = 131072,
    [int]$Port = 8094
)

$ErrorActionPreference = "Stop"
$kitDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# 1. Preflight
& (Join-Path $kitDir "01_preflight_check.ps1")

# 2. Decide Track A vs Track B
if ($Mode -eq "auto") {
    $hasNvcc = [bool](Get-Command nvcc -ErrorAction SilentlyContinue) -or
        [bool](Get-ChildItem "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v*\bin\nvcc.exe" -ErrorAction SilentlyContinue | Select-Object -First 1)
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    $hasVs = $false
    if (Test-Path $vswhere) {
        $vsPath = & $vswhere -latest -prerelease -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        $hasVs = [bool]$vsPath
    }
    $hasGit = [bool](Get-Command git -ErrorAction SilentlyContinue)

    if ($hasNvcc -and $hasVs -and $hasGit) {
        $Mode = "maya"
        Write-Host "`n[AUTO] Build tools detected -> Selecting Track A (maya-ik2, 130-210 tok/s)." -ForegroundColor Green
    } else {
        $Mode = "unsloth"
        Write-Host "`n[AUTO] Build tools absent -> Selecting Track B (Unsloth llama.cpp b12649, 5-min zero-compile)." -ForegroundColor Yellow
    }
}

# 3. Install chosen track
if ($Mode -eq "maya") {
    & (Join-Path $kitDir "02_install_maya_ik2.ps1") -MaxContext $MaxContext
} else {
    & (Join-Path $kitDir "03_install_unsloth_llamacpp.ps1")
}

# 4. Launch & verify
& (Join-Path $kitDir "04_start_inkling.ps1") -Engine $Mode -MaxContext $MaxContext -Port $Port
