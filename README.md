# dotfiles

Lean, fast terminal setup for a low-end Linux laptop and the servers it works on.
POSIX `sh` login shell, fish inside tmux, plugin-free Neovim, hardened ssh.
Everything is measured for process count and start-up time.

```sh
git clone https://github.com/ric-dg/dotfiles ~/src/dotfiles
~/src/dotfiles/install.sh --dry-run     # see what would change
~/src/dotfiles/install.sh               # link everything (backs up what's there)
~/src/dotfiles/install.sh check         # report drift
~/src/dotfiles/install.sh root          # print the system (sudo) steps; never runs them
```

## What's in it

| | |
|---|---|
| `home/.profile` | Login environment (POSIX: dash, bash, SDDM/Plasma all read it): `~/.local/bin` on PATH, editor, `ENV` |
| `home/.shrc` | Interactive dash/sh: line editing, a prompt with no forks, aliases; loads `~/.config/sh/local.sh` |
| `home/.bashrc` | Sources `~/.shrc` and `~/.config/bash/*.sh` drop-ins |
| fish | Prompt with 0 processes outside git repos and 1 inside (2.5× faster than before); fzf/zoxide init cached, regenerated only when the tool updates; abbreviations |
| tmux | One file for laptop and servers: fish, else `/bin/sh`; `tmux-256color` where available; OSC 52 clipboard through ssh; host name in the status line |
| Neovim | No plugins. `vim.loader`; over ssh, yanks reach your local clipboard (OSC 52); guarded for Neovim 0.7+ |
| `.vimrc` | The same keys for vim-only servers; vim-tiny skips it silently |
| git | Sensible defaults (`ff=only`, histogram diff, zdiff3, rerere); identity in untracked `config.local` |
| ssh | Shared defaults in `~/.ssh/config.d/`, included **last** (after `Match all`), so per-host settings win. Connection reuse (`ControlMaster`, `%C`), post-quantum key exchange first, AES-GCM first (cheap with AES-NI). Your host list stays in `~/.ssh/config`, never here. |
| mise | **Server profile only**: pinned tools for machines without root or with old packages (`./install.sh tools`). The laptop uses pacman, so nothing is installed twice. |
| `bin/dotpush` | `dotpush host…` copies tmux/nvim/vim configs to servers in one ssh round trip, backing up anything it replaces |
| Konsole | Ctrl+Tab / Ctrl+Shift+Tab switch tabs like a browser |
| `root/` | pacman hooks that keep `/bin/sh` on dash across bash updates, and restore bash if dash is removed |

## Profiles

- **laptop** (the default when a desktop session is running): everything.
- **server**: fish, tmux, nvim, vim, git, ssh, the mise config. The server's own `.profile` and
  `.bashrc` are left alone. Or skip cloning entirely and run `dotpush server` from
  the laptop.

## Local, never committed

| File | For |
|---|---|
| `~/.config/sh/local.sh` | Machine-specific aliases (e.g. per-account `claude-*`) |
| `~/.config/fish/conf.d/local.fish`, `~/.config/nvim/local.lua` | Machine-specific fish and Neovim additions |
| `~/.config/git/config.local` | `[user] name/email` (use your noreply address) |
| `~/.ssh/config` | Your hosts |
| `~/.config/dotfiles/private-terms` | Words the privacy check must never let into this repo |

## How it installs

Files are **symlinked** to the repo, so `git diff` shows every edit you make in `$HOME`.
Anything already there is moved to `~/.local/state/dotfiles/backup/<time>/`. Re-running
changes nothing, and `--dry-run` shows the plan first. The installer is POSIX `sh` and
never runs `sudo`.

Optional companion: [csw](https://github.com/ric-dg/csw) (one `claude` across several
accounts). When it's installed, the installer generates its fast `claude` function for
fish and sh.

## Development

```sh
tests/run.sh        # installs into throwaway HOMEs under dash and bash, loads every config in its program
tests/privacy.sh    # no private IPs, keys, tokens, emails or private terms (also the pre-commit hook)
git config core.hooksPath .githooks
```

## License

[MIT](LICENSE)
