# Install, update, uninstall

## Quick start

```sh
git clone https://github.com/ric-dg/dotfiles ~/dotfiles   # any location works
~/dotfiles/install.sh setup
```

`setup` asks, one step at a time. Press Enter to take the default in brackets, or run
`setup --yes` to take every default.

1. **Profile:** `laptop` (a workstation: everything) or `server` (editor and terminal
   only; the server's own `.profile`/`.bashrc` are left alone). The default is `laptop`
   when a desktop session is running.
2. **Link the config files:** each file in `home/` becomes a symlink in `$HOME`.
   Anything already there is moved to `~/.local/state/dotfiles/backup/<time>/` first.
3. **Tool groups:** `core`, `dev`, `extra`, `android` (laptop only), then which Neovim
   **language servers** you want (names, `all`, or `-`). See [tools.md](tools.md).
4. **Install as:** `system` (packages through your package manager) or `user` (mise,
   inside your home, no root). Asked only when you have root or a sudo-like command.
5. **The missing tools:** the plan is shown before anything is installed.
6. **Optional:** system steps (Arch: dash as `/bin/sh`), and
   [csw](https://github.com/ric-dg/csw).

Re-run `setup` any time; it only changes what differs.

## Commands

| Command | What it does |
|---|---|
| `./install.sh setup [--yes]` | The interactive walk-through above |
| `./install.sh [--profile laptop\|server] [--dry-run]` | Link the configs (re-running changes nothing) |
| `./install.sh check` | Link drift (exit 1 if any) and missing tools |
| `./install.sh tools [GROUP…]` | Install missing tools of the saved groups, or of `core dev extra android lsp lsp:NAME` |
| `./install.sh lsp` | Which language servers Neovim can use here |
| `./install.sh root` | Print optional system steps (never runs them) |
| `./install.sh uninstall [--dry-run]` | Remove the links and the ssh include; keeps backups, your local files and installed tools |

`--dry-run` works with every command that changes something.

## Root, sudo, or neither

| You are | `tools` installs with |
|---|---|
| root | the package manager directly |
| a user with `sudo`, `sudo-rs`, `doas` or `run0` | the package manager through the first of those found; pick one with `--sudo=doas` (or `DOTFILES_SUDO=doas`) |
| a user without any of them | mise, per user |
| on macOS | Homebrew (no root needed) |

Force a method with `--system` or `--user`. Supported package managers: pacman, apt,
dnf, apk, Homebrew. On other systems everything goes through mise.

mise installs prebuilt binaries into `~/.local/share/mise` and puts them on PATH through
its *shims* folder, which `~/.profile` adds only if it exists. There is no shell hook,
so nothing runs at each prompt.

## Missing tools

After any `install`, `check`, `tools` or `setup`, the installer records the missing
tools in `~/.local/state/dotfiles/missing`. The first interactive shell after each boot
(sh, dash, bash or fish) prints one line about them. Each entry is re-checked first
with shell builtins, so tools you installed since aren't listed, and there's no extra
process at shell start.

## Update

```sh
git -C ~/dotfiles pull && ~/dotfiles/install.sh check
```

The configs are symlinks, so a pull updates them immediately. `check` lists any new file
to link (run `./install.sh`) and any new tool (run `./install.sh tools`).

## Servers without cloning

From a workstation that has the repo: `dotpush host…` copies the tmux, Neovim and vim
configs to each host in one ssh round trip, backing up anything it replaces. Or clone on
the server and run `./install.sh setup` there; the `server` profile is the default
without a desktop.
