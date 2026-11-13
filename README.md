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
./install.sh check                # link drift + missing tools
./install.sh tools lsp:gopls      # add a tool or language server (system with sudo, else per user)
./install.sh uninstall --dry-run  # what removing it would do
```

Everything else is in [docs/install.md](docs/install.md).

## Any OS, with or without root

The tools the configs expect are listed in [`tools.conf`](tools.conf). Each line gives a
group, a command, and the package name on each system:

| Where | How tools are installed |
|---|---|
| Arch (pacman), Debian/Ubuntu (apt), Fedora (dnf), Alpine (apk), macOS (Homebrew) | **System packages** when you are root or have `sudo`, `sudo-rs`, `doas` or `run0` (`--sudo=CMD` picks one) |
| No root, or no package for that tool | **Per user with [mise](https://mise.jdx.dev)**: prebuilt binaries in `~/.local/share/mise`, put on PATH through mise's shims (no shell hook, so no cost per prompt) |
| Neither | Named as "install by hand" |

CI checks every package name in `tools.conf` against the real package index of each
distribution, and against mise's registry (`tests/manifest.sh`), so a typo or a renamed
package is caught before you hit it.

**Missing tools are pointed out, cheaply.** The installer records what's missing. Your
shells (sh/dash, bash, fish) mention it once per boot, and re-check each entry with shell
builtins, so a tool you installed since then isn't reported and a normal shell start
costs no extra process.

## Documentation

| Doc | |
|---|---|
| [docs/install.md](docs/install.md) | `setup` step by step, every command, root / sudo / doas / run0 / per-user, update, uninstall |
| [docs/tools.md](docs/tools.md) | Every tool by group, with its package name on each system (generated from `tools.conf`) |
| [docs/configs.md](docs/configs.md) | What each config does, and its keys (shells, tmux, Neovim + language servers, vim, git, ssh) |

## Make it yours

- **Fork it, then edit `tools.conf`** to add or remove tools: one line each, with `-`
  where a system has no package. `tests/manifest.sh` checks your names, and
  `scripts/gen-docs.sh` regenerates [docs/tools.md](docs/tools.md).
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
