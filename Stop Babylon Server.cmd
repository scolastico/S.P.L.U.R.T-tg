@echo off
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\babylon\Stop-Cluster.ps1"
if errorlevel 1 (
  echo.
  echo Shutdown did not complete. Running worlds were not forcibly terminated.
  pause
  exit /b 1
)
echo.
pause
