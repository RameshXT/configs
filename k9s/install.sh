#!/usr/bin/env bash
set -euo pipefail
set -x

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K9S_CFG_DIR="$HOME/.config/k9s"
TMP_DIR="$(mktemp -d)"
BASHRC="$HOME/.bashrc"
MARKER_START="# >>> k9s customization >>>"
MARKER_END="# <<< k9s customization <<<"

LOCKFILE="/tmp/k9s-install.lock"
if [ -e "$LOCKFILE" ]; then
  LOCK_PID="$(cat "$LOCKFILE" 2>/dev/null || echo "")"
  if [ -n "$LOCK_PID" ] && kill -0 "$LOCK_PID" 2>/dev/null; then
    echo "[install] ERROR: another install/uninstall is already running (PID $LOCK_PID)" >&2
    exit 1
  else
    echo "[install] WARNING: stale lockfile found (PID $LOCK_PID not running) — removing and continuing" >&2
    rm -f "$LOCKFILE"
  fi
fi
echo $$ > "$LOCKFILE"
trap 'rm -f "$LOCKFILE"; rm -rf "$TMP_DIR"' EXIT

command -v k9s >/dev/null 2>&1 || { echo "[install] error: k9s not found in PATH" >&2; exit 1; }
command -v yq  >/dev/null 2>&1 || { echo "[install] error: yq not found in PATH" >&2; exit 1; }

mkdir -p "$K9S_CFG_DIR/skins"

echo "$(date +'%Y-%m-%d %H:%M:%S') [install] copying config files to $TMP_DIR from local bundle ..."

cp "$SCRIPT_DIR/transparent.yaml" "$TMP_DIR/transparent.yaml" || { echo "[install] ERROR: failed to copy transparent.yaml" >&2; exit 1; }

cp "$SCRIPT_DIR/view.yaml" "$TMP_DIR/view.yaml" || { echo "[install] ERROR: failed to copy view.yaml" >&2; exit 1; }

cp "$SCRIPT_DIR/wrapper.sh" "$TMP_DIR/wrapper.sh" || { echo "[install] ERROR: failed to copy wrapper.sh" >&2; exit 1; }

echo "$(date +'%Y-%m-%d %H:%M:%S') [install] finished copying config files."

ts="$(date +%Y%m%d%H%M%S)"
echo "$(date +'%Y-%m-%d %H:%M:%S') [install] backing up existing files ..."
for f in "$K9S_CFG_DIR/skins/transparent.yaml" "$K9S_CFG_DIR/views.yaml"; do
  [ -f "$f" ] && cp "$f" "${f}.bak.${ts}"
done
echo "$(date +'%Y-%m-%d %H:%M:%S') [install] finished backing up existing files."

echo "$(date +'%Y-%m-%d %H:%M:%S') [install] applying skin + views ..."
cp "$TMP_DIR/transparent.yaml" "$K9S_CFG_DIR/skins/transparent.yaml"
cp "$TMP_DIR/view.yaml"        "$K9S_CFG_DIR/views.yaml"
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

echo "$(date +'%Y-%m-%d %H:%M:%S') [install] verifying final state ..."
for f in "$K9S_CFG_DIR/skins/transparent.yaml" "$K9S_CFG_DIR/views.yaml"; do
  if [ ! -s "$f" ]; then
    echo "[install] FATAL: $f is missing or empty after install — installation did not complete correctly" >&2
    exit 1
  fi
done
if ! grep -q "skin: transparent" "$K9S_CFG_DIR/config.yaml"; then
  echo "[install] FATAL: config.yaml does not reference the transparent skin after install" >&2
  exit 1
fi
if ! grep -qF "$MARKER_START" "$BASHRC"; then
  echo "[install] FATAL: .bashrc wrapper block missing after install" >&2
  exit 1
fi
echo "$(date +'%Y-%m-%d %H:%M:%S') [install] verification passed — all files confirmed present."

echo "$(date +'%Y-%m-%d %H:%M:%S') [install] done. Run: source ~/.bashrc"