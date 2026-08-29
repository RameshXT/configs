#!/usr/bin/env bash
set -euo pipefail
set -x

K9S_CFG_DIR="$HOME/.config/k9s"
BASHRC="$HOME/.bashrc"
MARKER_START="# >>> k9s customization >>>"
MARKER_END="# <<< k9s customization <<<"

LOCKFILE="/tmp/k9s-install.lock"
if [ -e "$LOCKFILE" ]; then
  LOCK_PID="$(cat "$LOCKFILE" 2>/dev/null || echo "")"
  if [ -n "$LOCK_PID" ] && kill -0 "$LOCK_PID" 2>/dev/null; then
    echo "[uninstall] ERROR: another install/uninstall is already running (PID $LOCK_PID)" >&2
    exit 1
  else
    echo "[uninstall] WARNING: stale lockfile found (PID $LOCK_PID not running) — removing and continuing" >&2
    rm -f "$LOCKFILE"
  fi
fi
echo $$ > "$LOCKFILE"
trap 'rm -f "$LOCKFILE"' EXIT

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

echo "$(date +'%Y-%m-%d %H:%M:%S') [uninstall] verifying final state ..."
for f in "$K9S_CFG_DIR/skins/transparent.yaml" "$K9S_CFG_DIR/views.yaml"; do
  if [ -e "$f" ]; then
    echo "[uninstall] FATAL: $f still exists after uninstall" >&2
    exit 1
  fi
done
if [ -f "$K9S_CFG_DIR/config.yaml" ] && grep -q "skin: transparent" "$K9S_CFG_DIR/config.yaml"; then
  echo "[uninstall] FATAL: config.yaml still references the transparent skin after uninstall" >&2
  exit 1
fi
if grep -qF "$MARKER_START" "$BASHRC" 2>/dev/null; then
  echo "[uninstall] FATAL: .bashrc wrapper block still present after uninstall" >&2
  exit 1
fi
echo "$(date +'%Y-%m-%d %H:%M:%S') [uninstall] verification passed — all files confirmed removed."

echo "$(date +'%Y-%m-%d %H:%M:%S') [uninstall] done. Run: source ~/.bashrc"
