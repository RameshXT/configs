param([string]$LocalSource = "")

$ErrorActionPreference = "Stop"

function Write-UI {
    param([string]$Message, [string]$Type="INFO")
    switch ($Type) {
        "OK"    { Write-Host "[OK]: $Message" -ForegroundColor Green }
        "INFO"  { Write-Host "[INFO]: $Message" -ForegroundColor Cyan }
        "WARN"  { Write-Host "[WARNING]: $Message" -ForegroundColor Yellow }
        "ERROR" { Write-Host "[ERROR]: $Message" -ForegroundColor Red }
    }
}

$terminalPkg = "Microsoft.WindowsTerminal_8wekyb3d8bbwe"
$settingsPath = "$env:LOCALAPPDATA\Packages\$terminalPkg\LocalState\settings.json"

if (-not (Test-Path $settingsPath)) {
    Write-UI "Windows Terminal settings file not found at $settingsPath" "ERROR"
    exit 1
}

Write-Host ""
Write-UI "Starting Windows Terminal customization uninstallation..." "INFO"
Write-Host ""

$response = Read-Host "Are you sure you want to uninstall Windows Terminal customizations? (y/n)"
if ($response -notmatch '^[Yy]$') {
    Write-Host ""
    Write-UI "Uninstallation aborted by user." "INFO"
    exit 0
}

$originalBackup = "$settingsPath.bak.original"
$legacyBackups = Get-ChildItem -Path "$env:LOCALAPPDATA\Packages\$terminalPkg\LocalState" -Filter "settings.json.bak.*" 2>$null | Sort-Object CreationTime

if (Test-Path $originalBackup) {
    Copy-Item $originalBackup $settingsPath -Force
    Remove-Item $originalBackup -Force -ErrorAction SilentlyContinue
    Write-UI "Restored original pre-customization settings from $originalBackup" "OK"
} elseif ($legacyBackups.Count -gt 0) {
    $earliestBackup = $legacyBackups[0].FullName
    Copy-Item $earliestBackup $settingsPath -Force
    Write-UI "Restored earliest backup settings from $earliestBackup" "OK"
} else {
    $localSettingsStr = Get-Content $settingsPath -Raw
    $localSettings = $localSettingsStr | ConvertFrom-Json
    if ($localSettings.psobject.properties["useAcrylicInTabRow"]) { $localSettings.psobject.properties.Remove("useAcrylicInTabRow") }
    if ($localSettings.profiles -and $localSettings.profiles.defaults) {
        foreach ($p in @("useAcrylic", "opacity", "colorScheme", "cursorColor", "cursorShape", "selectionBackground", "bellStyle")) {
            if ($localSettings.profiles.defaults.psobject.properties[$p]) { $localSettings.profiles.defaults.psobject.properties.Remove($p) }
        }
    }
    $localSettings | ConvertTo-Json -Depth 20 | Set-Content $settingsPath -Encoding UTF8
    Write-UI "Reverted customized settings to stock Windows Terminal defaults" "OK"
}

Remove-Item "$env:LOCALAPPDATA\Packages\$terminalPkg\LocalState\settings.json.bak.*" -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "[DONE]: Uninstallation complete!" -ForegroundColor Green
Write-UI "Windows Terminal will automatically apply the restored settings!" "OK"
Write-Host ""
