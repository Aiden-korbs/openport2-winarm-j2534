# OpenPort 2.0 ARM Diagnostics

This is an ARM-focused OpenPort 2.0 diagnostics project based on `j2534`, a libusb-based SAE J2534-1 library for the Tactrix OpenPort 2.0 cable.

The project has two related goals:

- Make OpenPort 2.0 usable from 32-bit x86 diagnostic applications running under Windows 11 ARM emulation, where the original Tactrix x86/x64 kernel driver cannot be loaded.
- Provide native Apple Silicon/macOS command-line diagnostics that talk directly to OpenPort 2.0 through libusb.

Tested target setups:

- Apple Silicon Mac running native macOS ARM64 tools with Homebrew `libusb`.
- Apple Silicon Mac running a Windows 11 ARM VM
- OpenPort 2.0 USB device attached to the VM
- OpenPort bound to Microsoft WinUSB with Zadig
- 32-bit x86 build of this DLL
- 32-bit x86 `libusb-1.0.dll`
- EvoScan 2.9 using this DLL as `op20pt32.dll`
- Honda HDS/I-HDS diagnostics on a 2005 CR-V over ISO9141/K-line after the KWP checksum compatibility fix

Do not use this fork for ECU flashing unless you have independently validated it for your exact vehicle, VM, USB path, and application. Current focus is diagnostics and datalogging.

## Attribution

This fork is based on the original project:

- Upstream repository: `https://github.com/NikolaKozina/j2534`
- Original authors shown in source: NikolaKozina and Dale Schultz
- Original license: BSD 3-Clause, retained in `LICENSE`

This project depends on libusb:

- libusb project: `https://libusb.info/`
- libusb releases: `https://github.com/libusb/libusb/releases`

Tactrix, OpenPort, EvoScan, EcuFlash, Honda, Mitsubishi, and other product names are trademarks of their respective owners. This fork is not affiliated with or endorsed by those projects or companies.

## What This Fork Adds

- Windows x86 J2534 calling convention and undecorated exports for applications that load J2534 functions by name.
- Windows ARM notes and helper scripts.
- Safer null checks and error handling in several J2534 entry points.
- Fixes for channel validation and `PassThruGetLastError` copying.
- Timeout handling for `PassThruReadMsgs(..., Timeout=0)`.
- 29-bit CAN flag handling.
- Basic support/no-ops for clear-buffer, filter, periodic-message, and function-message-table setup calls used by some applications.
- EvoScan/OpenPort compatibility work, including `READ_VBATT` / `READ_PROG_VOLTAGE` before channel connect and experimental `FIVE_BAUD_INIT` support.
- Optional Windows J2534 registry helper for a K-line-only OpenPort alias.
- Diagnostic logging on DLL load and J2534 calls via `LOG_ENABLE`.
- Native macOS ARM64 OpenPort ISO9141/K-line tester, safe generic OBD scanner, large read-only probe, and HDS-observed Honda K-line probe.

## Why ARM Needs This

Windows ARM can run many x86 user-mode applications and DLLs, but it cannot load x86/x64 kernel drivers. The normal Tactrix OpenPort driver path depends on a kernel driver, so it is not suitable for Windows ARM VMs.

This fork uses WinUSB plus libusb from an emulated x86 DLL. The USB driver remains native Windows, while the diagnostic application and this J2534 DLL run as x86 user-mode code.

On Apple Silicon macOS, the native tools skip J2534 entirely and use libusb directly against OpenPort 2.0. These tools are intended for diagnostics and reverse engineering of read-only request/response behavior, not flashing.

## Build On Windows ARM

Install Build Tools for Visual Studio and the Desktop C++ workload.

The all-in-one installer can download and extract libusb automatically if 7-Zip is installed. The repo does not vendor libusb binaries; it downloads the official libusb release and verifies the SHA-256 hash before copying the needed x86 files into place.

Manual libusb setup is also supported. Download the Windows libusb release archive from:

```text
https://github.com/libusb/libusb/releases
```

Extract the needed x86 files into this layout:

```text
libusb\include\libusb-1.0\libusb.h
libusb\MS32\Release\dll\libusb-1.0.lib
libusb\MS32\Release\dll\libusb-1.0.dll
```

Build from an x86 developer command prompt or normal Administrator Command Prompt:

```bat
cd /d C:\path\to\openport2-winarm-j2534
"C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\MSBuild\Current\Bin\MSBuild.exe" j2534.sln /p:Configuration=Release /p:Platform=x86
```

If your Visual Studio install uses a different MSBuild path or version, adjust the command. The solution platform is `x86`, not `Win32`.

