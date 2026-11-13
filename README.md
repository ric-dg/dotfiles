# dotfiles

A lean, fast terminal setup that works the same on your workstation and on the servers
you ssh into: a POSIX `sh` login shell, fish inside tmux, plugin-free Neovim with built-in
language servers, and hardened ssh. It's built for slow machines, so nothing starts a
process it doesn't need. The interactive installer adapts to your OS and to whether you
have root.

```sh
git clone https://github.com/ric-dg/dotfiles ~/dotfiles     # any location works
~/dotfiles/install.sh setup                                 # interactive; --yes = defaults
```

`setup` asks, one step at a time:
1. **Profile:** workstation ("laptop") or server.
2. **Link the configs:** anything already there is backed up first.
3. **Tool groups and language servers** to use.
4. **Installs what's missing.**
5. **Optional system steps and extras.**

Re-run it any time. Everything has a non-interactive form too:

```sh
./install.sh --dry-run          # what linking would change
./install.sh                    # link (backs up what's there; re-running changes nothing)
./install.sh check              # link drift (exit 1) + missing tools
./install.sh tools [GROUP...]   # install missing tools: core dev extra android lsp lsp:NAME
./install.sh tools --user       # same, without root: per-user with mise
./install.sh lsp                # which language servers Neovim can use here
./install.sh root               # print optional system steps (never runs sudo itself)
```

## Any OS, with or without root

The tools the configs expect are listed in [`tools.conf`](tools.conf). Each line gives a
group, a command, and the package name on each system:

| Where | How tools are installed |
|---|---|
| Arch (pacman), Debian/Ubuntu (apt), Fedora (dnf), Alpine (apk), macOS (Homebrew) | **System packages** when you are root or have `sudo` |
| No root, or no package for that tool | **Per user with [mise](https://mise.jdx.dev)**: prebuilt binaries in `~/.local/share/mise`, put on PATH through mise's shims (no shell hook, so no cost per prompt) |
| Neither | Named as "install by hand" |

CI checks every package name in `tools.conf` against the real package index of each
distribution, and against mise's registry (`tests/manifest.sh`), so a typo or a renamed
package is caught before you hit it.

**Missing tools are pointed out, cheaply.** The installer records what's missing. Your
shells (sh/dash, bash, fish) mention it once per boot, and re-check each entry with shell
builtins, so a tool you installed since then isn't reported and a normal shell start
costs no extra process.

## What's in it

| | |
|---|---|
| `home/.profile` | Login environment (POSIX; also read by display managers): `~/.local/bin` and mise shims on PATH, editor, `ENV` |
| `home/.shrc` | Interactive sh/dash: line editing, a prompt with no forks, aliases; loads `~/.config/sh/local.sh` |
| `home/.bashrc` | Sources `~/.shrc` and `~/.config/bash/*.sh` drop-ins |
| fish | A prompt with 0 processes outside git repos and 1 inside; fzf/zoxide init cached and regenerated only when the tool updates; abbreviations |
| tmux | One file for workstation and servers: fish if installed, else `/bin/sh`; OSC 52 clipboard through ssh; host name in the status line; inside ssh the bar moves to the top, so nested tmux stays readable (inner prefix: `C-b C-b`) |
| Neovim | No plugins. `vim.loader`; **built-in language servers** (Neovim 0.11+) for 15 languages, each enabled only if installed and started only for its file type; OSC 52 yanks over ssh; guarded for Neovim 0.7+ |
| `.vimrc` | The same keys for vim-only machines |
| git | Sensible defaults (`ff=only`, histogram diff, zdiff3, rerere); your identity in an untracked `config.local` |
| ssh | Shared defaults in `~/.ssh/config.d/`, included **last** (after `Match all`) so your per-host settings win: connection reuse (`ControlMaster`), post-quantum key exchange first, AES-GCM first. Your host list stays in your own `~/.ssh/config` |
| `bin/dotpush` | `dotpush host…`: send the tmux/Neovim/vim configs to servers in one ssh round trip, backing up anything replaced |
| Konsole | Ctrl+Tab / Ctrl+Shift+Tab switch tabs (linked only if Konsole is installed) |
| `bin/android-*.sh` | adb/scrcpy helpers (linked only with the `android` tool group) |
| `root/` | Optional pacman hooks that keep `/bin/sh` on dash across bash updates (Arch; shown by `install.sh root`) |

## Make it yours

- **Fork it, then edit `tools.conf`** to add or remove tools: one line each, with `-`
  where a system has no package. `tests/manifest.sh` checks your names.
- **Machine-specific settings go in untracked local files**, which the tracked ones load:

| File | For |
|---|---|
| `~/.config/sh/local.sh` | Aliases and functions for sh/dash/bash |
| `~/.config/fish/conf.d/local.fish` | fish additions |
| `~/.config/nvim/local.lua` | Neovim additions |
| `~/.config/git/config.local` | `[user] name/email` |
| `~/.ssh/config` | Your hosts |

- **Profiles:** `laptop` links everything. `server` links only the editor/terminal set
  and leaves the server's own `.profile`/`.bashrc` alone.
- **Optional extra:** [csw](https://github.com/ric-dg/csw) (one `claude` across several
  Claude Code accounts). `setup` offers it, and when it's installed the installer
  generates its fast `claude` function for fish and sh.

## Lightweight by design

- No plugin managers, and no shell frameworks or prompt engines.
- Tool init scripts are cached.
- Language servers start only for their file type.
- The missing-tools notice uses builtins only.
- mise uses shims rather than a prompt hook.
- The installer is POSIX `sh`, needs no root itself, and never runs `sudo` unless you
  confirm.

## Development

```sh
tests/run.sh        # throwaway HOMEs under dash and bash: linking, tools planning, setup, notices, configs load
tests/privacy.sh    # no private IPs, keys, tokens or emails (also the pre-commit hook)
tests/manifest.sh   # every package name in tools.conf exists (network)
git config core.hooksPath .githooks
```

Issues and pull requests are welcome. Please keep changes POSIX, fork-free on hot paths,
and covered by `tests/run.sh`.

## License

[MIT](LICENSE)
