# configs
A centralized collection of configurations and customizations.

## bashrc (Only for Ubuntu 24.04)
A modular configuration bundle for `.bashrc` featuring an interactive AWS SSO login workflow, custom aliases, history optimizations, and terminal keybindings.

### Install & Update
```bash
curl -fsSL https://raw.githubusercontent.com/RameshXT/configs/main/bashrc/scripts/install.sh | bash
```

### Uninstall
```bash
curl -fsSL https://raw.githubusercontent.com/RameshXT/configs/main/bashrc/scripts/uninstall.sh | bash
```

## k9s (Only for Ubuntu 24.04)
A UI skin and configuration bundle for k9s that adds visual transparency, custom resource views, and a safe read-only terminal wrapper.

### Install & Update
```bash
curl -fsSL https://raw.githubusercontent.com/RameshXT/configs/main/k9s/scripts/install.sh | bash
```

### Uninstall
```bash
curl -fsSL https://raw.githubusercontent.com/RameshXT/configs/main/k9s/scripts/uninstall.sh | bash
```

## Windows Terminal
A smart, idempotent PowerShell installer that dynamically merges custom keybindings, global settings, and profile defaults into your local Windows Terminal `settings.json` without destroying your unique machine GUIDs.

### Install & Update
```powershell
Invoke-RestMethod -Uri "https://raw.githubusercontent.com/RameshXT/configs/main/windows-terminal/scripts/install.ps1" | Invoke-Expression
```
