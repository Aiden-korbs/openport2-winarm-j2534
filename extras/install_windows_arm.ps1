param(
    [string]$EvoScanDir = "C:\Program Files (x86)\EvoScan\EvoScan v2.9",
    [string]$InstallDir = "C:\J2534\OpenPort",
    [string]$LogFile = "C:\J2534\op2.log",
    [string]$MsBuildPath,
    [string]$PlatformToolset,
    [string]$LibusbVersion = "1.0.30",
    [string]$LibusbSha256 = "7fb1dfec805b97983763d7d0ae244320da12add1003d4249c96cc4d586398c79",
    [switch]$NoBuild,
    [switch]$NoEvoScan,
    [switch]$NoRegistry,
    [switch]$NoLibusbDownload,
    [switch]$InstallMissingPrereqs,
    [switch]$CheckOnly
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
        "C:\Program Files\Microsoft Visual Studio\18\BuildTools\MSBuild\Current\Bin\MSBuild.exe",
        "C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\MSBuild.exe",
        "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe",
        "C:\Program Files\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe",
        "C:\Program Files (x86)\Microsoft Visual Studio\17\BuildTools\MSBuild\Current\Bin\MSBuild.exe",
        "C:\Program Files\Microsoft Visual Studio\17\BuildTools\MSBuild\Current\Bin\MSBuild.exe",
        "C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe",
        "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\MSBuild\Current\Bin\MSBuild.exe"
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) { return $candidate }
    }

    $vswhereCandidates = @(
        "C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe",
        "C:\Program Files\Microsoft Visual Studio\Installer\vswhere.exe"
    )

    foreach ($vswhere in $vswhereCandidates) {
        if (-not (Test-Path $vswhere)) { continue }
        $found = & $vswhere -latest -products * -requires Microsoft.Component.MSBuild -find "MSBuild\Current\Bin\MSBuild.exe" 2>$null | Select-Object -First 1
        if ($found -and (Test-Path $found)) { return $found }
    }

    $cmd = Get-Command msbuild.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    return $null
}

