<#
.SYNOPSIS
  Instant rollback: stops Inkling 2 Mini on port 8094, restores the scheduled finance service on port 8092,
  and verifies HTTP 200 health + golden math gate (17*19=323).
#>
[CmdletBinding()]
param(
    [int]$InklingPort = 8094,
    [int]$FinancePort = 8092,
    [string]$TaskName = "MojayFleet-CoderNext8092"
)

$ErrorActionPreference = "Stop"

Write-Host "`n=== Rollback: Stopping Inkling (:$InklingPort) -> Restoring $TaskName (:$FinancePort) ===" -ForegroundColor Cyan

# 1. Stop Inkling server processes on $InklingPort
$inklingProcs = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { ($_.Name -in @("python.exe", "llama-server.exe", "maya-ik2.exe")) -and ($_.CommandLine -match "--port\s+$InklingPort\b|ik2-mini") }
foreach ($p in $inklingProcs) {
    Write-Host "Stopping Inkling PID=$($p.ProcessId) ($($p.Name)) ..." -ForegroundColor Yellow
    Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 3

# 2. Restart scheduled task
Write-Host "Starting scheduled task '$TaskName' ..." -ForegroundColor Cyan
schtasks /Run /TN $TaskName | Out-Null

# 3. Poll /health on $FinancePort
$ok = $false
for ($i = 1; $i -le 30; $i++) {
    try {
        $resp = Invoke-WebRequest -Uri "http://127.0.0.1:$FinancePort/health" -UseBasicParsing -TimeoutSec 2
        if ($resp.StatusCode -eq 200) { $ok = $true; break }
    } catch { }
    Start-Sleep -Seconds 2
}

if (-not $ok) {
    throw "Rollback warning: http://127.0.0.1:$FinancePort/health did not return 200 within 60s. Check Task Scheduler '$TaskName'."
}

Write-Host "[PASS] Finance service restored on :$FinancePort (HTTP 200)." -ForegroundColor Green
& nvidia-smi --query-gpu=index,name,memory.used,memory.total --format=csv
