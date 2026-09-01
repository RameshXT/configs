#!/usr/bin/env bash

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ui_ok()    { echo -e "${GREEN}[OK]${NC}: $1" >&3; }
ui_info()  { echo -e "${BLUE}[INFO]${NC}: $1" >&3; }
ui_warn()  { echo -e "${YELLOW}[WARNING]${NC}: $1" >&3; }
ui_error() { echo -e "${RED}[ERROR]${NC}: $1" >&3; }

exec 3>&1

spin() {
  local pid=$1
  local msg=$2
  local delay=0.08
  local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  while kill -0 "$pid" 2>/dev/null; do
    local temp=${spinstr#?}
    printf "\r${BLUE}[INFO]${NC}: %s [%c] " "$msg" "$spinstr" >&3
    spinstr=$temp${spinstr%"$temp"}
    sleep $delay
  done
  printf "\r${GREEN}[OK]${NC}: %s              \n" "$msg" >&3
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" && pwd)"

if [ ! -f "$SCRIPT_DIR/../assets/aws_config.template" ]; then
  TMP_BOOT="$(mktemp -d)"
  curl -fsSL "https://github.com/RameshXT/configs/releases/download/custom-bashrc/bashrc.tar.gz" -o "$TMP_BOOT/bashrc.tar.gz" &
  spin $! "Bootstrapping bashrc bundle..."
  tar -xzf "$TMP_BOOT/bashrc.tar.gz" -C "$TMP_BOOT"
  bash "$TMP_BOOT/scripts/install.sh"
  ret=$?
  rm -rf "$TMP_BOOT"
  exit $ret
fi

LOG_FILE="/tmp/bashrc_install.log"
exec 1>"$LOG_FILE" 2>&1
set -x

ui_info "Starting bashrc bundle installation. Logs: $LOG_FILE"

BASHRC_DIR="$HOME/.config/bashrc.d"
BASHRC="$HOME/.bashrc"
AWS_CONFIG_DIR="$HOME/.aws"
AWS_CONFIG_FILE="$AWS_CONFIG_DIR/config"
MARKER_START="# >>> custom bashrc bundle >>>"
MARKER_END="# <<< custom bashrc bundle <<<"

if [ ! -f "$AWS_CONFIG_FILE" ]; then
  echo -e -n "\n${YELLOW}AWS config not found. Please enter your AWS SSO Organization Name: ${NC}" >&3
  read -r ORG_NAME </dev/tty
  echo -e -n "${YELLOW}Please enter your AWS Account ID: ${NC}" >&3
  read -r ACCOUNT_ID </dev/tty
  
  if [ -z "$ORG_NAME" ] || [ -z "$ACCOUNT_ID" ]; then
    echo "[install] error: missing org name or account id" >&2
    ui_error "Organization name and Account ID are required for first-time setup."
    exit 1
  fi
  
  mkdir -p "$AWS_CONFIG_DIR"
  cp "$SCRIPT_DIR/../assets/aws_config.template" "$AWS_CONFIG_FILE"
  sed -i "s/<YOUR_ORG_NAME>/$ORG_NAME/g" "$AWS_CONFIG_FILE"
  sed -i "s/<YOUR_AWS_ACCOUNT_ID>/$ACCOUNT_ID/g" "$AWS_CONFIG_FILE"
  ui_ok "AWS: Generated configuration securely in ~/.aws/config"
else
  ui_ok "AWS: Configuration already exists, skipping prompt"
fi

ORG_NAME=$(grep "sso_session =" "$AWS_CONFIG_FILE" | head -n 1 | awk '{print $3}')

mkdir -p "$BASHRC_DIR"
cp "$SCRIPT_DIR/../assets/history.sh" "$BASHRC_DIR/history.sh"
cp "$SCRIPT_DIR/../assets/aliases.sh" "$BASHRC_DIR/aliases.sh"
cp "$SCRIPT_DIR/../assets/terminal.sh" "$BASHRC_DIR/terminal.sh"

cp "$SCRIPT_DIR/../assets/aws.sh" "$BASHRC_DIR/aws.sh"
if [ -n "$ORG_NAME" ]; then
  sed -i "s/<YOUR_ORG_NAME>/$ORG_NAME/g" "$BASHRC_DIR/aws.sh"
fi

ui_ok "Scripts: Copied bash configurations to $BASHRC_DIR"

if grep -qF "$MARKER_START" "$BASHRC" 2>/dev/null; then
  awk -v start="$MARKER_START" -v end="$MARKER_END" '
    $0 == start { in_block=1; next }
    $0 == end { in_block=0; next }
    !in_block { print }
  ' "$BASHRC" > "${BASHRC}.tmp" && mv "${BASHRC}.tmp" "$BASHRC"
fi

{
  echo ""
  echo "$MARKER_START"
  echo 'source ~/.config/bashrc.d/aws.sh'
  echo 'source ~/.config/bashrc.d/history.sh'
  echo 'source ~/.config/bashrc.d/terminal.sh'
  echo 'source ~/.config/bashrc.d/aliases.sh'
  echo "$MARKER_END"
} >> "$BASHRC"
ui_ok "Wrapper: Injected strictly ordered source statements to ~/.bashrc"

ui_ok "Status: All files in place"
echo -e "\n${GREEN}[DONE]${NC}: Installation complete!" >&3
ui_ok "Shell reloaded! All aliases are ready to use.\n"
exec bash -i </dev/tty >/dev/tty 2>&1
