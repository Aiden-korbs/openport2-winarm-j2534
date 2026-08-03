@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0prepare_evoscan_windows_arm.ps1" %*
exit /b %ERRORLEVEL%
