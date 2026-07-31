# OpenPort 2.0 J2534 for Windows ARM

This is a Windows ARM focused fork of `j2534`, a libusb-based SAE J2534-1 library for the Tactrix OpenPort 2.0 cable.

The goal of this fork is to make an OpenPort 2.0 usable from 32-bit x86 diagnostic applications running under Windows 11 ARM emulation, where the original Tactrix x86/x64 kernel driver cannot be loaded.

Tested target setup:

- Apple Silicon Mac running a Windows 11 ARM VM
- OpenPort 2.0 USB device attached to the VM
- OpenPort bound to Microsoft WinUSB with Zadig
- 32-bit x86 build of this DLL
- 32-bit x86 `libusb-1.0.dll`
- EvoScan 2.9 using this DLL as `op20pt32.dll`

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
- Basic support for `CLEAR_MSG_FILTERS`.
- EvoScan/OpenPort compatibility work, including `READ_VBATT` before channel connect and experimental `FIVE_BAUD_INIT` support.
- Diagnostic logging on DLL load and J2534 calls via `LOG_ENABLE`.

## Why Windows ARM Needs This

Windows ARM can run many x86 user-mode applications and DLLs, but it cannot load x86/x64 kernel drivers. The normal Tactrix OpenPort driver path depends on a kernel driver, so it is not suitable for Windows ARM VMs.

This fork uses WinUSB plus libusb from an emulated x86 DLL. The USB driver remains native Windows, while the diagnostic application and this J2534 DLL run as x86 user-mode code.

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

If the project complains about an unavailable platform toolset, retarget `j2534\j2534.vcxproj` to the installed toolset, for example `v145`.

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

If the required libusb files are missing, the installer downloads the official libusb release from GitHub, verifies its SHA-256 hash, extracts it with 7-Zip, and copies the x86 files into the expected repo layout. Install 7-Zip first if you want this automatic path.

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

If no log appears, the application did not load this DLL.

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
