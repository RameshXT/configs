#!/usr/bin/env bash
set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

exec 3>&1

ui_ok()    { echo -e "${GREEN}[OK]${NC}: $1" >&3; }
ui_info()  { echo -e "${BLUE}[INFO]${NC}: $1" >&3; }
ui_warn()  { echo -e "${YELLOW}[WARNING]${NC}: $1" >&3; }
ui_error() { echo -e "${RED}[ERROR]${NC}: $1" >&3; }
ui_done()  { echo -e "${GREEN}[DONE]${NC}: $1" >&3; }

spin() {
  local pid=$1
  local msg=$2
  local delay=0.08
  local spinstr=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  local i=0
  local count=0
  local LC_ALL=C.UTF-8
  local LANG=C.UTF-8
  while kill -0 "$pid" 2>/dev/null || [ $count -lt 12 ]; do
    printf "\r${BLUE}[INFO]${NC}: %s [%s] " "$msg" "${spinstr[i]}" >&3
    i=$(( (i + 1) % ${#spinstr[@]} ))
    count=$((count + 1))
    sleep $delay
  done
  wait "$pid" 2>/dev/null
  printf "\r${GREEN}[OK]${NC}: %s              \n" "$msg" >&3
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" && pwd)"

if [ ! -f "$SCRIPT_DIR/../assets/transparent.yaml" ]; then
  TMP_BOOT="$(mktemp -d)"
  curl -fsSL "https://github.com/RameshXT/configs/releases/download/custom-k9s/k9s.tar.gz" -o "$TMP_BOOT/k9s.tar.gz" &
  spin $! "Bootstrapping k9s bundle..."
  tar -xzf "$TMP_BOOT/k9s.tar.gz" -C "$TMP_BOOT"
  bash "$TMP_BOOT/scripts/uninstall.sh"
  ret=$?
  rm -rf "$TMP_BOOT"
  exit $ret
fi

LOG_FILE="/tmp/k9s_uninstall.log"
exec 1>"$LOG_FILE" 2>&1
set -x

echo -e "" >&3
ui_info "Starting k9s bundle uninstallation. Logs: $LOG_FILE"
echo -e "" >&3

echo -e -n "${YELLOW}Are you sure you want to uninstall k9s customizations? (y/n): ${NC}" >&3
read -r response </dev/tty
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
    echo "[uninstall] WARNING: stale lockfile found (PID $LOCK_PID not running), removing and continuing" >&2
    ui_warn "Stale lockfile found and removed."
    rm -f "$LOCKFILE"
  fi
fi
echo $$ > "$LOCKFILE"
trap 'rm -f "$LOCKFILE"' EXIT

ui_ok "Verified no overlapping installations"

command -v yq >/dev/null 2>&1 || { echo "[uninstall] error: yq not found in PATH" >&2; ui_error "yq not found in PATH"; exit 1; }
ui_ok "Verified yq is installed"

echo "$(date +'%Y-%m-%d %H:%M:%S') [uninstall] removing skin + views files ..."
rm -f "$K9S_CFG_DIR/skins/transparent.yaml" "$K9S_CFG_DIR/views.yaml" "$K9S_CFG_DIR/wrapper.sh"
echo "$(date +'%Y-%m-%d %H:%M:%S') [uninstall] finished removing skin + views files."
ui_ok "Removed custom skin and views"

if [ -f "$K9S_CFG_DIR/config.yaml" ]; then
  echo "$(date +'%Y-%m-%d %H:%M:%S') [uninstall] removing skin reference from config.yaml (file itself kept, has cluster data) ..."
  yq eval 'del(.k9s.ui.skin) | del(.k9s.skin) | del(.ui.skin)' -i "$K9S_CFG_DIR/config.yaml"
  echo "$(date +'%Y-%m-%d %H:%M:%S') [uninstall] finished removing skin reference."
  ui_ok "Removed skin reference from config"
fi

if grep -qF "$MARKER_START" "$BASHRC" 2>/dev/null; then
  echo "$(date +'%Y-%m-%d %H:%M:%S') [uninstall] removing wrapper block from .bashrc ..."
  ts="$(date +%Y%m%d%H%M%S)"
  cp "$BASHRC" "${BASHRC}.bak.${ts}"
  sed -i "/$MARKER_START/,/$MARKER_END/d" "$BASHRC"
  echo "$(date +'%Y-%m-%d %H:%M:%S') [uninstall] finished removing wrapper block."
  ui_ok "Removed wrapper from ~/.bashrc"
else
  echo "$(date +'%Y-%m-%d %H:%M:%S') [uninstall] no wrapper block found in .bashrc, skipping"
  ui_ok "Wrapper not found in ~/.bashrc"
fi

echo "$(date +'%Y-%m-%d %H:%M:%S') [uninstall] verifying final state ..."
for f in "$K9S_CFG_DIR/skins/transparent.yaml" "$K9S_CFG_DIR/views.yaml" "$K9S_CFG_DIR/wrapper.sh"; do
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
echo "$(date +'%Y-%m-%d %H:%M:%S') [uninstall] verification passed, all files confirmed removed."
ui_ok "Clean state confirmed"

echo "$(date +'%Y-%m-%d %H:%M:%S') [uninstall] done."
echo -e "\n${GREEN}[DONE]${NC}: Uninstallation complete!" >&3
ui_ok "Shell reloaded! Customizations removed.\n"
exec bash -i </dev/tty >/dev/tty 2>&1
