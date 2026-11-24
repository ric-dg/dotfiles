# ~/.zshenv: zsh is the login shell on macOS. Every zsh reads this file (also `ssh host
# <command>` and scripts), so it only loads the shared login environment, ~/.profile.
emulate sh -c '. "$HOME/.profile"'
# for ~/.zprofile: macOS's /etc/zprofile (path_helper) reorders PATH after this file
_dotfiles_path=$PATH