function Find-Winget {
    $cmd = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Test-SuccessExitCode {
    param([int]$ExitCode)

    return ($ExitCode -eq 0 -or $ExitCode -eq 3010)
}

function Write-RebootRecommended {
    param([int]$ExitCode)

    if ($ExitCode -eq 3010) {
        Write-Warning "Installer returned 3010: installation succeeded, but Windows recommends a restart before continuing."
    }
}

function Find-VCToolsCompiler {
    $roots = @(
        "C:\Program Files\Microsoft Visual Studio\18\BuildTools",
        "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools",
        "C:\Program Files\Microsoft Visual Studio\18\Community",
        "C:\Program Files (x86)\Microsoft Visual Studio\18\Community",
        "C:\Program Files\Microsoft Visual Studio\2022\BuildTools",
        "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools",
        "C:\Program Files\Microsoft Visual Studio\2022\Community",
        "C:\Program Files (x86)\Microsoft Visual Studio\2022\Community",
        "C:\Program Files\Microsoft Visual Studio\2019\BuildTools",
        "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools"
    )

    foreach ($root in $roots) {
        if (-not (Test-Path $root)) { continue }
        $compilerPath = Join-Path $root "VC\Tools\MSVC\*\bin\Host*\x86\cl.exe"
        $compiler = Get-ChildItem -Path $compilerPath -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($compiler) { return $compiler.FullName }
    }

    $cmd = Get-Command cl.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    return $null
}

function Find-PlatformToolset {
    param(
        [string]$MsBuild,
        [string]$RequestedToolset
    )

    if ($RequestedToolset) { return $RequestedToolset }
    if (-not $MsBuild) { return $null }

    $msbuildDir = Split-Path $MsBuild -Parent
    $currentDir = Split-Path $msbuildDir -Parent
    $msbuildRoot = Split-Path $currentDir -Parent
    $installRoot = Split-Path $msbuildRoot -Parent
    $toolsetRoot = Join-Path $installRoot "MSBuild\Microsoft\VC"

    if (-not (Test-Path $toolsetRoot)) { return $null }

    $toolsets = Get-ChildItem -Path (Join-Path $toolsetRoot "*\Platforms\Win32\PlatformToolsets") -Directory -ErrorAction SilentlyContinue |
        ForEach-Object { Get-ChildItem -Path $_.FullName -Directory -ErrorAction SilentlyContinue } |
        Where-Object { $_.Name -match '^v\d+$' } |
        Sort-Object @{ Expression = { [int]($_.Name.Substring(1)) }; Descending = $true } |
        Select-Object -ExpandProperty Name -Unique

    return ($toolsets | Select-Object -First 1)
}

function Install-7ZipWithWinget {
    $winget = Find-Winget
    if (-not $winget) {
        throw "winget was not found. Install 7-Zip manually from https://www.7-zip.org/ and re-run this installer."
    }

    Write-Host "Installing 7-Zip with winget..."
    & $winget install --id 7zip.7zip -e --accept-source-agreements --accept-package-agreements
    if (-not (Test-SuccessExitCode -ExitCode $LASTEXITCODE)) {
        throw "winget failed to install 7-Zip with exit code $LASTEXITCODE"
    }
    Write-RebootRecommended -ExitCode $LASTEXITCODE
}

function Install-BuildToolsWithWinget {
    $winget = Find-Winget
    if (-not $winget) {
        throw "winget was not found. Install Visual Studio Build Tools manually and include the Desktop C++ workload."
    }

    Write-Host "Installing Visual Studio 2022 Build Tools with winget..."
    & $winget install --id Microsoft.VisualStudio.2022.BuildTools -e --accept-source-agreements --accept-package-agreements
    if (-not (Test-SuccessExitCode -ExitCode $LASTEXITCODE)) {
        throw "winget failed to install Visual Studio Build Tools with exit code $LASTEXITCODE"
    }
    Write-RebootRecommended -ExitCode $LASTEXITCODE

    $vsInstallerCandidates = @(
        "C:\Program Files (x86)\Microsoft Visual Studio\Installer\vs_installer.exe",
        "C:\Program Files\Microsoft Visual Studio\Installer\vs_installer.exe"
    )
    $vsInstaller = $vsInstallerCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $vsInstaller) {
        throw "Visual Studio Installer was not found after Build Tools install. Open Visual Studio Installer manually and add the Desktop C++ workload."
    }

    $buildToolsCandidates = @(
        "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools",
        "C:\Program Files\Microsoft Visual Studio\2022\BuildTools"
    )
    $buildToolsPath = $buildToolsCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $buildToolsPath) {
        throw "Visual Studio Build Tools install path was not found after installation. Open Visual Studio Installer manually and add the Desktop C++ workload."
    }

    Write-Host "Adding Desktop C++ workload to Build Tools..."
    & $vsInstaller modify --installPath $buildToolsPath --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended --passive --norestart
    if (-not (Test-SuccessExitCode -ExitCode $LASTEXITCODE)) {
        throw "Visual Studio Installer failed to add the Desktop C++ workload with exit code $LASTEXITCODE"
    }
    Write-RebootRecommended -ExitCode $LASTEXITCODE
}

