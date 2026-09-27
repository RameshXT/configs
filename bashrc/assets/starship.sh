if [ -x "$HOME/.local/bin/starship" ] && ! command -v starship >/dev/null 2>&1; then
  export PATH="$HOME/.local/bin:$PATH"
fi

if [ -x "/usr/local/bin/starship" ] && ! command -v starship >/dev/null 2>&1; then
  export PATH="/usr/local/bin:$PATH"
fi

if command -v starship >/dev/null 2>&1; then
  eval "$(starship init bash)"
fi
