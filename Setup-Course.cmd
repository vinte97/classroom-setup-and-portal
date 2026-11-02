@echo off
chcp 65001 >nul
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-windows.ps1" %*
set EXITCODE=%ERRORLEVEL%
echo.
echo Код завершения: %EXITCODE%
echo %* | findstr /I /C:"-Yes" /C:"-DryRun" /C:"-SelfCheck" >nul
if errorlevel 1 pause
exit /b %EXITCODE%
