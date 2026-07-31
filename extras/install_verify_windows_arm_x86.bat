@echo off
setlocal EnableExtensions

set "INSTALL_DIR=C:\J2534\OpenPort"
set "LOG_FILE=C:\J2534\op2.log"
set "REG_KEY=HKLM\SOFTWARE\WOW6432Node\PassThruSupport.04.04\RomRaider - OP2 J2534"
set "REPO_ROOT=%~dp0.."
set "BUILT_DLL=%REPO_ROOT%\Release\j2534.dll"
set "BUILT_LIBUSB=%REPO_ROOT%\libusb\MS32\Release\dll\libusb-1.0.dll"

echo OpenPort 2.0 J2534 x86 install and verification
echo.

fltmc >nul 2>&1
if errorlevel 1 (
    echo ERROR: Run this script from an Administrator command prompt.
    echo.
    exit /b 1
)

echo [1/6] Creating install directory
mkdir "C:\J2534" >nul 2>&1
mkdir "%INSTALL_DIR%" >nul 2>&1

echo [2/6] Copying DLLs
if exist "%BUILT_DLL%" (
    copy /Y "%BUILT_DLL%" "%INSTALL_DIR%\j2534.dll" >nul
    echo Installed %INSTALL_DIR%\j2534.dll
) else (
    echo MISSING: %BUILT_DLL%
)

if exist "%BUILT_LIBUSB%" (
    copy /Y "%BUILT_LIBUSB%" "%INSTALL_DIR%\libusb-1.0.dll" >nul
    echo Installed %INSTALL_DIR%\libusb-1.0.dll
) else (
    echo MISSING: %BUILT_LIBUSB%
)

echo.
echo [3/6] Registering 32-bit J2534 DLL
reg add "%REG_KEY%" /v FunctionLibrary /t REG_SZ /d "%INSTALL_DIR%\j2534.dll" /f
reg add "%REG_KEY%" /v ConfigApplication /t REG_SZ /d "" /f
reg add "%REG_KEY%" /v Name /t REG_SZ /d "Openport 2.0 J2534" /f
reg add "%REG_KEY%" /v Vendor /t REG_SZ /d "RomRaider" /f
reg add "%REG_KEY%" /v CAN /t REG_DWORD /d 1 /f
reg add "%REG_KEY%" /v ISO14230 /t REG_DWORD /d 1 /f
reg add "%REG_KEY%" /v ISO15765 /t REG_DWORD /d 1 /f
reg add "%REG_KEY%" /v ISO9141 /t REG_DWORD /d 1 /f

echo.
echo [4/6] Enabling logging for future processes
setx LOG_ENABLE "%LOG_FILE%" /M >nul
setx LIBUSB_DEBUG 3 /M >nul
set "LOG_ENABLE=%LOG_FILE%"
set "LIBUSB_DEBUG=3"

echo.
echo [5/6] Current J2534 registry entry
reg query "%REG_KEY%" /s

echo.
echo [6/6] OpenPort USB device and installed files
dir "%INSTALL_DIR%"
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -like 'USB\VID_0403&PID_CC4D*' } | Format-List Status,Class,FriendlyName,InstanceId"

echo.
echo Next: fully close EvoScan, reopen it, try Openport 2.0 J2534, then run:
echo type "%LOG_FILE%"
echo.
echo If no log file appears, EvoScan did not load this J2534 DLL.

endlocal
