#!/usr/bin/env bash

BASHRC_DIR="$HOME/.config/bashrc.d"
BASHRC="$HOME/.bashrc"
MARKER_START="# >>> custom bashrc bundle >>>"
MARKER_END="# <<< custom bashrc bundle <<<"

if [ ! -d "$BASHRC_DIR" ] && ! grep -qF "$MARKER_START" "$BASHRC" 2>/dev/null; then
  echo -e "\033[90m[INFO]: bashrc bundle is not installed.\033[0m"
  exit 0
fi

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ui_ok()    { echo -e "${GREEN}[OK]${NC}: $1" >&3; }
ui_info()  { echo -e "${BLUE}[INFO]${NC}: $1" >&3; }
ui_warn()  { echo -e "${YELLOW}[WARNING]${NC}: $1" >&3; }
ui_error() { echo -e "${RED}[ERROR]${NC}: $1" >&3; }

LOG_FILE="/tmp/bashrc_uninstall.log"
exec 3>&1
exec 1>"$LOG_FILE" 2>&1
set -x

echo -e "" >&3
ui_info "Starting bashrc bundle uninstallation. Logs: $LOG_FILE"
echo -e "" >&3

echo -e -n "${YELLOW}Are you sure you want to uninstall your bashrc customizations? (y/n): ${NC}" >&3
read -r response </dev/tty

if [[ ! "$response" =~ ^[Yy]$ ]]; then
  echo -e "\n${BLUE}[INFO]${NC}: Uninstallation aborted by user." >&3
  exit 0
fi

BASHRC_DIR="$HOME/.config/bashrc.d"
BASHRC="$HOME/.bashrc"
MARKER_START="# >>> custom bashrc bundle >>>"
MARKER_END="# <<< custom bashrc bundle <<<"

if [ -d "$BASHRC_DIR" ]; then
  rm -rf "$BASHRC_DIR"
  ui_ok "Removed configuration directory $BASHRC_DIR"
else
  ui_warn "Configuration directory $BASHRC_DIR not found"
fi

if grep -qF "$MARKER_START" "$BASHRC" 2>/dev/null; then
  awk -v start="$MARKER_START" -v end="$MARKER_END" '
    $0 == start { in_block=1; next }
    $0 == end { in_block=0; next }
    !in_block { print }
  ' "$BASHRC" > "${BASHRC}.tmp" && mv "${BASHRC}.tmp" "$BASHRC"
  ui_ok "Removed source loop from ~/.bashrc"
else
  ui_info "No source loop found in ~/.bashrc"
fi

ui_info "Note: ~/.aws/config was NOT removed as it contains your AWS credentials."
ui_ok "Clean state confirmed"
echo -e "\n${GREEN}[DONE]${NC}: Uninstallation complete!" >&3
ui_ok "Shell reloaded! Customizations removed.\n"
exec 200>&- 2>/dev/null || true
exec bash -i </dev/tty >/dev/tty 2>&1
