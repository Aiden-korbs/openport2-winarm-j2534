param(
    [string]$EvoScanDir = "C:\Program Files (x86)\EvoScan\EvoScan v2.9",
    [string]$InstallDir = "C:\J2534\OpenPort",
    [string]$LogFile = "C:\J2534\op2.log",
    [string]$MsBuildPath,
    [string]$LibusbVersion = "1.0.30",
    [string]$LibusbSha256 = "7fb1dfec805b97983763d7d0ae244320da12add1003d4249c96cc4d586398c79",
    [switch]$NoBuild,
    [switch]$NoEvoScan,
    [switch]$NoRegistry,
    [switch]$NoLibusbDownload
)

$ErrorActionPreference = "Stop"

function Require-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Run this script from an Administrator PowerShell or Command Prompt."
    }
}

function Find-MSBuild {
    param([string]$RequestedPath)

    if ($RequestedPath) {
        if (Test-Path $RequestedPath) { return $RequestedPath }
        throw "MSBuild not found at: $RequestedPath"
    }

    $candidates = @(
        "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\MSBuild\Current\Bin\MSBuild.exe",
        "C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\MSBuild.exe",
        "C:\Program Files (x86)\Microsoft Visual Studio\17\BuildTools\MSBuild\Current\Bin\MSBuild.exe",
        "C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe",
        "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\MSBuild\Current\Bin\MSBuild.exe"
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) { return $candidate }
    }

    $cmd = Get-Command msbuild.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    return $null
}

function Add-J2534Registry {
    param([string]$DllPath)

    $keyPath = "HKLM:\SOFTWARE\WOW6432Node\PassThruSupport.04.04\RomRaider - OP2 J2534"
    New-Item -Path $keyPath -Force | Out-Null
    New-ItemProperty -Path $keyPath -Name "FunctionLibrary" -PropertyType String -Value $DllPath -Force | Out-Null
    New-ItemProperty -Path $keyPath -Name "ConfigApplication" -PropertyType String -Value "" -Force | Out-Null
    New-ItemProperty -Path $keyPath -Name "Name" -PropertyType String -Value "Openport 2.0 J2534" -Force | Out-Null
    New-ItemProperty -Path $keyPath -Name "Vendor" -PropertyType String -Value "RomRaider" -Force | Out-Null
    New-ItemProperty -Path $keyPath -Name "CAN" -PropertyType DWord -Value 1 -Force | Out-Null
    New-ItemProperty -Path $keyPath -Name "ISO14230" -PropertyType DWord -Value 1 -Force | Out-Null
    New-ItemProperty -Path $keyPath -Name "ISO15765" -PropertyType DWord -Value 1 -Force | Out-Null
    New-ItemProperty -Path $keyPath -Name "ISO9141" -PropertyType DWord -Value 1 -Force | Out-Null
}

function Find-7Zip {
    $cmd = Get-Command 7z.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $candidates = @(
        "C:\Program Files\7-Zip\7z.exe",
        "C:\Program Files (x86)\7-Zip\7z.exe"
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) { return $candidate }
    }

    return $null
}

function Ensure-LibusbLayout {
    param(
        [string]$RepoRoot,
        [string]$HeaderPath,
        [string]$ImportLibPath,
        [string]$DllPath,
        [string]$Version,
        [string]$Sha256,
        [switch]$NoDownload
    )

    if ((Test-Path $HeaderPath) -and (Test-Path $ImportLibPath) -and (Test-Path $DllPath)) {
        Write-Host "libusb files already present."
        return
    }

    if ($NoDownload) {
        throw "libusb files are missing and -NoLibusbDownload was specified. See README.md for the required libusb layout."
    }

    $sevenZip = Find-7Zip
    if (-not $sevenZip) {
        throw "libusb files are missing and 7-Zip was not found. Install 7-Zip, then re-run this script, or manually extract libusb into the repo layout documented in README.md."
    }

    $url = "https://github.com/libusb/libusb/releases/download/v$Version/libusb-$Version.7z"
    $workDir = Join-Path ([IO.Path]::GetTempPath()) "openport2-winarm-j2534-libusb"
    $archive = Join-Path $workDir "libusb-$Version.7z"
    $extractDir = Join-Path $workDir "extracted"

    New-Item -ItemType Directory -Path $workDir -Force | Out-Null
    Remove-Item -Path $extractDir -Recurse -Force -ErrorAction SilentlyContinue

    if (-not (Test-Path $archive)) {
        Write-Host "Downloading libusb $Version from: $url"
        Invoke-WebRequest -Uri $url -OutFile $archive
    } else {
        Write-Host "Using cached libusb archive: $archive"
    }

    $actualSha = (Get-FileHash -Algorithm SHA256 -Path $archive).Hash.ToLowerInvariant()
    if ($actualSha -ne $Sha256.ToLowerInvariant()) {
        Remove-Item -Path $archive -Force -ErrorAction SilentlyContinue
        throw "libusb archive SHA-256 mismatch. Expected $Sha256, got $actualSha. Deleted downloaded archive."
    }
    Write-Host "Verified libusb archive SHA-256."

    Write-Host "Extracting libusb with: $sevenZip"
    & $sevenZip x -y $archive "-o$extractDir" | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "7-Zip failed to extract libusb archive with exit code $LASTEXITCODE"
    }

    $sourceHeader = Join-Path $extractDir "include\libusb.h"
    $sourceDll = Join-Path $extractDir "VS2022\MS32\dll\libusb-1.0.dll"
    $sourceImportLib = Join-Path $extractDir "VS2022\MS32\dll\libusb-1.0.lib"

    if (-not (Test-Path $sourceDll) -or -not (Test-Path $sourceImportLib)) {
        $sourceDll = Join-Path $extractDir "VS2019\MS32\dll\libusb-1.0.dll"
        $sourceImportLib = Join-Path $extractDir "VS2019\MS32\dll\libusb-1.0.lib"
    }

    foreach ($required in @($sourceHeader, $sourceDll, $sourceImportLib)) {
        if (-not (Test-Path $required)) {
            throw "Required libusb file was not found after extraction: $required"
        }
    }

    New-Item -ItemType Directory -Path (Split-Path $HeaderPath -Parent) -Force | Out-Null
    New-Item -ItemType Directory -Path (Split-Path $ImportLibPath -Parent) -Force | Out-Null

    Copy-Item -Path $sourceHeader -Destination $HeaderPath -Force
    Copy-Item -Path $sourceDll -Destination $DllPath -Force
    Copy-Item -Path $sourceImportLib -Destination $ImportLibPath -Force

    Write-Host "Installed libusb files into repo layout."
}

