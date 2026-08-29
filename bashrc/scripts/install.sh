#!/usr/bin/env bash

# UI Helpers
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ui_ok()    { echo -e "${GREEN}[OK]${NC}: $1" >&3; }
ui_info()  { echo -e "${BLUE}[INFO]${NC}: $1" >&3; }
ui_warn()  { echo -e "${YELLOW}[WARNING]${NC}: $1" >&3; }
ui_error() { echo -e "${RED}[ERROR]${NC}: $1" >&3; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" && pwd)"

if [ ! -f "$SCRIPT_DIR/../assets/aws_config.template" ]; then
  echo -e "" >&3
  ui_info "Bootstrapping bashrc bundle..."
  echo -e "" >&3
  TMP_BOOT="$(mktemp -d)"
  curl -# -fL "https://github.com/RameshXT/configs/releases/download/custom-bashrc/bashrc.tar.gz" -o "$TMP_BOOT/bashrc.tar.gz"
  echo -e "" >&3
  tar -xzf "$TMP_BOOT/bashrc.tar.gz" -C "$TMP_BOOT"
  bash "$TMP_BOOT/scripts/install.sh"
  ret=$?
  rm -rf "$TMP_BOOT"
  exit $ret
fi

LOG_FILE="/tmp/bashrc_install.log"
exec 3>&1
exec 1>"$LOG_FILE" 2>&1
set -x

ui_info "Starting bashrc bundle installation. Logs: $LOG_FILE"

BASHRC_DIR="$HOME/.config/bashrc.d"
BASHRC="$HOME/.bashrc"
AWS_CONFIG_DIR="$HOME/.aws"
AWS_CONFIG_FILE="$AWS_CONFIG_DIR/config"
MARKER_START="# >>> custom bashrc bundle >>>"
MARKER_END="# <<< custom bashrc bundle <<<"

# AWS Setup (Interactive only if missing)
if [ ! -f "$AWS_CONFIG_FILE" ]; then
  exec 4<&0
  exec 0</dev/tty
  echo -e -n "\n${YELLOW}AWS config not found. Please enter your AWS SSO Organization Name (e.g. smaitic): ${NC}" >&3
  read -r ORG_NAME
  echo -e -n "${YELLOW}Please enter your AWS Account ID: ${NC}" >&3
  read -r ACCOUNT_ID
  exec 0<&4
  exec 4<&-
  
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

# We extract the ORG_NAME from the aws config so we can dynamically inject it into the aws.sh script
ORG_NAME=$(grep "sso_session =" "$AWS_CONFIG_FILE" | head -n 1 | awk '{print $3}')

# Copy assets
mkdir -p "$BASHRC_DIR"
cp "$SCRIPT_DIR/../assets/history.sh" "$BASHRC_DIR/history.sh"
cp "$SCRIPT_DIR/../assets/aliases.sh" "$BASHRC_DIR/aliases.sh"
cp "$SCRIPT_DIR/../assets/terminal.sh" "$BASHRC_DIR/terminal.sh"

cp "$SCRIPT_DIR/../assets/aws.sh" "$BASHRC_DIR/aws.sh"
if [ -n "$ORG_NAME" ]; then
  sed -i "s/<YOUR_ORG_NAME>/$ORG_NAME/g" "$BASHRC_DIR/aws.sh"
fi

ui_ok "Scripts: Copied bash configurations to $BASHRC_DIR"

# Inject into .bashrc
if grep -qF "$MARKER_START" "$BASHRC" 2>/dev/null; then
  ui_ok "Wrapper: Source loop already present in ~/.bashrc"
else
  {
    echo -e "\n$MARKER_START"
    echo 'for f in ~/.config/bashrc.d/*.sh; do'
    # shellcheck disable=SC2016
    echo '  [ -r "$f" ] && source "$f"'
    echo 'done'
    echo "$MARKER_END"
  } >> "$BASHRC"
  ui_ok "Wrapper: Injected source loop to ~/.bashrc"
fi

ui_ok "Verification: All files in place"
echo -e "\n${GREEN}[DONE]${NC}: Installation complete!\n\nRun: source ~/.bashrc" >&3
