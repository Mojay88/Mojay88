<#
.SYNOPSIS
  Installs and configures the Pi coding harness (@earendil-works/pi-coding-agent) — the exact coding harness
  used by Unbiased Bob in the video — wired to Inkling 2 Mini on http://127.0.0.1:8094/v1.
  Safely merges into ~/.pi/agent/models.json without deleting existing providers.
#>
[CmdletBinding()]
param(
    [int]$Port = 8094,
    [int]$ContextWindow = 131072
)

$ErrorActionPreference = "Stop"

Write-Host "`n=== Configuring Pi Coding Harness (@earendil-works/pi-coding-agent) ===`n" -ForegroundColor Cyan

if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    throw "npm not found. Run .\00_install_prereqs_win.ps1 first to install Node.js LTS."
}

# 1. Install Pi globally if missing
if (-not (Get-Command pi -ErrorAction SilentlyContinue)) {
    Write-Host "[1/2] Installing @earendil-works/pi-coding-agent ..." -ForegroundColor Yellow
    npm install -g @earendil-works/pi-coding-agent
} else {
    $piVer = (& pi --version 2>&1) -join " "
    Write-Host "[1/2] Pi already installed: $piVer" -ForegroundColor Green
}

# 2. Merge maya-ik2 provider into ~/.pi/agent/models.json
Write-Host "[2/2] Updating ~/.pi/agent/models.json ..." -ForegroundColor Cyan
$piDir = Join-Path $env:USERPROFILE ".pi\agent"
$modelsFile = Join-Path $piDir "models.json"
New-Item -ItemType Directory -Force -Path $piDir | Out-Null

$rootObj = @{}
if (Test-Path $modelsFile) {
    $backup = "$modelsFile.bak_$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item -Force $modelsFile $backup
    Write-Host "Backed up existing models.json to $backup" -ForegroundColor Gray
    try {
        $parsed = Get-Content $modelsFile -Raw | ConvertFrom-Json
        if ($parsed) {
            foreach ($prop in $parsed.PSObject.Properties) {
                $rootObj[$prop.Name] = $prop.Value
            }
        }
    } catch {
        Write-Warning "Existing models.json could not be parsed cleanly; starting fresh (backup saved)."
    }
}

$providersMap = [ordered]@{}
if ($rootObj.ContainsKey("providers") -and $rootObj["providers"]) {
    foreach ($prop in $rootObj["providers"].PSObject.Properties) {
        $providersMap[$prop.Name] = $prop.Value
    }
}

$providersMap["maya-ik2"] = [ordered]@{
    baseUrl = "http://127.0.0.1:$Port/v1"
    api = "openai-completions"
    apiKey = "none"
    models = @(
        [ordered]@{
            id = "inkling-2-mini"
            name = "Inkling 2 Mini (maya-ik2 RTX 3090)"
            reasoning = $true
            input = @("text", "image")
            contextWindow = $ContextWindow
            maxTokens = 32768
        }
    )
}

$rootObj["providers"] = $providersMap
$rootObj | ConvertTo-Json -Depth 10 | Set-Content -Path $modelsFile -Encoding UTF8

Write-Host "[DONE] Pi configured at $modelsFile" -ForegroundColor Green
Write-Host "Tip from video: inside Pi, set thinking/reasoning level to MINIMAL (0.1) for best speed & 94% coding score!" -ForegroundColor Yellow
Write-Host "Start Pi in any project folder with: pi`n" -ForegroundColor Cyan