The project defaults to the Visual Studio 2022 C++ toolset, `v143`. The installer detects the installed C++ toolset and passes it to MSBuild automatically. For a manual build, if the project complains about an unavailable platform toolset, add the installed toolset explicitly, for example:

```bat
"C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe" j2534.sln /p:Configuration=Release /p:Platform=x86 /p:PlatformToolset=v143
```

## OpenPort Driver Setup

Inside the Windows ARM VM, bind OpenPort 2.0 to WinUSB:

1. Plug the OpenPort 2.0 into the VM.
2. Open Zadig.
3. Select `OpenPort 2.0`.
4. Replace the current driver with `WinUSB`.
5. Confirm Device Manager shows the device under USB devices, not as the Tactrix kernel driver.

Expected USB ID:

```text
USB\VID_0403&PID_CC4D
```

### Driver Signature Enforcement

Using Zadig to bind the device to WinUSB is preferred because it usually avoids manually installing an unsigned driver package.

If you try a custom/manual INF and Windows refuses to install it because the driver is unsigned, temporarily disable driver signature enforcement from Windows Advanced Startup:

1. Open Settings.
2. Go to System, Recovery, Advanced startup.
3. Restart now.
4. Choose Troubleshoot, Advanced options, Startup Settings, Restart.
5. Press the option for Disable driver signature enforcement.
6. Install the driver before the next normal reboot.

Secure Boot can also block test-signing changes such as `bcdedit /set testsigning on`. Prefer Zadig/WinUSB first, and only use unsigned INF/test-signing workflows if you know you need them.

## Generic J2534 Install

For a fresh Windows ARM VM, the all-in-one installer is preferred. Run from an Administrator Command Prompt in the repo root:

```bat
extras\install_windows_arm.cmd -EvoScanDir "C:\Program Files (x86)\EvoScan\EvoScan v2.9"
```

The installer will build `Release|x86` if needed, copy the DLLs to `C:\J2534\OpenPort`, register the 32-bit J2534 provider, enable logging, replace EvoScan's `op20pt32.dll`, and print OpenPort USB status.

Before changing anything, the installer checks for the common missing pieces: libusb layout, 7-Zip, MSBuild, and the Visual Studio Desktop C++ workload. If something is missing, it prints the exact install commands to run.

To only check prerequisites, use:

```bat
extras\install_windows_arm.cmd -CheckOnly
```

To let the installer use `winget` for missing prerequisites such as 7-Zip or Visual Studio Build Tools with the Desktop C++ workload, use:

```bat
extras\install_windows_arm.cmd -InstallMissingPrereqs -EvoScanDir "C:\Program Files (x86)\EvoScan\EvoScan v2.9"
```

If Build Tools or 7-Zip were just installed, close and reopen the Administrator Command Prompt before re-running the installer if Windows has not refreshed `PATH` yet. If the Visual Studio Installer reports exit code `3010`, restart Windows, then re-run the installer.

If the required libusb files are missing, the installer downloads the official libusb release from GitHub, verifies its SHA-256 hash, extracts it with 7-Zip, and copies the x86 files into the expected repo layout.

If PowerShell script execution is blocked, use the `.cmd` launcher above. It runs PowerShell with `-ExecutionPolicy Bypass` for that one invocation only.

If you already have a built DLL and only want to install it, use:

```bat
extras\install_windows_arm.cmd -NoBuild
```

If you do not want to modify EvoScan, use:

```bat
extras\install_windows_arm.cmd -NoEvoScan
```

If you want to prevent automatic libusb downloading and require the files to already exist locally, use:

```bat
extras\install_windows_arm.cmd -NoLibusbDownload
```

After building, run from an Administrator Command Prompt:

```bat
extras\install_verify_windows_arm_x86.bat
```

This copies files to:

```text
C:\J2534\OpenPort\j2534.dll
C:\J2534\OpenPort\libusb-1.0.dll
```

It also registers a 32-bit J2534 provider under:

```text
HKLM\SOFTWARE\WOW6432Node\PassThruSupport.04.04\RomRaider - OP2 J2534
```

## EvoScan 2.9 Install

EvoScan can load OpenPort support directly from its own `op20pt32.dll` rather than using the Windows J2534 registry. For EvoScan, replace that DLL with this fork's built DLL.

Before running the EvoScan installer on a fresh Windows ARM VM, enable the legacy .NET Framework feature EvoScan asks for:

```bat
extras\prepare_evoscan_windows_arm.cmd
```

This enables `.NET Framework 3.5`, which includes `.NET 2.0`. If the EvoScan installer asks to download `.NET Framework 2.0` from the web, click `No`; use the Windows feature instead.

