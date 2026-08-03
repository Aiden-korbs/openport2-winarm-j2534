param(
    [string]$DllPath = "C:\J2534\OpenPort\j2534.dll",
    [switch]$ReplaceGNA600
)

$ErrorActionPreference = "Stop"

function Require-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Run this script from an Administrator PowerShell or Command Prompt."
    }
}

function Set-J2534Value {
    param(
        [string]$KeyPath,
        [string]$Name,
        [string]$Type,
        [object]$Value
    )

    New-ItemProperty -Path $KeyPath -Name $Name -PropertyType $Type -Value $Value -Force | Out-Null
}

function Add-HondaAlias {
    param(
        [string]$KeyName,
        [string]$DisplayName,
        [string]$Vendor,
        [string]$DllPath
    )

    $keyPath = "HKLM:\SOFTWARE\WOW6432Node\PassThruSupport.04.04\$KeyName"
    New-Item -Path $keyPath -Force | Out-Null

    Set-J2534Value -KeyPath $keyPath -Name "FunctionLibrary" -Type String -Value $DllPath
    Set-J2534Value -KeyPath $keyPath -Name "ConfigApplication" -Type String -Value ""
    Set-J2534Value -KeyPath $keyPath -Name "Name" -Type String -Value $DisplayName
    Set-J2534Value -KeyPath $keyPath -Name "Vendor" -Type String -Value $Vendor
    Set-J2534Value -KeyPath $keyPath -Name "APIVersion" -Type String -Value "04.04"
    Set-J2534Value -KeyPath $keyPath -Name "DllVersion" -Type String -Value "1.0.0"
    Set-J2534Value -KeyPath $keyPath -Name "DeviceId" -Type DWord -Value 0
    Set-J2534Value -KeyPath $keyPath -Name "CAN" -Type DWord -Value 1
    Set-J2534Value -KeyPath $keyPath -Name "ISO14230" -Type DWord -Value 1
    Set-J2534Value -KeyPath $keyPath -Name "ISO15765" -Type DWord -Value 1
    Set-J2534Value -KeyPath $keyPath -Name "ISO9141" -Type DWord -Value 1
    Set-J2534Value -KeyPath $keyPath -Name "BYTE_ECHO" -Type DWord -Value 1
    Set-J2534Value -KeyPath $keyPath -Name "UART_ECHO_BYTE_PS" -Type DWord -Value 1
    Set-J2534Value -KeyPath $keyPath -Name "HONDA_DIAGH" -Type DWord -Value 1
    Set-J2534Value -KeyPath $keyPath -Name "HONDA_DIAGH_PS" -Type DWord -Value 1

    Write-Host "Registered Honda J2534 alias: $KeyName -> $DllPath"
}

Require-Admin

if (-not (Test-Path $DllPath)) {
    throw "J2534 DLL was not found: $DllPath. Run extras\install_windows_arm.cmd first, or pass -DllPath."
}

Write-Host "Registering Honda HDS/I-HDS J2534 aliases"

$baseKey = "HKLM:\SOFTWARE\WOW6432Node\PassThruSupport.04.04"
New-Item -Path $baseKey -Force | Out-Null

# Honda's SPX MVCI patcher references this exact J2534 provider key.
Add-HondaAlias -KeyName "SPX-Device1" -DisplayName "SPX-Device1" -Vendor "SPX" -DllPath $DllPath

$romRaiderKey = Join-Path $baseKey "RomRaider - OP2 J2534"
if (Test-Path $romRaiderKey) {
    Set-J2534Value -KeyPath $romRaiderKey -Name "BYTE_ECHO" -Type DWord -Value 1
    Set-J2534Value -KeyPath $romRaiderKey -Name "UART_ECHO_BYTE_PS" -Type DWord -Value 1
    Set-J2534Value -KeyPath $romRaiderKey -Name "HONDA_DIAGH" -Type DWord -Value 1
    Set-J2534Value -KeyPath $romRaiderKey -Name "HONDA_DIAGH_PS" -Type DWord -Value 1
    Set-J2534Value -KeyPath $romRaiderKey -Name "APIVersion" -Type String -Value "04.04"
    Set-J2534Value -KeyPath $romRaiderKey -Name "DllVersion" -Type String -Value "1.0.0"
    Write-Host "Updated existing OpenPort provider with Honda capability flags."
}

if ($ReplaceGNA600) {
    $gnaKeyName = "Teradyne - GNA600"
    $gnaKey = Join-Path $baseKey $gnaKeyName
    $backupPath = "C:\J2534\gna600-backup.reg"

    if (Test-Path $gnaKey) {
        New-Item -ItemType Directory -Path (Split-Path $backupPath -Parent) -Force | Out-Null
        & reg.exe export "HKLM\SOFTWARE\WOW6432Node\PassThruSupport.04.04\$gnaKeyName" $backupPath /y | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "Failed to back up GNA600 registry key with exit code $LASTEXITCODE" }
        Set-J2534Value -KeyPath $gnaKey -Name "FunctionLibrary" -Type String -Value $DllPath
        Write-Warning "Repointed existing GNA600 provider to $DllPath. Restore with: reg import $backupPath"
    } else {
        Add-HondaAlias -KeyName $gnaKeyName -DisplayName "GNA600" -Vendor "Teradyne" -DllPath $DllPath
    }
}

Write-Host "Done. Restart HDS/I-HDS before testing."
