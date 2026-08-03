@echo off
setlocal

set "HDS_ROOT=C:\GenRad\DiagSystem"
set "HDS_RUNTIME=%HDS_ROOT%\Runtime"
set "HDS_DATA=%HDS_ROOT%\Data\"
set "HDS_SCANTOOL_DB=%HDS_ROOT%\Scantool\RuntimeDatabase\"
set "HDS_HTML=%HDS_ROOT%\HTML"
set "HDS_HELP=%HDS_ROOT%\HTML\Use"
set "HDS_ICONS=%HDS_ROOT%\Icons"
set "BACKUP_DIR=C:\J2534"

if not exist "%HDS_ROOT%" (
    echo Legacy HDS root was not found: "%HDS_ROOT%"
    exit /b 1
)
if not exist "%HDS_DATA%Values" (
    echo Legacy HDS database was not found: "%HDS_DATA%Values"
    exit /b 1
)
if not exist "%HDS_SCANTOOL_DB%Values" (
    echo Legacy HDS Scantool database was not found: "%HDS_SCANTOOL_DB%Values"
    exit /b 1
)
if not exist "%BACKUP_DIR%" mkdir "%BACKUP_DIR%"

net session >nul 2>&1
if errorlevel 1 (
    echo Run this script from an Administrator Command Prompt.
    exit /b 1
)

set "STAMP=%DATE:/=-%_%TIME::=-%"
set "STAMP=%STAMP: =0%"
set "STAMP=%STAMP:.=-%"

reg export "HKLM\SOFTWARE\GenRad\System" "%BACKUP_DIR%\hds-reg-backup-genrad-system-%STAMP%.reg" /y /reg:32 >nul 2>&1
reg export "HKLM\SOFTWARE\GenRad\WidgetSet" "%BACKUP_DIR%\hds-reg-backup-widgetset-%STAMP%.reg" /y /reg:32 >nul 2>&1
reg export "HKLM\SOFTWARE\Teradyne\OBD Scantool\Settings" "%BACKUP_DIR%\hds-reg-backup-obd-scantool-%STAMP%.reg" /y /reg:32 >nul 2>&1

echo Writing legacy HDS 32-bit registry paths.

call :write_paths HKLM
call :write_paths HKCU

echo Done.
echo.
echo Re-run:
echo   C:\J2534\launch_hds_sysnav_with_openport_logging.cmd
echo.
echo If the next run still reports a missing Values file, try setting
echo GenRad System Database to the Scantool runtime database:
echo   reg add "HKLM\SOFTWARE\GenRad\System" /v "Database" /t REG_SZ /d "%HDS_SCANTOOL_DB%" /f /reg:32
echo   reg add "HKCU\SOFTWARE\GenRad\System" /v "Database" /t REG_SZ /d "%HDS_SCANTOOL_DB%" /f /reg:32
exit /b 0

:write_paths
set "ROOT=%~1"
reg add "%ROOT%\SOFTWARE\GenRad\System" /v "Path" /t REG_SZ /d "%HDS_ROOT%" /f /reg:32 >nul
reg add "%ROOT%\SOFTWARE\GenRad\System" /v "RuntimePath" /t REG_SZ /d "%HDS_RUNTIME%" /f /reg:32 >nul
reg add "%ROOT%\SOFTWARE\GenRad\System" /v "Database" /t REG_SZ /d "%HDS_DATA%" /f /reg:32 >nul
reg add "%ROOT%\SOFTWARE\GenRad\System" /v "HtmlPath" /t REG_SZ /d "%HDS_HTML%" /f /reg:32 >nul
reg add "%ROOT%\SOFTWARE\GenRad\System" /v "HelpURLPath" /t REG_SZ /d "%HDS_HELP%" /f /reg:32 >nul
reg add "%ROOT%\SOFTWARE\GenRad\WidgetSet" /v "Icon Paths" /t REG_SZ /d "%HDS_ICONS%" /f /reg:32 >nul
reg add "%ROOT%\SOFTWARE\GenRad\WidgetSet" /v "Image Paths" /t REG_SZ /d "%HDS_ICONS%;%HDS_HTML%\Images" /f /reg:32 >nul
reg add "%ROOT%\SOFTWARE\GenRad\WidgetSet\System" /v "Icon Paths" /t REG_SZ /d "%HDS_ICONS%" /f /reg:32 >nul
reg add "%ROOT%\SOFTWARE\GenRad\WidgetSet\System" /v "Image Paths" /t REG_SZ /d "%HDS_ICONS%;%HDS_HTML%\Images" /f /reg:32 >nul
reg add "%ROOT%\SOFTWARE\Teradyne\OBD Scantool\Settings" /v "Database" /t REG_SZ /d "%HDS_SCANTOOL_DB%" /f /reg:32 >nul
exit /b 0
