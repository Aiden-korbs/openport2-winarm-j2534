@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0register_kline_only_alias_windows_arm.ps1" %*
exit /b %ERRORLEVEL%
