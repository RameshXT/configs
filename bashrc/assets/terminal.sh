if [ -t 0 ]; then
  stty susp undef 2>/dev/null
fi

bind 'set bell-style none'
bind 'set undo-limit 1000'
bind '"\b": backward-kill-word'
bind '"\C-z": undo'


