if [ -t 0 ]; then
  stty susp undef 2>/dev/null
fi

bind 'set bell-style none'
bind '"\b": backward-kill-word'
bind '"\C-z": undo'

export PS1='${debian_chroot:+($debian_chroot)}\[\033[01;34m\]\u@\h\[\033[00m\]:\[\033[01;37m\]\w\[\033[00m\]\$ '

# WSL browser integration (Ubuntu 24.04 / 26.04)
if [ -n "$WSL_DISTRO_NAME" ]; then
  if command -v wslview >/dev/null 2>&1; then
    export BROWSER="wslview"
  else
    export BROWSER="rundll32.exe url.dll,FileProtocolHandler %s"
  fi
fi
