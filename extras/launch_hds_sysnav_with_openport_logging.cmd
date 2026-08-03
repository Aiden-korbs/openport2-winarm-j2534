@echo off
setlocal

set "OPENPORT_DIR=C:\J2534\OpenPort"
set "HDS_RUNTIME=C:\GenRad\DiagSystem\Runtime"
set "HDS_SYSNAV=%HDS_RUNTIME%\SysNav.exe"

if not exist "%OPENPORT_DIR%\j2534.dll" (
    echo OpenPort J2534 DLL was not found: "%OPENPORT_DIR%\j2534.dll"
    echo Run extras\install_windows_arm.cmd first.
    exit /b 1
)
if not exist "%OPENPORT_DIR%\libusb-1.0.dll" (
    echo libusb runtime was not found: "%OPENPORT_DIR%\libusb-1.0.dll"
    echo Run extras\install_windows_arm.cmd first.
    exit /b 1
)
if not exist "%HDS_SYSNAV%" (
    echo Legacy HDS SysNav was not found: "%HDS_SYSNAV%"
    exit /b 1
)
if not exist "%HDS_RUNTIME%\SysNav.ini" (
    echo Legacy HDS SysNav.ini was not found: "%HDS_RUNTIME%\SysNav.ini"
    exit /b 1
)

if not exist "C:\J2534" mkdir "C:\J2534"
break > "C:\J2534\op2.log"

set "LOG_ENABLE=C:\J2534\op2.log"
set "LIBUSB_DEBUG=3"
set "PATH=%OPENPORT_DIR%;%HDS_RUNTIME%;%PATH%"

echo Launching legacy Honda HDS SysNav with OpenPort logging enabled.
echo SysNav: %HDS_SYSNAV%
echo Start in: %HDS_RUNTIME%
echo LOG_ENABLE=%LOG_ENABLE%
echo LIBUSB_DEBUG=%LIBUSB_DEBUG%
echo PATH prepended with: %OPENPORT_DIR%;%HDS_RUNTIME%
echo.
echo SysNav.ini starts the classic vehicle workflow:
echo   testman.exe /a:Setup /a:Vehicle
echo.
echo If C:\J2534\op2.log remains empty, HDS has not reached J2534 yet.

start "HDS SysNav OpenPort logging" /D "%HDS_RUNTIME%" "%HDS_SYSNAV%"
exit /b 0
