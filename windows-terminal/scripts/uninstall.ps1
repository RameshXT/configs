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

$backups = Get-ChildItem -Path "$env:LOCALAPPDATA\Packages\$terminalPkg\LocalState" -Filter "settings.json.bak.*" 2>$null | Sort-Object CreationTime -Descending
if ($backups.Count -gt 0) {
    $latestBackup = $backups[0].FullName
    Copy-Item $latestBackup $settingsPath -Force
    Write-UI "Restored latest backup settings from $latestBackup" "OK"
} else {
    Write-UI "No backup file found to restore" "WARN"
}

Write-Host ""
Write-Host "[DONE]: Uninstallation complete!" -ForegroundColor Green
Write-UI "Windows Terminal will automatically apply the restored settings!" "OK"
Write-Host ""
