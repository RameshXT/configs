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
    return
}

Write-Host ""
Write-UI "Starting Windows Terminal customization installer..." "INFO"
Write-Host ""


function Invoke-Spinner {
    param([scriptblock]$ScriptBlock, [string]$Message, [array]$ArgumentList = @())
    $spinstr = "⠋","⠙","⠹","⠸","⠼","⠴","⠦","⠧","⠇","⠏"
    $job = Start-Job -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList
    $i = 0
    while ($job.State -eq "Running" -or $i -lt 12) {
        $char = $spinstr[$i % $spinstr.Length]
        Write-Host "`r[INFO]: $Message [$char] " -ForegroundColor Cyan -NoNewline
        Start-Sleep -Milliseconds 80
        $i++
    }
    $result = Receive-Job -Job $job
    Remove-Job -Job $job
    Write-Host "`r[OK]: $Message             " -ForegroundColor Green
    return $result
}

if ($LocalSource) {
    Write-UI "Using local settings source: $LocalSource" "INFO"
    $customJsonStr = Get-Content $LocalSource -Raw
} else {
    $repoUrl = "https://raw.githubusercontent.com/RameshXT/configs/main/windows-terminal/assets/settings.json"
    $customJsonStr = Invoke-Spinner -Message "Fetching custom settings from GitHub..." -ScriptBlock {
        param($url)
        (Invoke-WebRequest -Uri $url -UseBasicParsing).Content
    } -ArgumentList $repoUrl
}

$customSettings = $customJsonStr | ConvertFrom-Json
$localSettingsStr = Get-Content $settingsPath -Raw
$localSettings = $localSettingsStr | ConvertFrom-Json


$originalBackup = "$settingsPath.bak.original"
if (-not (Test-Path $originalBackup)) {
    Copy-Item $settingsPath $originalBackup
    Write-UI "Created initial pre-customization backup at $originalBackup" "OK"
} else {
    Write-UI "Original pre-customization backup already preserved at $originalBackup" "OK"
}

Write-Host ""
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

Write-Host ""
Write-Host "[DONE]: Installation complete!" -ForegroundColor Green
Write-UI "Windows Terminal will automatically apply the changes!" "OK"
Write-Host ""
