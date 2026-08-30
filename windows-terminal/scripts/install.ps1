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


if ($LocalSource) {
    Write-UI "Using local settings source: $LocalSource" "INFO"
    $customJsonStr = Get-Content $LocalSource -Raw
} else {
    $repoUrl = "https://raw.githubusercontent.com/RameshXT/configs/main/windows-terminal/assets/settings.json"
    Write-UI "Fetching custom settings from GitHub..." "INFO"
    $response = Invoke-WebRequest -Uri $repoUrl -UseBasicParsing
    $customJsonStr = $response.Content
}

$customSettings = $customJsonStr | ConvertFrom-Json
$localSettingsStr = Get-Content $settingsPath -Raw
$localSettings = $localSettingsStr | ConvertFrom-Json


$ts = Get-Date -Format 'yyyyMMddHHmmss'
$backupPath = "$settingsPath.bak.$ts"
Copy-Item $settingsPath $backupPath
Write-UI "Backed up existing settings to $backupPath" "OK"

Write-UI "Merging configurations idempotently..." "INFO"


foreach ($prop in @("autoHideWindow", "copyFormatting", "copyOnSelect", "useAcrylicInTabRow")) {
    if ($null -eq $localSettings.psobject.properties[$prop]) {
        $localSettings | Add-Member -MemberType NoteProperty -Name $prop -Value $customSettings.$prop
    } else {
        $localSettings.$prop = $customSettings.$prop
    }
}


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


$mergedJson = $localSettings | ConvertTo-Json -Depth 20
$mergedJson | Set-Content $settingsPath -Encoding UTF8

Write-UI "Windows Terminal will automatically apply the changes!" "OK"
Write-UI "Installation complete." "OK"
