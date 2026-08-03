@echo off
setlocal

set "BASE=%~dp0"
set "SRC=%BASE%obd2_mode09_j2534.c"
set "OUT=%BASE%obd2_mode09.exe"
set "DLL=C:\J2534\OpenPort\j2534.dll"

if not exist "%SRC%" (
    echo Source file not found: "%SRC%"
    exit /b 1
)
if not exist "%DLL%" (
    echo OpenPort J2534 DLL not found: "%DLL%"
    exit /b 1
)

if not defined VSCMD_VER call :vsdev
if not defined VSCMD_VER (
    echo Visual Studio Build Tools environment was not found.
    echo Install VS 2022 Build Tools with MSVC x86 tools, or run this from an x86 Developer Command Prompt.
    exit /b 1
)

cl /nologo /W4 /O2 /MT /D_CRT_SECURE_NO_WARNINGS /Fe:"%OUT%" "%SRC%"
if errorlevel 1 exit /b 1

set "LOG_ENABLE=C:\J2534\op2.log"
set "LIBUSB_DEBUG=3"
set "PATH=C:\J2534\OpenPort;%PATH%"

"%OUT%" --dll "%DLL%" %*
exit /b %ERRORLEVEL%

:vsdev
if exist "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat" (
    call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat" -arch=x86 -host_arch=arm64
    exit /b 0
)
if exist "C:\Program Files\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat" (
    call "C:\Program Files\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat" -arch=x86 -host_arch=arm64
    exit /b 0
)
if exist "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat" (
    call "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat" -arch=x86 -host_arch=arm64
    exit /b 0
)
exit /b 1
