@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_windows_arm.ps1" %*
exit /b %ERRORLEVEL%
