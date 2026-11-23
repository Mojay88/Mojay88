<#
.SYNOPSIS
  1-Click Master Orchestrator - EXACT Unbiased Bob Video Setup on Windows 11 (RTX 3090 24GB):
  1) Preflight check.
  2) Auto-installs missing build prerequisites (VS 2022 C++, CUDA Toolkit 12.8 without touching Driver 580.88, Git, Python, Node).
  3) Builds maya-ik2.exe (sm_86) + maya-vision.exe (CPU), downloads Unsloth UD-Q4_K_XL (Old_Support) + Thinking Machines mtp.safetensors.
  4) Installs & wires Pi coding harness (~/.pi/agent/models.json) to http://127.0.0.1:8094/v1.
  5) Safely frees GPU0 (:8092 -> rollback anytime via 05_rollback_to_finance.ps1), launches maya-ik2 with exact video flags,
     verifies resident=1 and runs the golden smoke test at reasoning_effort=minimal (0.1).
#>
[CmdletBinding()]
param(
    [ValidateSet("video", "unsloth")]
    [string]$Mode = "video",
    [int]$MaxContext = 131072,
    [int]$Port = 8094,
    [switch]$SkipPi
)

$ErrorActionPreference = "Stop"
$kitDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# 1. Preflight
& (Join-Path $kitDir "01_preflight_check.ps1")

if ($Mode -eq "video") {
    # 2. Ensure all build prerequisites are installed (preserving NVIDIA Driver 580.88)
    & (Join-Path $kitDir "00_install_prereqs_win.ps1") -SkipNodeForPi:$SkipPi

    # 3. Build maya-ik2 + maya-vision + download weights & DSpark drafter
    & (Join-Path $kitDir "02_install_maya_ik2.ps1") -MaxContext $MaxContext

    # 4. Install & configure Pi coding harness
    if (-not $SkipPi) {
        & (Join-Path $kitDir "06_setup_pi_harness.ps1") -Port $Port -ContextWindow $MaxContext
    }

    # 5. Launch maya-ik2 on GPU0 & verify resident=1 + live smoke test
    & (Join-Path $kitDir "04_start_inkling.ps1") -Engine maya -MaxContext $MaxContext -Port $Port
} else {
    # Optional fast zero-compile fallback (Unsloth llama.cpp b12649)
    & (Join-Path $kitDir "03_install_unsloth_llamacpp.ps1")
    & (Join-Path $kitDir "04_start_inkling.ps1") -Engine unsloth -MaxContext $MaxContext -Port $Port
}
