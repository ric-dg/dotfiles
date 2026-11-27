# ~/.profile: login environment (POSIX sh). Read by the dash login shell, by SDDM
# when starting Plasma (so every app inherits it), and by bash via ~/.bash_profile.
# Keep it to environment variables only: it runs once per login, not per terminal.
# On macOS, zsh (the login shell there) reads it through ~/.zshenv.

# Homebrew (macOS /opt/homebrew, Linux /home/linuxbrew) ahead of the system directories,
# which macOS's path_helper puts first; a builtin test, no `brew shellenv` process. Already
# ahead of /usr/bin (a nested login shell) = left where it is, behind ~/.local/bin.
for _b in /opt/homebrew /home/linuxbrew/.linuxbrew; do
	[ -x "$_b/bin/brew" ] || continue
	case ":$PATH:" in *":$_b/bin:"*":/usr/bin:"*) ;; *) PATH=$_b/bin:$_b/sbin:$PATH ;; esac
	break
done
unset _b
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) PATH=$HOME/.local/bin:$PATH ;; esac
# per-user tools installed by mise (install.sh tools --user / no root): shims, no hook
[ ! -d "$HOME/.local/share/mise/shims" ] || case ":$PATH:" in *":$HOME/.local/share/mise/shims:"*) ;; *) PATH=$HOME/.local/share/mise/shims:$PATH ;; esac
export PATH

export EDITOR=nvim VISUAL=nvim

# Android SDK command-line tools, only if installed at /opt/android-sdk (e.g. Arch's
# android-sdk-cmdline-tools-latest); one builtin test, no cost otherwise. build-tools is
# versioned, so only cmdline-tools/latest/bin goes on PATH.
if [ -d /opt/android-sdk ]; then
	export ANDROID_HOME=/opt/android-sdk ANDROID_SDK_ROOT=/opt/android-sdk
	case ":$PATH:" in *":$ANDROID_HOME/cmdline-tools/latest/bin:"*) ;; *) PATH=$ANDROID_HOME/cmdline-tools/latest/bin:$PATH ;; esac
	export PATH
fi

# machine-specific login environment (untracked, sh syntax), e.g. extra PATH entries
[ ! -r "$HOME/.config/sh/profile.local" ] || . "$HOME/.config/sh/profile.local"

# Interactive sh/dash reads this file at start-up (prompt, line editing, aliases).
export ENV="$HOME/.shrc"

# Opt-in, per machine (profile.local: DOTFILES_SSH_TMUX=<session>): an interactive login over SSH goes straight into
# that tmux session (fish inside, tmux.conf), replacing this shell. Not for `ssh host <command>`, scp/sftp/rsync (no
# login shell), nor inside tmux; `ssh -t host sh` gives a plain shell. zsh does the same in ~/.zprofile.
if [ -n "${DOTFILES_SSH_TMUX-}" ] && [ -n "${SSH_TTY-}" ] && [ -z "${TMUX-}" ] && [ -z "${ZSH_VERSION-}" ]; then
	case $- in *i*) ! command -v tmux >/dev/null 2>&1 || exec tmux new-session -A -s "$DOTFILES_SSH_TMUX" ;; esac
fi
