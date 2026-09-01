# Windows Terminal Customization Bundle

A smart, idempotent PowerShell installer that dynamically merges custom keybindings, global settings, and profile defaults into your local Windows Terminal `settings.json` without destroying your unique machine GUIDs.

## Install & Update

Open PowerShell and run:

```powershell
Invoke-RestMethod -Uri "https://raw.githubusercontent.com/RameshXT/configs/main/windows-terminal/scripts/install.ps1" | Invoke-Expression
```

## Uninstall

Open PowerShell and run:

```powershell
Invoke-RestMethod -Uri "https://raw.githubusercontent.com/RameshXT/configs/main/windows-terminal/scripts/uninstall.ps1" | Invoke-Expression
```