Run from an Administrator Command Prompt:

```bat
extras\install_evoscan_windows_arm_x86.bat "C:\Program Files (x86)\EvoScan\EvoScan v2.9"
```

The script backs up the existing DLL to:

```text
op20pt32.dll.tactrix.bak
```

Then it copies:

```text
Release\j2534.dll -> op20pt32.dll
libusb\MS32\Release\dll\libusb-1.0.dll -> libusb-1.0.dll
```

If EvoScan shows an FTDI driver warning on Windows ARM, do not install the FTDI/Tactrix driver path for OpenPort. The working path for this fork is WinUSB/libusb.

## Native macOS Apple Silicon Tester

This repo also includes a standalone native macOS ARM64 OpenPort diagnostic tester. It is not a J2534 library and it does not run Windows applications such as EvoScan or i-HDS. It talks directly to OpenPort 2.0 with `libusb` and mirrors the ISO9141/K-line sequence that worked with EvoScan on a 2005 Honda CR-V.

Install dependencies:

```sh
brew install libusb pkg-config
```

Attach the OpenPort USB device to macOS, not the Windows VM, then run:

```sh
extras/build_run_macos_openport_iso9141_mode09.sh
```

To run the safe read-only generic OBD scanner and write a timestamped log:

```sh
extras/build_run_macos_openport_iso9141_scan.sh
```

To run the larger read-only probe intended to find non-generic/ECU-specific data that the generic OBD scanner missed:

```sh
extras/build_run_macos_openport_iso9141_probe.sh
```

To replay the read/status-style Honda HDS K-line requests that were observed working through I-HDS/HDS, including the requests that returned VIN and ECU calibration ID:

```sh
extras/build_run_macos_openport_iso9141_hds_probe.sh
```

The large probe writes `extras/macos_openport_probe_YYYYMMDD_HHMMSS.log`. To quickly inspect only useful responses:

```sh
grep '^HIT' extras/macos_openport_probe_*.log
grep '^HIT' extras/macos_openport_probe_*.log | grep -v 'negative_for='
```

The large probe can take 30 minutes or more because most unknown identifiers will time out rather than answer.

The HDS-style probe writes `extras/macos_openport_hds_probe_YYYYMMDD_HHMMSS.log`. Useful filters:

```sh
grep '^HIT_HDS' extras/macos_openport_hds_probe_*.log
grep 'strings=' extras/macos_openport_hds_probe_*.log
```

The tester performs the same K-line setup used by the Windows tester:

- OpenPort `ato3 512 10400 0`
- EvoScan-compatible ISO9141 timing config
- broad pass filter
- pre-init `01 00` wake/probe
- five-baud init with address `0x33`
- Mode 01 and Mode 09 OBD requests

On the tested 2005 CR-V, generic Mode 01 works and Mode 09 PID `00` responds. The corrected native scanner also found Mode 09 calibration/CVN data over generic OBD:

- `09 04`: multi-frame calibration ID pieces, reconstructing as `37805-PPA-Q120`, `37850-RCA-A100` from returned text fragments.
- `09 06`: CVN bytes `4A FC 69 88`.
- `09 02`: VIN did not respond.

The safe scanner exhausts these read-only generic OBD services over ISO9141/K-line:

- `01 00..FF`: current powertrain data
- `02 00..FF`: freeze-frame data
- `03`: stored DTC read
- `05 00..FF`: oxygen sensor monitor data
- `06 00..FF`: on-board monitor data
- `07`: pending DTC read
- `09 00..FF`: vehicle information
- `0A`: permanent DTC read

It intentionally skips destructive/control services such as `04` Clear DTC and `08` Control Operation.

The larger probe also skips reset, security, write, clear, output-control, routine-control, and session-control services. In addition to the generic OBD scan above, it tries read/status style services that can expose ECU-specific data on older K-line ECUs:

- KWP/Honda `1A 80..9F`: ECU identification records.
- KWP/Honda `21 00..FF`: local data identifiers.
- KWP/UDS `22 F100..F11F`, `22 F180..F19F`, and `22 0000..00FF`: common read-data identifiers.
- DTC read candidates `17`, `18`, and `19` forms only; no clear-DTC requests.

The HDS-style probe is not an open-ended command sweep. It replays a curated set of read/status-style Honda K-line frames observed in successful HDS logs. On the tested CR-V, these HDS-observed requests returned:

- `25 04 E2 F5`: VIN `JHLRD77806C202401`.
- `7D 06 32 01 00 4A`: ECU/calibration string `37805-PPA-Q120`.
- Several `25 07 72 ...` records used by HDS for Honda-specific status/live data.

