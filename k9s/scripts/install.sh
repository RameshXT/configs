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
  bash "$TMP_BOOT/scripts/install.sh"
  ret=$?
  rm -rf "$TMP_BOOT"
  exit $ret
fi

LOG_FILE="/tmp/k9s_install.log"
exec 1>"$LOG_FILE" 2>&1
set -x

ui_info "Starting installation. Logs: $LOG_FILE"

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
    ui_error "Another install/uninstall is already running."
    exit 1
  else
    echo "[install] WARNING: stale lockfile found (PID $LOCK_PID not running), removing and continuing" >&2
    ui_warn "Stale lockfile found and removed."
    rm -f "$LOCKFILE"
  fi
fi
echo $$ > "$LOCKFILE"
trap 'rm -f "$LOCKFILE"; rm -rf "$TMP_DIR"' EXIT

ui_ok "Checked for existing installations"

command -v k9s >/dev/null 2>&1 || { echo "[install] error: k9s not found in PATH" >&2; ui_error "k9s not found in PATH"; exit 1; }
command -v yq  >/dev/null 2>&1 || { echo "[install] error: yq not found in PATH" >&2; ui_error "yq not found in PATH"; exit 1; }

ui_ok "Verified dependencies"

mkdir -p "$K9S_CFG_DIR/skins"

echo "$(date +'%Y-%m-%d %H:%M:%S') [install] copying config files to $TMP_DIR from local bundle ..."

cp "$SCRIPT_DIR/../assets/transparent.yaml" "$TMP_DIR/transparent.yaml" || { echo "[install] ERROR: failed to copy transparent.yaml" >&2; ui_error "Failed to copy transparent.yaml"; exit 1; }

cp "$SCRIPT_DIR/../assets/view.yaml" "$TMP_DIR/view.yaml" || { echo "[install] ERROR: failed to copy view.yaml" >&2; ui_error "Failed to copy view.yaml"; exit 1; }

cp "$SCRIPT_DIR/../assets/wrapper.sh" "$TMP_DIR/wrapper.sh" || { echo "[install] ERROR: failed to copy wrapper.sh" >&2; ui_error "Failed to copy wrapper.sh"; exit 1; }

echo "$(date +'%Y-%m-%d %H:%M:%S') [install] finished copying config files."
ui_ok "Copying: Bundle transferred"

ts="$(date +%Y%m%d%H%M%S)"
echo "$(date +'%Y-%m-%d %H:%M:%S') [install] backing up existing files ..."
for f in "$K9S_CFG_DIR/skins/transparent.yaml" "$K9S_CFG_DIR/views.yaml"; do
  [ -f "$f" ] && cp "$f" "${f}.bak.${ts}"
done
echo "$(date +'%Y-%m-%d %H:%M:%S') [install] finished backing up existing files."
ui_ok "Backup: Existing configs backed up"

echo "$(date +'%Y-%m-%d %H:%M:%S') [install] applying skin + views ..."
cp "$TMP_DIR/transparent.yaml" "$K9S_CFG_DIR/skins/transparent.yaml"
cp "$TMP_DIR/view.yaml"        "$K9S_CFG_DIR/views.yaml"
echo "$(date +'%Y-%m-%d %H:%M:%S') [install] finished applying skin + views."
ui_ok "Apply: Skin and views configured"

echo "$(date +'%Y-%m-%d %H:%M:%S') [install] updating config.yaml (skin reference only) ..."
touch "$K9S_CFG_DIR/config.yaml"
yq eval '.k9s.ui.skin = "transparent" | .k9s.skin = "transparent" | del(.ui.skin)' -i "$K9S_CFG_DIR/config.yaml"
echo "$(date +'%Y-%m-%d %H:%M:%S') [install] finished updating config.yaml."
ui_ok "Config: Activated transparent skin"

echo "$(date +'%Y-%m-%d %H:%M:%S') [install] applying .bashrc wrapper (idempotent) ..."
if grep -qF "$MARKER_START" "$BASHRC" 2>/dev/null; then
  cp "$BASHRC" "${BASHRC}.bak.${ts}"
  sed -i "/$MARKER_START/,/$MARKER_END/d" "$BASHRC"
fi

cp "$TMP_DIR/wrapper.sh" "$K9S_CFG_DIR/wrapper.sh"

{
  echo ""
  echo "$MARKER_START"
  # shellcheck disable=SC2016
  echo 'export K9S_CONFIG_DIR="$HOME/.config/k9s"'
  echo 'source ~/.config/k9s/wrapper.sh'
  echo "$MARKER_END"
} >> "$BASHRC"
echo "$(date +'%Y-%m-%d %H:%M:%S') [install] finished applying .bashrc wrapper."
ui_ok "Wrapper: Injected to ~/.bashrc"

echo "$(date +'%Y-%m-%d %H:%M:%S') [install] verifying final state ..."
for f in "$K9S_CFG_DIR/skins/transparent.yaml" "$K9S_CFG_DIR/views.yaml" "$K9S_CFG_DIR/wrapper.sh"; do
  if [ ! -s "$f" ]; then
    echo "[install] FATAL: $f is missing or empty after install, installation did not complete correctly" >&2
    ui_error "Verification failed: $f is missing or empty"
    exit 1
  fi
done
if ! grep -q "skin: transparent" "$K9S_CFG_DIR/config.yaml"; then
  echo "[install] FATAL: config.yaml does not reference the transparent skin after install" >&2
  ui_error "Verification failed: config.yaml missing skin reference"
  exit 1
fi
if ! grep -qF "$MARKER_START" "$BASHRC"; then
  echo "[install] FATAL: .bashrc wrapper block missing after install" >&2
  ui_error "Verification failed: wrapper block missing in ~/.bashrc"
  exit 1
fi
echo "$(date +'%Y-%m-%d %H:%M:%S') [install] verification passed, all files confirmed present."
ui_ok "Verification: All files in place"

echo "$(date +'%Y-%m-%d %H:%M:%S') [install] done."
echo -e "\n${GREEN}[DONE]${NC}: Installation complete!" >&3
ui_ok "Shell reloaded! All aliases are ready to use.\n"
exec bash -i </dev/tty >/dev/tty 2>&1