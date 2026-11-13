# fish: the interactive shell (inside tmux; the login shell is POSIX sh/dash, see ~/.profile).
# Machine-specific additions go in ~/.config/fish/conf.d/local.fish (untracked).
set -gx EDITOR nvim
set -gx VISUAL nvim
set -gx MANPAGER "nvim +Man!"
contains -- $HOME/.local/bin $PATH; or set -gx PATH $HOME/.local/bin $PATH   # builtins only, no fork

# Android SDK command-line tools (system-wide; the scripts find build-tools/aapt2 themselves)
if test -d /opt/android-sdk   # Android SDK, only if installed (see ~/.profile)
    set -gx ANDROID_HOME /opt/android-sdk
    set -gx ANDROID_SDK_ROOT /opt/android-sdk
    contains -- $ANDROID_HOME/cmdline-tools/latest/bin $PATH; or set -gx PATH $ANDROID_HOME/cmdline-tools/latest/bin $PATH
end

if status is-interactive
    set -g fish_greeting
    # tool init scripts cached; regenerated only when the tool is updated (saves process starts per shell)
    function __ll_init --argument-names name
        set -l f (set -q XDG_CACHE_HOME; and echo $XDG_CACHE_HOME; or echo ~/.cache)/dotfiles/$name.fish
        set -l bin (command -v $argv[2]); or return 0
        if not test -s $f; or test $bin -nt $f
            mkdir -p (path dirname $f); $argv[2..] >$f
        end
        source $f
    end
    __ll_init fzf fzf --fish                # Ctrl-R history, Ctrl-T files, Alt-C dirs
    __ll_init zoxide zoxide init fish       # z <part of a path>
    functions -e __ll_init

    # abbreviations expand when typed, so the real command stays visible and in history
    abbr -a ls eza --group-directories-first
    abbr -a ll eza -l --git --group-directories-first
    abbr -a la eza -la --git --group-directories-first
    abbr -a cat bat --paging=never
    abbr -a v nvim
    abbr -a g git
end
