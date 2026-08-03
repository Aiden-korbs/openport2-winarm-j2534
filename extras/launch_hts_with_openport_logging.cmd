@echo off
setlocal

set "HTS_TARGET=%~1"
if "%HTS_TARGET%"=="" set "HTS_TARGET=C:\Users\Aiden\Desktop\HTS2.15\HTS2.15.exe"

if not exist "%HTS_TARGET%" (
    echo HTS was not found: "%HTS_TARGET%"
    echo Pass the full path to HTS2.15.exe as the first argument.
    exit /b 1
)

set "OPENPORT_DIR=C:\J2534\OpenPort"
if not exist "%OPENPORT_DIR%\j2534.dll" (
    echo OpenPort J2534 DLL was not found: "%OPENPORT_DIR%\j2534.dll"
    exit /b 1
)
if not exist "%OPENPORT_DIR%\libusb-1.0.dll" (
    echo libusb runtime was not found: "%OPENPORT_DIR%\libusb-1.0.dll"
    exit /b 1
)

for %%I in ("%HTS_TARGET%") do set "HTS_DIR=%%~dpI"

set "LOG_ENABLE=C:\J2534\op2.log"
set "LIBUSB_DEBUG=3"
set "PATH=%OPENPORT_DIR%;%HTS_DIR%;%PATH%"

echo Launching HTS with OpenPort logging enabled.
echo HTS: %HTS_TARGET%
echo Start in: %HTS_DIR%
echo LOG_ENABLE=%LOG_ENABLE%
echo PATH prepended with: %OPENPORT_DIR%;%HTS_DIR%
echo.

start "HTS OpenPort logging" /D "%HTS_DIR%" "%HTS_TARGET%"
exit /b 0
