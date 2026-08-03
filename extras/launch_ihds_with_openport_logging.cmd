@echo off
setlocal

set "IHDS_TARGET=%~1"
set "IHDS_ARGS="
if "%IHDS_TARGET%"=="" (
    if exist "C:\i-HDS\Launcher.exe" (
        set "IHDS_TARGET=C:\i-HDS\Launcher.exe"
        set "IHDS_ARGS=-selector"
    ) else if exist "C:\Users\Public\Desktop\Diagnostic System.lnk" (
        set "IHDS_TARGET=C:\Users\Public\Desktop\Diagnostic System.lnk"
    ) else (
        set "IHDS_TARGET=C:\i-HDS\Launcher.exe"
    )
) else (
    if not "%~2"=="" call :append_arg %2
    if not "%~3"=="" call :append_arg %3
    if not "%~4"=="" call :append_arg %4
    if not "%~5"=="" call :append_arg %5
    if not "%~6"=="" call :append_arg %6
    if not "%~7"=="" call :append_arg %7
    if not "%~8"=="" call :append_arg %8
    if not "%~9"=="" call :append_arg %9
)

if not exist "%IHDS_TARGET%" (
    echo I-HDS launcher was not found: "%IHDS_TARGET%"
    echo Pass the full path to the installed shortcut or executable, for example:
    echo   %~nx0 "C:\i-HDS\Launcher.exe" -selector
    exit /b 1
)

if not exist "C:\J2534" mkdir "C:\J2534"

set "OPENPORT_DIR=C:\J2534\OpenPort"
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

for %%I in ("%IHDS_TARGET%") do (
    set "IHDS_DIR=%%~dpI"
    set "IHDS_EXT=%%~xI"
)

set "LOG_ENABLE=C:\J2534\op2.log"
set "LIBUSB_DEBUG=3"
set "PATH=%OPENPORT_DIR%;%PATH%"

echo Launching I-HDS with OpenPort logging enabled.
echo I-HDS: %IHDS_TARGET%
if not "%IHDS_ARGS%"=="" echo Arguments: %IHDS_ARGS%
echo Start in: %IHDS_DIR%
echo LOG_ENABLE=%LOG_ENABLE%
echo LIBUSB_DEBUG=%LIBUSB_DEBUG%
echo PATH prepended with: %OPENPORT_DIR%
echo.
echo If C:\J2534\op2.log remains empty while ProcMon shows j2534.dll loaded,
echo I-HDS loaded the DLL but has not called into this J2534 implementation yet.

if /I "%IHDS_EXT%"==".lnk" (
    echo Shortcut target, arguments, and Start in settings will be preserved.
    start "I-HDS OpenPort logging" "%IHDS_TARGET%" %IHDS_ARGS%
) else (
    start "I-HDS OpenPort logging" /D "%IHDS_DIR%" "%IHDS_TARGET%" %IHDS_ARGS%
)
exit /b 0

:append_arg
if defined IHDS_ARGS (
    set "IHDS_ARGS=%IHDS_ARGS% %1"
) else (
    set "IHDS_ARGS=%1"
)
exit /b 0
