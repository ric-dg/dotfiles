# ~/.zprofile: zsh login shells (macOS). /etc/zprofile's path_helper ran after ~/.zshenv and
# moved the system directories in front of yours: restore ~/.profile's order, keeping what
# path_helper added (typeset -U keeps the first of each directory).
if [[ -n ${_dotfiles_path-} ]]; then
	typeset -U path
	path=(${(s.:.)_dotfiles_path} $path)
fi
unset _dotfiles_path

# Opt-in SSH login -> tmux (DOTFILES_SSH_TMUX, see ~/.profile): here, before ~/.zshrc, so none of the interactive
# set-up runs for a shell that is replaced. Login shells only: `ssh -t host zsh` gives a plain zsh.
[[ -n ${DOTFILES_SSH_TMUX-} && -n ${SSH_TTY-} && -z ${TMUX-} && -o interactive ]] && (( $+commands[tmux] )) &&
	exec tmux new-session -A -s $DOTFILES_SSH_TMUX