function Show-PrereqHelp {
    param(
        [bool]$NeedBuiltDll,
        [bool]$NeedLibusbManual,
        [bool]$Need7Zip,
        [bool]$NeedMSBuild,
        [bool]$NeedVCTools,
        [string]$MsBuildReason
    )

    Write-Host ""
    Write-Host "Missing prerequisites:" -ForegroundColor Yellow

    if ($NeedBuiltDll) {
        Write-Host "- Release\j2534.dll is missing, but -NoBuild was specified."
        Write-Host "  Remove -NoBuild so the installer can build it, or copy a previously built Release\j2534.dll into this repo."
    }

    if ($NeedLibusbManual) {
        Write-Host "- libusb files are missing and automatic download was disabled with -NoLibusbDownload."
        Write-Host "  Extract the official libusb release into the repo layout documented in README.md, or remove -NoLibusbDownload."
    }

    if ($Need7Zip) {
        Write-Host "- 7-Zip is required to automatically extract libusb."
        Write-Host "  Install with: winget install --id 7zip.7zip -e"
    }

    if ($NeedMSBuild) {
        Write-Host "- MSBuild with the Desktop C++ workload is required to build Release|x86."
        if ($MsBuildReason) { Write-Host "  $MsBuildReason" }
        Write-Host "  Install Build Tools with: winget install --id Microsoft.VisualStudio.2022.BuildTools -e"
        Write-Host "  Then add C++ workload with:"
        Write-Host '  "C:\Program Files (x86)\Microsoft Visual Studio\Installer\vs_installer.exe" modify --installPath "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools" --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended --passive --norestart'
        Write-Host "  If that returns exit code 3010, restart Windows, then re-run this installer."
    } elseif ($NeedVCTools) {
        Write-Host "- Visual Studio is installed, but the C++ compiler/toolset was not found."
        Write-Host "  Add the Desktop C++ workload with:"
        Write-Host '  "C:\Program Files (x86)\Microsoft Visual Studio\Installer\vs_installer.exe" modify --installPath "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools" --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended --passive --norestart'
        Write-Host "  If that returns exit code 3010, restart Windows, then re-run this installer."
    }

    Write-Host ""
    Write-Host "Or re-run this installer with -InstallMissingPrereqs to install missing prerequisites with winget where possible."
}

