@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0RUN_ME_FIRST.ps1" %*
echo.
pause
