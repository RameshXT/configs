#!/usr/bin/env bash
set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/RameshXT/configs/main/k9s"
K9S_CFG_DIR="$HOME/.config/k9s"
TMP_DIR="$(mktemp -d)"
BASHRC="$HOME/.bashrc"
MARKER_START="# >>> k9s customization >>>"
MARKER_END="# <<< k9s customization <<<"

trap 'rm -rf "$TMP_DIR"' EXIT

command -v k9s >/dev/null 2>&1 || { echo "[install] error: k9s not found in PATH" >&2; exit 1; }
command -v yq  >/dev/null 2>&1 || { echo "[install] error: yq not found in PATH" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "[install] error: curl not found in PATH" >&2; exit 1; }

mkdir -p "$K9S_CFG_DIR/skins"

echo "[install] downloading config files to $TMP_DIR ..."
curl -fsSL "$REPO_RAW/skins/transparent.yaml" -o "$TMP_DIR/transparent.yaml"
curl -fsSL "$REPO_RAW/views.yaml"            -o "$TMP_DIR/views.yaml"
curl -fsSL "$REPO_RAW/wrapper.sh"            -o "$TMP_DIR/wrapper.sh"

ts="$(date +%Y%m%d%H%M%S)"
for f in "$K9S_CFG_DIR/skins/transparent.yaml" "$K9S_CFG_DIR/views.yaml"; do
  [ -f "$f" ] && cp "$f" "${f}.bak.${ts}"
done

echo "[install] applying skin + views ..."
cp "$TMP_DIR/transparent.yaml" "$K9S_CFG_DIR/skins/transparent.yaml"
cp "$TMP_DIR/views.yaml"       "$K9S_CFG_DIR/views.yaml"

echo "[install] updating config.yaml (skin reference only) ..."
touch "$K9S_CFG_DIR/config.yaml"
yq eval '.ui.skin = "transparent"' -i "$K9S_CFG_DIR/config.yaml"

echo "[install] applying .bashrc wrapper (idempotent) ..."
if grep -qF "$MARKER_START" "$BASHRC" 2>/dev/null; then
  cp "$BASHRC" "${BASHRC}.bak.${ts}"
  sed -i "/$MARKER_START/,/$MARKER_END/d" "$BASHRC"
fi

{
  echo ""
  echo "$MARKER_START"
  cat "$TMP_DIR/wrapper.sh"
  echo "$MARKER_END"
} >> "$BASHRC"

echo "[install] done. Run: source ~/.bashrc"