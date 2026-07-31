@echo off
setlocal EnableExtensions

set "REPO_ROOT=%~dp0.."
set "BUILT_DLL=%REPO_ROOT%\Release\j2534.dll"
set "BUILT_LIBUSB=%REPO_ROOT%\libusb\MS32\Release\dll\libusb-1.0.dll"
set "LOG_FILE=C:\J2534\op2.log"

if "%~1"=="" (
    echo Usage: %~nx0 "C:\Program Files (x86)\EvoScan\EvoScan v2.9"
    exit /b 2
)

set "EVOSCAN_DIR=%~1"

fltmc >nul 2>&1
if errorlevel 1 (
    echo ERROR: Run this script from an Administrator command prompt.
    exit /b 1
)

if not exist "%EVOSCAN_DIR%\EvoScan.exe" (
    echo ERROR: EvoScan.exe not found in: %EVOSCAN_DIR%
    exit /b 1
)

if not exist "%BUILT_DLL%" (
    echo ERROR: Built DLL not found: %BUILT_DLL%
    exit /b 1
)

if not exist "%BUILT_LIBUSB%" (
    echo ERROR: libusb runtime not found: %BUILT_LIBUSB%
    exit /b 1
)

taskkill /IM EvoScan.exe /F >nul 2>&1

if exist "%EVOSCAN_DIR%\op20pt32.dll" (
    if not exist "%EVOSCAN_DIR%\op20pt32.dll.tactrix.bak" (
        copy /Y "%EVOSCAN_DIR%\op20pt32.dll" "%EVOSCAN_DIR%\op20pt32.dll.tactrix.bak" >nul
        echo Backed up original op20pt32.dll
    ) else (
        echo Backup already exists: op20pt32.dll.tactrix.bak
    )
)

copy /Y "%BUILT_DLL%" "%EVOSCAN_DIR%\op20pt32.dll" >nul
copy /Y "%BUILT_LIBUSB%" "%EVOSCAN_DIR%\libusb-1.0.dll" >nul

mkdir "C:\J2534" >nul 2>&1
setx LOG_ENABLE "%LOG_FILE%" /M >nul
setx LIBUSB_DEBUG 3 /M >nul

echo Installed replacement OpenPort DLL for EvoScan:
echo %EVOSCAN_DIR%\op20pt32.dll
echo.
echo Log file: %LOG_FILE%

endlocal