function Test-MSBuildAvailable {
    param([string]$RequestedPath)

    try {
        $found = Find-MSBuild -RequestedPath $RequestedPath
        return $found
    } catch {
        return $null
    }
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

$needsBuiltDll = $NoBuild -and (-not (Test-Path $builtDll))
$needsLibusbLayout = (-not (Test-Path $builtLibusb)) -or ((-not $NoBuild) -and ((-not (Test-Path $libusbHeader)) -or (-not (Test-Path $libusbImport))))
$needsLibusbManual = $needsLibusbLayout -and $NoLibusbDownload
$needs7Zip = $needsLibusbLayout -and (-not $NoLibusbDownload) -and (-not (Find-7Zip))
$msbuildForBuild = $null
$vcCompilerForBuild = $null
$toolsetForBuild = $null
$needsMSBuild = $false
$needsVCTools = $false

if (-not $NoBuild) {
    $msbuildForBuild = Test-MSBuildAvailable -RequestedPath $MsBuildPath
    $vcCompilerForBuild = Find-VCToolsCompiler
    $toolsetForBuild = Find-PlatformToolset -MsBuild $msbuildForBuild -RequestedToolset $PlatformToolset
    $needsMSBuild = -not $msbuildForBuild
    $needsVCTools = (-not $needsMSBuild) -and (-not $vcCompilerForBuild)
}

if ($needsBuiltDll -or $needsLibusbManual -or $needs7Zip -or $needsMSBuild -or $needsVCTools) {
    if ($InstallMissingPrereqs) {
        if ($needsBuiltDll) {
            throw "Release\j2534.dll is missing and -NoBuild was specified. Remove -NoBuild so the installer can build it, or copy a previously built DLL into Release\."
        }
        if ($needsLibusbManual) {
            throw "libusb files are missing and -NoLibusbDownload was specified. Remove -NoLibusbDownload or install libusb manually."
        }
        if ($needs7Zip) {
            Install-7ZipWithWinget
            if (-not (Find-7Zip)) { throw "7-Zip still was not found after installation. Close and reopen the terminal, then re-run this installer." }
        }
        if ($needsMSBuild -or $needsVCTools) {
            Install-BuildToolsWithWinget
            $msbuildForBuild = Test-MSBuildAvailable -RequestedPath $MsBuildPath
            $vcCompilerForBuild = Find-VCToolsCompiler
            $toolsetForBuild = Find-PlatformToolset -MsBuild $msbuildForBuild -RequestedToolset $PlatformToolset
            if (-not $msbuildForBuild) { throw "MSBuild still was not found after Build Tools installation. Close and reopen the terminal, then re-run this installer." }
            if (-not $vcCompilerForBuild) { throw "The C++ compiler still was not found after Build Tools installation. Close and reopen the terminal, then re-run this installer." }
        }
    } else {
        Show-PrereqHelp -NeedBuiltDll:$needsBuiltDll -NeedLibusbManual:$needsLibusbManual -Need7Zip:$needs7Zip -NeedMSBuild:$needsMSBuild -NeedVCTools:$needsVCTools -MsBuildReason $(if ($MsBuildPath) { "Requested path was not found: $MsBuildPath" } else { "MSBuild was not found in common Visual Studio locations or PATH." })
        throw "Missing prerequisites. Install them, or re-run with -InstallMissingPrereqs."
    }
}

if ($CheckOnly) {
    Write-Host "Prerequisite check passed."
    Write-Host "Release\j2534.dll: $(if (Test-Path $builtDll) { 'present' } elseif ($NoBuild) { 'missing' } else { 'will build during install' })"
    Write-Host "libusb layout: $(if ($needsLibusbLayout) { 'will download/extract during install' } else { 'present' })"
    Write-Host "7-Zip: $(if (Find-7Zip) { Find-7Zip } else { 'not needed/found' })"
    Write-Host "MSBuild: $(if ($msbuildForBuild) { $msbuildForBuild } else { 'not needed' })"
    Write-Host "C++ compiler: $(if ($vcCompilerForBuild) { $vcCompilerForBuild } else { 'not needed' })"
    Write-Host "Platform toolset: $(if ($toolsetForBuild) { $toolsetForBuild } else { 'not needed/found' })"
    Write-Host "EvoScan: $(if ($NoEvoScan) { 'skipped' } elseif (Test-Path (Join-Path $EvoScanDir 'EvoScan.exe')) { $EvoScanDir } else { 'not found; installer will skip EvoScan replacement' })"
    return
}

if ($needsLibusbLayout) {
    Ensure-LibusbLayout -RepoRoot $repoRoot -HeaderPath $libusbHeader -ImportLibPath $libusbImport -DllPath $builtLibusb -Version $LibusbVersion -Sha256 $LibusbSha256 -NoDownload:$NoLibusbDownload
}

if (-not $NoBuild) {
    foreach ($required in @($solutionPath, $libusbHeader, $libusbImport, $builtLibusb)) {
        if (-not (Test-Path $required)) {
            throw "Missing build dependency: $required`nExtract the x86 libusb release files into the repo layout documented in README.md, or run with -NoBuild if j2534.dll is already built."
        }
    }

    $msbuild = $msbuildForBuild
    if (-not $msbuild) { $msbuild = Find-MSBuild -RequestedPath $MsBuildPath }
    if (-not $msbuild) {
        throw "MSBuild was not found. Install Visual Studio Build Tools with the Desktop C++ workload, or pass -MsBuildPath."
    }

    if (-not $toolsetForBuild) {
        $toolsetForBuild = Find-PlatformToolset -MsBuild $msbuild -RequestedToolset $PlatformToolset
    }

    Write-Host "Rebuilding Release|x86 with: $msbuild"
    if ($toolsetForBuild) {
        Write-Host "Using PlatformToolset=$toolsetForBuild"
        & $msbuild $solutionPath /t:Rebuild /p:Configuration=Release /p:Platform=x86 /p:PlatformToolset=$toolsetForBuild
    } else {
        & $msbuild $solutionPath /t:Rebuild /p:Configuration=Release /p:Platform=x86
    }
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
