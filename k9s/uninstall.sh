#!/usr/bin/env bash
set -euo pipefail
set -x

K9S_CFG_DIR="$HOME/.config/k9s"
BASHRC="$HOME/.bashrc"
MARKER_START="# >>> k9s customization >>>"
MARKER_END="# <<< k9s customization <<<"

command -v yq >/dev/null 2>&1 || { echo "[uninstall] error: yq not found in PATH" >&2; exit 1; }

echo "$(date +'%Y-%m-%d %H:%M:%S') [uninstall] removing skin + views files ..."
rm -f "$K9S_CFG_DIR/skins/transparent.yaml" "$K9S_CFG_DIR/views.yaml"
echo "$(date +'%Y-%m-%d %H:%M:%S') [uninstall] finished removing skin + views files."

if [ -f "$K9S_CFG_DIR/config.yaml" ]; then
  echo "$(date +'%Y-%m-%d %H:%M:%S') [uninstall] removing skin reference from config.yaml (file itself kept — has cluster data) ..."
  yq eval 'del(.ui.skin)' -i "$K9S_CFG_DIR/config.yaml"
  echo "$(date +'%Y-%m-%d %H:%M:%S') [uninstall] finished removing skin reference."
fi

if grep -qF "$MARKER_START" "$BASHRC" 2>/dev/null; then
  echo "$(date +'%Y-%m-%d %H:%M:%S') [uninstall] removing wrapper block from .bashrc ..."
  ts="$(date +%Y%m%d%H%M%S)"
  cp "$BASHRC" "${BASHRC}.bak.${ts}"
  sed -i "/$MARKER_START/,/$MARKER_END/d" "$BASHRC"
  echo "$(date +'%Y-%m-%d %H:%M:%S') [uninstall] finished removing wrapper block."
else
  echo "$(date +'%Y-%m-%d %H:%M:%S') [uninstall] no wrapper block found in .bashrc, skipping"
fi

echo "$(date +'%Y-%m-%d %H:%M:%S') [uninstall] done. Run: source ~/.bashrc"
