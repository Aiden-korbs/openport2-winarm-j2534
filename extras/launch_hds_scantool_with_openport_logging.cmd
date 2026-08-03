@echo off
setlocal

set "OPENPORT_DIR=C:\J2534\OpenPort"
set "HDS_ROOT=C:\GenRad\DiagSystem"
set "HDS_LAUNCHER=%HDS_ROOT%\Launcher\Launcher.exe"
set "HDS_SCANTOOL=%HDS_ROOT%\Runtime\Scantool.exe"
set "HDS_START_DIR=%HDS_ROOT%\Launcher"

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
if not exist "%HDS_LAUNCHER%" (
    echo Legacy HDS launcher was not found: "%HDS_LAUNCHER%"
    exit /b 1
)
if not exist "%HDS_SCANTOOL%" (
    echo Legacy HDS Scantool was not found: "%HDS_SCANTOOL%"
    exit /b 1
)

if not exist "C:\J2534" mkdir "C:\J2534"
break > "C:\J2534\op2.log"

set "LOG_ENABLE=C:\J2534\op2.log"
set "LIBUSB_DEBUG=3"
set "PATH=%OPENPORT_DIR%;%PATH%"

echo Launching legacy Honda HDS Scantool with OpenPort logging enabled.
echo Launcher: %HDS_LAUNCHER%
echo Scantool: %HDS_SCANTOOL%
echo Start in: %HDS_START_DIR%
echo LOG_ENABLE=%LOG_ENABLE%
echo LIBUSB_DEBUG=%LIBUSB_DEBUG%
echo PATH prepended with: %OPENPORT_DIR%
echo.
echo This follows the installed Start Menu shortcut:
echo   Diagnostic System\Scantool.lnk
echo.
echo If C:\J2534\op2.log remains empty, verify the 32-bit
echo Teradyne - GNA600 J2534 registry provider points to this DLL:
echo   %OPENPORT_DIR%\j2534.dll

start "HDS Scantool OpenPort logging" /D "%HDS_START_DIR%" "%HDS_LAUNCHER%" "%HDS_SCANTOOL%"
exit /b 0
