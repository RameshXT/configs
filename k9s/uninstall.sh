#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="/tmp/k9s_uninstall.log"
exec 3>&1
exec 1>"$LOG_FILE" 2>&1
set -x

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ui_ok()    { echo -e "${GREEN}[OK]${NC}: $1" >&3; }
ui_info()  { echo -e "${BLUE}[INFO]${NC}: $1" >&3; }
ui_warn()  { echo -e "${YELLOW}[WARNING]${NC}: $1" >&3; }
ui_error() { echo -e "${RED}[ERROR]${NC}: $1" >&3; }
ui_done()  { echo -e "${GREEN}[DONE]${NC}: $1" >&3; }

ui_info "Starting k9s customization uninstallation. Detailed logs: $LOG_FILE"

echo -e -n "\n${YELLOW}Are you sure you want to uninstall k9s customizations? (y/n): ${NC}" >&3
read -r response
if [[ ! "$response" =~ ^[Yy]$ ]]; then
  echo -e "\n${BLUE}[INFO]${NC}: Uninstallation aborted by user." >&3
  exit 0
fi

K9S_CFG_DIR="$HOME/.config/k9s"
BASHRC="$HOME/.bashrc"
MARKER_START="# >>> k9s customization >>>"
MARKER_END="# <<< k9s customization <<<"

LOCKFILE="/tmp/k9s-install.lock"
if [ -e "$LOCKFILE" ]; then
  LOCK_PID="$(cat "$LOCKFILE" 2>/dev/null || echo "")"
  if [ -n "$LOCK_PID" ] && kill -0 "$LOCK_PID" 2>/dev/null; then
    echo "[uninstall] ERROR: another install/uninstall is already running (PID $LOCK_PID)" >&2
    ui_error "Another install/uninstall is already running."
    exit 1
  else
    echo "[uninstall] WARNING: stale lockfile found (PID $LOCK_PID not running) — removing and continuing" >&2
    ui_warn "Stale lockfile found and removed."
    rm -f "$LOCKFILE"
  fi
fi
echo $$ > "$LOCKFILE"
trap 'rm -f "$LOCKFILE"' EXIT

ui_ok "Locking: Checked if an install/uninstall is already running"

command -v yq >/dev/null 2>&1 || { echo "[uninstall] error: yq not found in PATH" >&2; ui_error "yq not found in PATH"; exit 1; }
ui_ok "Dependencies: Verified yq is installed"

echo "$(date +'%Y-%m-%d %H:%M:%S') [uninstall] removing skin + views files ..."
rm -f "$K9S_CFG_DIR/skins/transparent.yaml" "$K9S_CFG_DIR/views.yaml"
echo "$(date +'%Y-%m-%d %H:%M:%S') [uninstall] finished removing skin + views files."
ui_ok "Cleanup: Removed skin and custom view configurations"

if [ -f "$K9S_CFG_DIR/config.yaml" ]; then
  echo "$(date +'%Y-%m-%d %H:%M:%S') [uninstall] removing skin reference from config.yaml (file itself kept — has cluster data) ..."
  yq eval 'del(.ui.skin)' -i "$K9S_CFG_DIR/config.yaml"
  echo "$(date +'%Y-%m-%d %H:%M:%S') [uninstall] finished removing skin reference."
  ui_ok "Config: Removed skin reference from k9s config.yaml"
fi

if grep -qF "$MARKER_START" "$BASHRC" 2>/dev/null; then
  echo "$(date +'%Y-%m-%d %H:%M:%S') [uninstall] removing wrapper block from .bashrc ..."
  ts="$(date +%Y%m%d%H%M%S)"
  cp "$BASHRC" "${BASHRC}.bak.${ts}"
  sed -i "/$MARKER_START/,/$MARKER_END/d" "$BASHRC"
  echo "$(date +'%Y-%m-%d %H:%M:%S') [uninstall] finished removing wrapper block."
  ui_ok "Wrapper: Removed k9s bash wrapper from ~/.bashrc"
else
  echo "$(date +'%Y-%m-%d %H:%M:%S') [uninstall] no wrapper block found in .bashrc, skipping"
  ui_ok "Wrapper: No k9s bash wrapper found in ~/.bashrc, skipped"
fi

echo "$(date +'%Y-%m-%d %H:%M:%S') [uninstall] verifying final state ..."
for f in "$K9S_CFG_DIR/skins/transparent.yaml" "$K9S_CFG_DIR/views.yaml"; do
  if [ -e "$f" ]; then
    echo "[uninstall] FATAL: $f still exists after uninstall" >&2
    ui_error "Verification failed: $f still exists"
    exit 1
  fi
done
if [ -f "$K9S_CFG_DIR/config.yaml" ] && grep -q "skin: transparent" "$K9S_CFG_DIR/config.yaml"; then
  echo "[uninstall] FATAL: config.yaml still references the transparent skin after uninstall" >&2
  ui_error "Verification failed: config.yaml still references the skin"
  exit 1
fi
if grep -qF "$MARKER_START" "$BASHRC" 2>/dev/null; then
  echo "[uninstall] FATAL: .bashrc wrapper block still present after uninstall" >&2
  ui_error "Verification failed: wrapper block still present in ~/.bashrc"
  exit 1
fi
echo "$(date +'%Y-%m-%d %H:%M:%S') [uninstall] verification passed — all files confirmed removed."
ui_ok "Verification: Confirmed all configurations are successfully removed"

echo "$(date +'%Y-%m-%d %H:%M:%S') [uninstall] done. Run: source ~/.bashrc"
echo -e "\n${GREEN}[DONE]${NC}: Uninstallation complete!\n\nRun: source ~/.bashrc" >&3
