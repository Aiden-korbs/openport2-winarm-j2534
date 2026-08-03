param()

$ErrorActionPreference = "Stop"

function Require-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Run this script from an Administrator PowerShell or Command Prompt."
    }
}

Require-Admin

Write-Host "EvoScan Windows ARM preparation"
Write-Host "Checking .NET Framework 3.5 / 2.0 support..."

$feature = Get-WindowsOptionalFeature -Online -FeatureName NetFx3 -ErrorAction SilentlyContinue
if ($feature -and $feature.State -eq "Enabled") {
    Write-Host ".NET Framework 3.5 is already enabled. This includes .NET 2.0."
} else {
    Write-Host "Enabling .NET Framework 3.5. This includes .NET 2.0 required by the EvoScan installer."
    & dism.exe /Online /Enable-Feature /FeatureName:NetFx3 /All
    if ($LASTEXITCODE -ne 0) {
        throw "DISM failed to enable NetFx3 with exit code $LASTEXITCODE. Try Control Panel -> Programs -> Turn Windows features on or off -> .NET Framework 3.5."
    }
}

Write-Host ""
Write-Host "Next steps:"
Write-Host "1. Run the EvoScan 2.9 installer. If it asks to download .NET 2.0, click No."
Write-Host "2. Run extras\install_windows_arm.cmd with -EvoScanDir after EvoScan is installed."
