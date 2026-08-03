@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0register_honda_aliases_windows_arm.ps1" %*
exit /b %ERRORLEVEL%
