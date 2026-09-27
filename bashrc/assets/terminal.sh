if [ -t 0 ]; then
  stty susp undef 2>/dev/null
fi

bind 'set bell-style none'
bind '"\b": backward-kill-word'
bind '"\C-z": undo'

export PS1='${debian_chroot:+($debian_chroot)}\[\033[01;34m\]\u@\h\[\033[00m\]:\[\033[01;37m\]\w\[\033[00m\]\$ '
