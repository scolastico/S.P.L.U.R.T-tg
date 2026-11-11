@echo off
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\babylon\Start-Cluster.ps1"
if errorlevel 1 (
  echo.
  echo Server startup failed. See the message above.
  pause
  exit /b 1
)
echo.
pause
