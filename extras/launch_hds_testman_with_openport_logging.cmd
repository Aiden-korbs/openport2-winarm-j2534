@echo off
setlocal

set "OPENPORT_DIR=C:\J2534\OpenPort"
set "HDS_RUNTIME=C:\GenRad\DiagSystem\Runtime"
set "HDS_TESTMAN=%HDS_RUNTIME%\testman.exe"

if not exist "%OPENPORT_DIR%\j2534.dll" (
    echo OpenPort J2534 DLL was not found: "%OPENPORT_DIR%\j2534.dll"
    exit /b 1
)
if not exist "%HDS_TESTMAN%" (
    echo Legacy HDS testman was not found: "%HDS_TESTMAN%"
    exit /b 1
)

break > "C:\J2534\op2.log"

set "LOG_ENABLE=C:\J2534\op2.log"
set "LIBUSB_DEBUG=3"
set "PATH=%OPENPORT_DIR%;%HDS_RUNTIME%;%PATH%"

echo Launching legacy HDS Testman with Setup, Launcher, and Vehicle apps.
echo This tests whether START_PC_HONDA is declared by Launcher.umf.

start "HDS Testman OpenPort logging" /D "%HDS_RUNTIME%" "%HDS_TESTMAN%" /a:Setup /a:Launcher /a:Vehicle
exit /b 0
