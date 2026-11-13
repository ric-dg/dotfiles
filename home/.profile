# ~/.profile: login environment (POSIX sh). Read by the dash login shell, by SDDM
# when starting Plasma (so every app inherits it), and by bash via ~/.bash_profile.
# Keep it to environment variables only: it runs once per login, not per terminal.

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

# Interactive sh/dash reads this file at start-up (prompt, line editing, aliases).
export ENV="$HOME/.shrc"
