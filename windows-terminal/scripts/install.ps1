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

Write-UI "Starting Windows Terminal customization installer..." "INFO"

# During dev/testing, we can run this locally without hitting GitHub cache
# If run with a local path parameter, it uses that instead of downloading

if ($LocalSource) {
    Write-UI "Using local settings source: $LocalSource" "INFO"
    $customJsonStr = Get-Content $LocalSource -Raw
} else {
    $repoUrl = "https://raw.githubusercontent.com/RameshXT/configs/main/windows-terminal/assets/custom-settings.json"
    Write-UI "Fetching custom settings from GitHub..." "INFO"
    $response = Invoke-WebRequest -Uri $repoUrl -UseBasicParsing
    $customJsonStr = $response.Content
}

$customSettings = $customJsonStr | ConvertFrom-Json
$localSettingsStr = Get-Content $settingsPath -Raw
$localSettings = $localSettingsStr | ConvertFrom-Json

# Backup
$ts = Get-Date -Format 'yyyyMMddHHmmss'
$backupPath = "$settingsPath.bak.$ts"
Copy-Item $settingsPath $backupPath
Write-UI "Backed up existing settings to $backupPath" "OK"

Write-UI "Merging configurations idempotently..." "INFO"

# Merge global settings
$localSettings.autoHideWindow = $customSettings.autoHideWindow
$localSettings.copyFormatting = $customSettings.copyFormatting
$localSettings.copyOnSelect = $customSettings.copyOnSelect
$localSettings.useAcrylicInTabRow = $customSettings.useAcrylicInTabRow

# Merge profile defaults
if ($null -eq $localSettings.profiles) {
    $localSettings | Add-Member -MemberType NoteProperty -Name "profiles" -Value @{}
}
if ($null -eq $localSettings.profiles.defaults) {
    $localSettings.profiles | Add-Member -MemberType NoteProperty -Name "defaults" -Value @{}
}

foreach ($prop in $customSettings.profiles.defaults.psobject.properties) {
    if ($null -eq $localSettings.profiles.defaults.psobject.properties[$prop.Name]) {
        $localSettings.profiles.defaults | Add-Member -MemberType NoteProperty -Name $prop.Name -Value $prop.Value
    } else {
        $localSettings.profiles.defaults.($prop.Name) = $prop.Value
    }
}

# Merge Actions (Deduplicate by ID so we don't spam the array)
if ($null -eq $localSettings.actions) {
    $localSettings | Add-Member -MemberType NoteProperty -Name "actions" -Value @()
}
$existingActions = @{}
foreach ($a in $localSettings.actions) {
    if ($a.id) { $existingActions[$a.id] = $a }
}
foreach ($a in $customSettings.actions) {
    $existingActions[$a.id] = $a
}
$localSettings.actions = @($existingActions.Values)

# Merge Keybindings (Deduplicate by keys)
if ($null -eq $localSettings.keybindings) {
    $localSettings | Add-Member -MemberType NoteProperty -Name "keybindings" -Value @()
}
$existingBindings = @{}
foreach ($kb in $localSettings.keybindings) {
    if ($kb.keys) { $existingBindings[$kb.keys] = $kb }
}
foreach ($kb in $customSettings.keybindings) {
    $existingBindings[$kb.keys] = $kb
}
$localSettings.keybindings = @($existingBindings.Values)

# Save merged JSON
$mergedJson = $localSettings | ConvertTo-Json -Depth 20
$mergedJson | Set-Content $settingsPath -Encoding UTF8

Write-UI "Windows Terminal will automatically apply the changes!" "OK"
Write-UI "Installation complete." "OK"
