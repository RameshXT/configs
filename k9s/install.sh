#!/usr/bin/env bash
set -euo pipefail
set -x

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

echo "$(date +'%Y-%m-%d %H:%M:%S') [install] downloading config files to $TMP_DIR ..."

echo "Fetching: $REPO_RAW/skins/transparent.yaml"
curl --max-time 15 -fsSL "$REPO_RAW/skins/transparent.yaml" -o "$TMP_DIR/transparent.yaml" || { echo "[install] ERROR: failed to download transparent.yaml from $REPO_RAW/skins/transparent.yaml" >&2; exit 1; }

echo "Fetching: $REPO_RAW/views.yaml"
curl --max-time 15 -fsSL "$REPO_RAW/views.yaml" -o "$TMP_DIR/views.yaml" || { echo "[install] ERROR: failed to download views.yaml from $REPO_RAW/views.yaml" >&2; exit 1; }

echo "Fetching: $REPO_RAW/wrapper.sh"
curl --max-time 15 -fsSL "$REPO_RAW/wrapper.sh" -o "$TMP_DIR/wrapper.sh" || { echo "[install] ERROR: failed to download wrapper.sh from $REPO_RAW/wrapper.sh" >&2; exit 1; }

echo "$(date +'%Y-%m-%d %H:%M:%S') [install] finished downloading config files."

ts="$(date +%Y%m%d%H%M%S)"
echo "$(date +'%Y-%m-%d %H:%M:%S') [install] backing up existing files ..."
for f in "$K9S_CFG_DIR/skins/transparent.yaml" "$K9S_CFG_DIR/views.yaml"; do
  [ -f "$f" ] && cp "$f" "${f}.bak.${ts}"
done
echo "$(date +'%Y-%m-%d %H:%M:%S') [install] finished backing up existing files."

echo "$(date +'%Y-%m-%d %H:%M:%S') [install] applying skin + views ..."
cp "$TMP_DIR/transparent.yaml" "$K9S_CFG_DIR/skins/transparent.yaml"
cp "$TMP_DIR/views.yaml"       "$K9S_CFG_DIR/views.yaml"
echo "$(date +'%Y-%m-%d %H:%M:%S') [install] finished applying skin + views."

echo "$(date +'%Y-%m-%d %H:%M:%S') [install] updating config.yaml (skin reference only) ..."
touch "$K9S_CFG_DIR/config.yaml"
yq eval '.ui.skin = "transparent"' -i "$K9S_CFG_DIR/config.yaml"
echo "$(date +'%Y-%m-%d %H:%M:%S') [install] finished updating config.yaml."

echo "$(date +'%Y-%m-%d %H:%M:%S') [install] applying .bashrc wrapper (idempotent) ..."
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
echo "$(date +'%Y-%m-%d %H:%M:%S') [install] finished applying .bashrc wrapper."

echo "$(date +'%Y-%m-%d %H:%M:%S') [install] done. Run: source ~/.bashrc"