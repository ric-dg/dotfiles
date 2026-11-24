# ~/.zprofile: zsh login shells (macOS). /etc/zprofile's path_helper ran after ~/.zshenv and
# moved the system directories in front of yours: restore ~/.profile's order, keeping what
# path_helper added (typeset -U keeps the first of each directory).
if [[ -n ${_dotfiles_path-} ]]; then
	typeset -U path
	path=(${(s.:.)_dotfiles_path} $path)
fi
unset _dotfiles_path