## Honda HDS / I-HDS Notes

Honda HDS/I-HDS may list J2534 providers from the Windows registry but still prefer Honda/SPX-specific provider names or capability flags. The HDS SPX MVCI patcher references this registry key:

Current HDS/I-HDS status: HDS/I-HDS diagnostics are confirmed working with this patched DLL on the tested 2005 Honda CR-V over ISO9141/K-line. The application still probes many ISO15765/CAN paths first, so startup/system selection can be slow, but it eventually reaches the working path: `protocolID: 3`, `10400` baud, `FIVE_BAUD_INIT 0x33`.

The key HDS compatibility fix is KWP checksum handling. HDS sent a KWP-style tester-present frame `80 46 F0 02 3E 02` without the trailing checksum byte. The DLL now appends a checksum only for ISO9141/ISO14230 KWP format-byte messages where the encoded length proves the checksum is absent. Already-checksummed frames, including known-good EvoScan generic OBD frames, are left unchanged.

Confirmed HDS/I-HDS read results from the tested CR-V include:

- VIN: `JHLRD77806C202401` from Honda K-line request `25 04 E2 F5`.
- ECU/calibration string: `37805-PPA-Q120` from Honda K-line request `7D 06 32 01 00 4A`.
- Honda-specific status/live data over repeated `25 07 72 ...` K-line requests.

This confirms diagnostics/live data, not ECU ROM dumping or flashing. Do not use HDS/I-HDS rewrite/flashing functions through this fork unless you have independently validated the exact ECU, protocol, backup, and recovery process.

```text
HKLM\SOFTWARE\WOW6432Node\PassThruSupport.04.04\SPX-Device1
```

After installing this fork, you can add Honda-compatible alias entries with:

```bat
extras\register_honda_aliases_windows_arm.cmd
```

This creates `SPX-Device1` pointing at `C:\J2534\OpenPort\j2534.dll` and adds Honda capability flags plus J2534 version metadata to the normal OpenPort provider. It does not modify an existing `Teradyne - GNA600` provider unless explicitly requested.

For older Honda vehicles where the application appears to prefer CAN/ISO15765 based on advertised provider capabilities, you can also register a separate K-line-only alias:

```bat
extras\register_kline_only_alias_windows_arm.cmd
```

This creates `OpenPort 2.0 ISO9141 K-Line` with `ISO9141=1`, `ISO14230=1`, `CAN=0`, and `ISO15765=0`. It does not remove or modify the normal all-protocol OpenPort provider. This may help applications that choose protocol/provider from registry capability flags, but it will not fix applications that are hard-coded to probe CAN for the selected vehicle.

For I-HDS D-PDU testing, launch I-HDS with logging set in the process environment instead of relying only on machine-wide environment propagation:

```bat
extras\launch_ihds_with_openport_logging.cmd
```

By default this runs `C:\i-HDS\Launcher.exe -selector`, which opens the same Diagnostic System selection menu as `C:\Users\Public\Desktop\Diagnostic System.lnk`. The launcher starts I-HDS with the executable's directory as the working directory and prepends `C:\J2534\OpenPort` to `PATH` so `ppl_j2534.exe` can resolve `libusb-1.0.dll` after loading `j2534.dll`. This matters because the Eclipse/Java application loads native helper DLLs during startup. If I-HDS fails before opening with an error like `UnsatisfiedLinkError: ca.beq.util.win32.registry.RegistryKey.testInitialized()V`, that is a Java registry JNI startup problem, not an OpenPort/J2534 problem.

To override the target manually, pass the executable and arguments explicitly:

```bat
extras\launch_ihds_with_openport_logging.cmd "C:\i-HDS\Launcher.exe" -selector
```

ProcMon may show `ppl_j2534.exe` reading the J2534 registry entries and successfully loading `C:\J2534\OpenPort\j2534.dll` before any vehicle communication happens. If `C:\J2534\op2.log` still remains empty after launching this way, the problem is no longer DLL discovery; I-HDS/D-PDU loaded the DLL but has not called into the OpenPort J2534 implementation yet.

## Honda Tuning Suite Notes

HTS can be launched with the same OpenPort DLL discovery/logging environment:

```bat
extras\launch_hts_with_openport_logging.cmd
```

If HTS is installed somewhere else, pass the executable path:

```bat
extras\launch_hts_with_openport_logging.cmd "C:\path\to\HTS2.15.exe"
```