Require-Admin

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$solutionPath = Join-Path $repoRoot "j2534.sln"
$builtDll = Join-Path $repoRoot "Release\j2534.dll"
$builtLibusb = Join-Path $repoRoot "libusb\MS32\Release\dll\libusb-1.0.dll"
$libusbImport = Join-Path $repoRoot "libusb\MS32\Release\dll\libusb-1.0.lib"
$libusbHeader = Join-Path $repoRoot "libusb\include\libusb-1.0\libusb.h"

Write-Host "OpenPort 2.0 J2534 Windows ARM installer"
Write-Host "Repo: $repoRoot"

if ((-not (Test-Path $builtLibusb)) -or ((-not $NoBuild) -and ((-not (Test-Path $libusbHeader)) -or (-not (Test-Path $libusbImport))))) {
    Ensure-LibusbLayout -RepoRoot $repoRoot -HeaderPath $libusbHeader -ImportLibPath $libusbImport -DllPath $builtLibusb -Version $LibusbVersion -Sha256 $LibusbSha256 -NoDownload:$NoLibusbDownload
}

if (-not $NoBuild) {
    foreach ($required in @($solutionPath, $libusbHeader, $libusbImport, $builtLibusb)) {
        if (-not (Test-Path $required)) {
            throw "Missing build dependency: $required`nExtract the x86 libusb release files into the repo layout documented in README.md, or run with -NoBuild if j2534.dll is already built."
        }
    }

    $msbuild = Find-MSBuild -RequestedPath $MsBuildPath
    if (-not $msbuild) {
        throw "MSBuild was not found. Install Visual Studio Build Tools with the Desktop C++ workload, or pass -MsBuildPath."
    }

    Write-Host "Building Release|x86 with: $msbuild"
    & $msbuild $solutionPath /p:Configuration=Release /p:Platform=x86
    if ($LASTEXITCODE -ne 0) {
        throw "MSBuild failed with exit code $LASTEXITCODE"
    }
}

if (-not (Test-Path $builtDll)) {
    throw "Built DLL not found: $builtDll"
}
if (-not (Test-Path $builtLibusb)) {
    throw "libusb runtime not found: $builtLibusb"
}

New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path $LogFile -Parent) -Force | Out-Null

$installedDll = Join-Path $InstallDir "j2534.dll"
$installedLibusb = Join-Path $InstallDir "libusb-1.0.dll"
Copy-Item -Path $builtDll -Destination $installedDll -Force
Copy-Item -Path $builtLibusb -Destination $installedLibusb -Force
Write-Host "Installed: $installedDll"
Write-Host "Installed: $installedLibusb"

if (-not $NoRegistry) {
    Add-J2534Registry -DllPath $installedDll
    Write-Host "Registered 32-bit J2534 provider."
}

[Environment]::SetEnvironmentVariable("LOG_ENABLE", $LogFile, "Machine")
[Environment]::SetEnvironmentVariable("LIBUSB_DEBUG", "3", "Machine")
Write-Host "Enabled LOG_ENABLE=$LogFile"

if (-not $NoEvoScan) {
    if (-not (Test-Path (Join-Path $EvoScanDir "EvoScan.exe"))) {
        Write-Warning "EvoScan.exe was not found in: $EvoScanDir"
        Write-Warning "Skipping EvoScan replacement. Re-run with -EvoScanDir when installed."
    } else {
        Stop-Process -Name "EvoScan" -Force -ErrorAction SilentlyContinue

        $evoscanDll = Join-Path $EvoScanDir "op20pt32.dll"
        $evoscanBackup = Join-Path $EvoScanDir "op20pt32.dll.tactrix.bak"
        $evoscanLibusb = Join-Path $EvoScanDir "libusb-1.0.dll"

        if ((Test-Path $evoscanDll) -and -not (Test-Path $evoscanBackup)) {
            Copy-Item -Path $evoscanDll -Destination $evoscanBackup -Force
            Write-Host "Backed up original EvoScan DLL: $evoscanBackup"
        }

        Copy-Item -Path $builtDll -Destination $evoscanDll -Force
        Copy-Item -Path $builtLibusb -Destination $evoscanLibusb -Force
        Write-Host "Installed EvoScan replacement: $evoscanDll"
    }
}

Write-Host ""
Write-Host "OpenPort USB device status:"
$device = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -like "USB\VID_0403&PID_CC4D*" }
if ($device) {
    $device | Format-List Status,Class,FriendlyName,InstanceId
} else {
    Write-Warning "OpenPort 2.0 USB device was not found. Attach it to the VM and bind it to WinUSB with Zadig."
}

Write-Host "Done. Reopen EvoScan after this script so it sees the new environment variables."
Write-Host "Log file: $LogFile"
