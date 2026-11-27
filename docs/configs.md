# What each config does

## Shells
- **`~/.profile`** (login, POSIX; also read by display managers): puts Homebrew (if
  installed, ahead of the system directories), `~/.local/bin` and mise's shims on PATH
  (only if they exist), sets the editor and `ENV=~/.shrc`. The Android SDK environment is
  set only if `/opt/android-sdk` exists. Last, it loads `~/.config/sh/profile.local`
  (yours, untracked: this machine's extra PATH entries and variables).
- **zsh** (linked on macOS, where it is the login shell, and wherever zsh is installed):
  - `~/.zshenv` loads `~/.profile`, for every zsh, so `ssh mac <command>` finds your
    tools too; `~/.zprofile` restores its PATH order after macOS's `path_helper`;
  - `~/.zshrc` loads `~/.shrc`, then makes zsh a full alternative to fish: completion
    (Homebrew's too; the full check once a day, a cached dump otherwise), shared history,
    the cached fzf and zoxide init scripts, fish's abbreviations as aliases, emacs keys,
    and the fish prompt's look (no process outside a git repo, one inside);
  - fish-like typing: Up/Down search the history for what is already typed (built in);
    with the packages `zsh-autosuggestions` and `zsh-syntax-highlighting` installed
    (Homebrew, Arch, Debian/Ubuntu, Fedora, Alpine), grey suggestions from history
    (Right arrow accepts) and command colouring, loaded only when present;
  - `~/.config/zsh/local.zsh` is yours.
- **macOS:** zsh stays the login shell (Apple's default); fish runs inside tmux as
  elsewhere, and `zsh` is there when you prefer it. `install.sh` also compiles a
  `tmux-256color` terminfo into `~/.terminfo` (macOS has none).
- **`~/.shrc`** (interactive sh/dash, and bash through `.bashrc`):
  - emacs-style line editing;
  - a prompt that starts no processes;
  - aliases `ls`/`ll` (eza), `v` (nvim), `g` (git), `grep --color`;
  - `t [name]` attaches to or creates a tmux session;
  - the once-per-boot missing-tools line;
  - loads `~/.config/sh/local.sh`.
- **`~/.bashrc`:** sources `~/.shrc`, then every `~/.config/bash/*.sh`.
- **fish:**
  - a git-aware prompt (no process outside repos, one inside);
  - the zoxide and fzf init scripts are cached and regenerated only when the tool
    updates;
  - abbreviations: `ls`, `ll`, `la`, `cat` (bat), `v`, `g`.
  - `conf.d/local.fish` is yours.

## tmux (`~/.config/tmux/tmux.conf`; servers get it as `~/.tmux.conf`)
- **Shell and colours:** fish if installed, else `/bin/sh`; `tmux-256color` where its
  terminfo exists; true colour.
- **Mouse and history:** mouse on, 50 000 lines of history, `escape-time 10` (no
  Esc lag in vim).
- **Copying:** vi copy mode (`v` select, `y` copy). Copies reach your local clipboard
  through ssh (OSC 52), and `wl-copy` is used when present.
- **Splits:** `"` and `%` split and `c` opens a window, all in the current directory;
  `r` reloads the config.
- **Nested tmux:** inside ssh the status bar is on top in another shade. Send keys to
  the inner tmux with `C-b C-b`.

## Neovim (`~/.config/nvim/`, no plugins)
- **General:** relative numbers, smart case search, persistent undo, `vim.loader`
  cache.
- **Clipboard:** over ssh, yanks go to your local clipboard (OSC 52, copy only); locally,
  the system clipboard.
- **Keys** (leader = Space): `<leader>w` save, `<leader>e` file explorer,
  `<leader>f` find file, `<leader>g` ripgrep, `Esc` clears the search highlight.
- **Language servers** (Neovim 0.11+): one file per server in `lsp/`, enabled only if
  installed and started only for its file type.
  - Completion pops up as you type; diagnostics are shown inline.
  - Keys: `K` hover, `grn` rename, `gra` code action, `grr` references, `gri`
    implementation, `gO` symbols, `[d`/`]d` diagnostics, `<C-s>` signature help,
    `<leader>F` format.
  - The list is in [tools.md](tools.md#lsp).
- `local.lua` is yours.

## vim (`~/.vimrc`)
The same options and Space keys for machines without Neovim. A minimal `vi` skips it
silently.

## git (`~/.config/git/config`)
`pull.ff = only`, `push.autoSetupRemote`, `fetch.prune`, histogram diff, `zdiff3`
conflicts, `rerere`, `init.defaultBranch = main`. Put your identity in
`~/.config/git/config.local`.

## ssh (`~/.ssh/config.d/10-hardening.conf`)
Included at the end of your `~/.ssh/config` (after `Match all`), so your per-host lines
win:
- **Connection reuse:** `ControlMaster`, `ControlPersist 10m`, so a new session to the
  same host opens instantly.
- **Keep-alives.**
- **Algorithm order:** post-quantum key exchange first, then AES-GCM before ChaCha20
  (cheaper with AES-NI).
- **`IdentitiesOnly`.**

## Other
- **`bin/dotpush host…`:** copies the server set (tmux, Neovim, vim) over ssh.
- **Konsole:** Ctrl+Tab / Ctrl+Shift+Tab switch tabs, if Konsole is installed.
- **`bin/android-*.sh`:** adb/scrcpy helpers, with the `android` group.
