# ~/.zshrc: interactive zsh (the login shell on macOS): the same small shell as sh/dash,
# from ~/.shrc (aliases, `t`, the missing-tools line); daily work is fish inside tmux.
unset _dotfiles_path
emulate sh -c '. "$HOME/.shrc"'
bindkey -e              # emacs line editing (zsh would pick vi keys because EDITOR=nvim)
PS1='%n@%m:%~%# '       # zsh's prompt syntax; no process