On the tested 2005 CR-V, HTS can reach the OpenPort J2534 DLL when launched this way, but it chooses ISO15765/CAN at `500000` baud for the tested path instead of the working ISO9141/K-line transport. The K-line-only registry alias is worth testing if HTS exposes it as a selectable J2534 device, but do not assume it will override HTS vehicle/protocol logic.

For older vehicles that use classic HDS rather than the i-HDS Eclipse workflow, use the GenRad SysNav launcher first:

```bat
extras\launch_hds_sysnav_with_openport_logging.cmd
```

This runs `C:\GenRad\DiagSystem\Runtime\SysNav.exe` from the runtime directory. `SysNav.ini` starts `testman.exe /a:Setup /a:Vehicle`, which is the classic vehicle-selection workflow.

If SysNav opens but shows errors like `Registry database location not found`, `Could not find file \My Documents\Values`, or `WID-DIB-7`, repair the legacy GenRad registry paths from an Administrator Command Prompt. The repair writes both machine-wide and current-user legacy keys because different GenRad components read different roots:

```bat
extras\repair_hds_legacy_registry.cmd
```

If you specifically need the Scantool module shortcut path, use:

```bat
extras\launch_hds_scantool_with_openport_logging.cmd
```

This follows the installed Start Menu shortcut `Diagnostic System\Scantool.lnk`, which runs `C:\GenRad\DiagSystem\Launcher\Launcher.exe` with `C:\GenRad\DiagSystem\Runtime\Scantool.exe`. Classic HDS uses `C:\GenRad\DiagSystem\Runtime\DS253432-04.dll`, which reads the 32-bit `PassThruSupport.04.04` registry and loads the configured J2534 `FunctionLibrary`. For this path, register the Honda aliases with GNA600 replacement so the `Teradyne - GNA600` provider points at this fork:

```bat
extras\register_honda_aliases_windows_arm.cmd -ReplaceGNA600
```

Useful ProcMon filters for the I-HDS path are:

```text
Process Name is iHDS.exe
Process Name is ppl_j2534.exe
Path contains C:\J2534
Path contains j2534.dll
Path contains libusb
Path contains op2.log
Path contains PassThruSupport
Path contains D-PDU_API
Operation is Process Create
Operation is Load Image
```

If you need to test whether HDS/I-HDS is hardwired to the installed GNA600 provider, run:

```bat
extras\register_honda_aliases_windows_arm.cmd -ReplaceGNA600
```

This backs up the existing GNA600 registry key to `C:\J2534\gna600-backup.reg` before repointing it. Restore it with:

```bat
reg import C:\J2534\gna600-backup.reg
```

Use HDS/I-HDS for diagnostics first. Do not attempt ECU rewrite/flashing through this fork until communication is proven stable and the required J2534 calls have been verified in logs.

## Logging

Enable logging with:

```bat
setx LOG_ENABLE C:\J2534\op2.log /M
setx LIBUSB_DEBUG 3 /M
```

Close and reopen EvoScan after setting environment variables.

View logs with:

```bat
type C:\J2534\op2.log
```

For most applications, no log means the application did not load this DLL. For I-HDS/D-PDU, also check ProcMon `Load Image` events because `ppl_j2534.exe` can load the DLL before calling any J2534 entry point that produces a useful runtime log.

## Known Working Result

The current fork has been used to get EvoScan 2.9 on Windows ARM to:

- Load the replacement OpenPort DLL.
- Detect OpenPort 2.0.
- Read OpenPort firmware version.
- Read vehicle battery voltage.
- Connect ISO9141 at `10400` baud.
- Send and receive OpenPort USB command/loopback traffic.
- Reach and handle EvoScan's `FIVE_BAUD_INIT` path for ISO9141 address `0x33`.

Vehicle/application behavior still depends on correct vehicle profile, baud rate, protocol, ignition state, and wiring.

## Safety Notes

- Datalog first; do not flash first.
- Keep a battery charger on the vehicle for longer sessions.
- Keep the original EvoScan DLL backup.
- Keep a copy of a known-working replacement DLL.
- Avoid changing USB driver bindings immediately before a vehicle session.

Restore the original EvoScan DLL with:

```bat
copy /Y "C:\Program Files (x86)\EvoScan\EvoScan v2.9\op20pt32.dll.tactrix.bak" "C:\Program Files (x86)\EvoScan\EvoScan v2.9\op20pt32.dll"
```

## Linux Build

Linux support from the upstream project remains available:

```sh
cd j2534
make
```

USB permissions usually require a udev rule similar to:

```text
SUBSYSTEM=="usb", ATTRS{idVendor}=="0403", ATTR{idProduct}=="cc4d", GROUP="dialout", MODE="0666"
```

Your user must be in the `dialout` group or another group with access to the device.
