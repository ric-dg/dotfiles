# bash (interactive). The login environment is in ~/.profile (POSIX, shared with dash).
[[ $- == *i* ]] || return
# shared POSIX aliases, prompt and functions
[[ -r ~/.shrc ]] && . ~/.shrc
# drop-ins: ~/.config/bash/*.sh (e.g. tool hooks), loaded in name order
for _f in ~/.config/bash/*.sh; do [[ -r $_f ]] && . "$_f"; done
unset _f
