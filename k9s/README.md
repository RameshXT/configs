# k9s Customization Bundle

A custom configuration bundle for k9s (v0.51.0+) featuring a transparent skin, extra pod columns, and a safe read-only-by-default `.bashrc` wrapper.

> **Note**: `custom-k9s` is always the latest state of the `k9s/` folder on `main`, auto-published by GitHub Actions on every relevant push — this is not a manually versioned release.

## Install

```bash
curl -fsSL https://github.com/RameshXT/configs/releases/download/custom-k9s/k9s.tar.gz -o /tmp/k9s.tar.gz && mkdir -p /tmp/k9s-install && tar -xzf /tmp/k9s.tar.gz -C /tmp/k9s-install && bash /tmp/k9s-install/install.sh
```

## Uninstall

```bash
curl -fsSL https://github.com/RameshXT/configs/releases/download/custom-k9s/k9s.tar.gz -o /tmp/k9s.tar.gz && mkdir -p /tmp/k9s-install && tar -xzf /tmp/k9s.tar.gz -C /tmp/k9s-install && bash /tmp/k9s-install/uninstall.sh
```
