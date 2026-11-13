# ~/.profile: login environment (POSIX sh). Read by the dash login shell, by SDDM
# when starting Plasma (so every app inherits it), and by bash via ~/.bash_profile.
# Keep it to environment variables only: it runs once per login, not per terminal.

case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) PATH=$HOME/.local/bin:$PATH ;; esac
export PATH

export EDITOR=nvim VISUAL=nvim

# Android SDK command-line tools (system-wide at /opt/android-sdk, installed by
# the AUR cmdline-tools package + sdkmanager build-tools). Only the cmdline-tools
# bin dir goes on PATH: build-tools is versioned, so android-install.sh locates
# aapt2 under $ANDROID_HOME/build-tools/*/aapt2 instead of pinning a version here.
export ANDROID_HOME=/opt/android-sdk ANDROID_SDK_ROOT=/opt/android-sdk
case ":$PATH:" in *":$ANDROID_HOME/cmdline-tools/latest/bin:"*) ;; *) PATH=$ANDROID_HOME/cmdline-tools/latest/bin:$PATH ;; esac
export PATH

# Interactive sh/dash reads this file at start-up (prompt, line editing, aliases).
export ENV="$HOME/.shrc"
