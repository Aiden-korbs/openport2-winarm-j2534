param(
    [string]$DllPath = "C:\J2534\OpenPort\j2534.dll",
    [string]$KeyName = "OpenPort 2.0 ISO9141 K-Line"
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

Require-Admin

if (-not (Test-Path $DllPath)) {
    throw "J2534 DLL was not found: $DllPath. Run extras\install_windows_arm.cmd first, or pass -DllPath."
}

$baseKey = "HKLM:\SOFTWARE\WOW6432Node\PassThruSupport.04.04"
$keyPath = Join-Path $baseKey $KeyName
New-Item -Path $keyPath -Force | Out-Null

Set-J2534Value -KeyPath $keyPath -Name "FunctionLibrary" -Type String -Value $DllPath
Set-J2534Value -KeyPath $keyPath -Name "ConfigApplication" -Type String -Value ""
Set-J2534Value -KeyPath $keyPath -Name "Name" -Type String -Value $KeyName
Set-J2534Value -KeyPath $keyPath -Name "Vendor" -Type String -Value "OpenPort"
Set-J2534Value -KeyPath $keyPath -Name "APIVersion" -Type String -Value "04.04"
Set-J2534Value -KeyPath $keyPath -Name "DllVersion" -Type String -Value "1.0.0"
Set-J2534Value -KeyPath $keyPath -Name "DeviceId" -Type DWord -Value 0

# Advertise only the protocols that are useful on older Honda K-line vehicles.
Set-J2534Value -KeyPath $keyPath -Name "ISO9141" -Type DWord -Value 1
Set-J2534Value -KeyPath $keyPath -Name "ISO14230" -Type DWord -Value 1
Set-J2534Value -KeyPath $keyPath -Name "CAN" -Type DWord -Value 0
Set-J2534Value -KeyPath $keyPath -Name "ISO15765" -Type DWord -Value 0

# Honda/legacy apps sometimes look for these vendor capability flags.
Set-J2534Value -KeyPath $keyPath -Name "BYTE_ECHO" -Type DWord -Value 1
Set-J2534Value -KeyPath $keyPath -Name "UART_ECHO_BYTE_PS" -Type DWord -Value 1
Set-J2534Value -KeyPath $keyPath -Name "HONDA_DIAGH" -Type DWord -Value 1
Set-J2534Value -KeyPath $keyPath -Name "HONDA_DIAGH_PS" -Type DWord -Value 1

Write-Host "Registered K-line-only J2534 alias: $KeyName -> $DllPath"
Write-Host "Restart the diagnostic application before testing."
