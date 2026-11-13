#!/bin/sh
# shellcheck shell=dash
#
# dotfiles installer. Links the files in home/ (and the profile's extras) into $HOME.
#
#   ./install.sh [install] [--profile laptop|server] [--dry-run]   link everything (default)
#   ./install.sh check     [--profile laptop|server]               report drift; exit 1 if any
#   ./install.sh root                                              print the sudo steps (never runs them)
#   ./install.sh tools                                             install mise + the pinned tools
#
# Profiles:
#   laptop  everything: shells (.profile/.shrc/.bashrc), fish, tmux, nvim, vim, git, ssh,
#           Konsole tab keys, dotpush (+ its server file set). Tools come from pacman.
#   server  the editor/terminal set: fish, tmux, nvim, vim, git, ssh, and the mise config
#           (./install.sh tools) for machines with old packages or no root.
#           The server's own .profile/.bashrc are left alone.
#   Default: laptop when a desktop session is running, otherwise server.
#
# Files are symlinked, so the repo stays the source of truth (`git diff` shows any edit).
# Anything already there is moved to ~/.local/state/dotfiles/backup/<time>/ first.
# Machine-specific things live in untracked local files the tracked ones load:
#   ~/.config/sh/local.sh, ~/.config/fish/conf.d/local.fish, ~/.config/nvim/local.lua,
#   ~/.config/git/config.local, and your host list in ~/.ssh/config.
set -eu

REPO=$(cd "$(dirname "$0")" && pwd)
STATE=${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP=$STATE/backup/$STAMP
DRY=0
CHANGED=0
DRIFT=0

say() { printf '%s\n' "$*"; }
err() { printf 'dotfiles: %s\n' "$*" >&2; exit 1; }
has() { command -v "$1" >/dev/null 2>&1; }
run() { [ "$DRY" = 1 ] || "$@"; } # dry run: the backup/link lines already describe it

# "SOURCE-in-repo  TARGET-in-HOME" pairs, one per line
files_common() {
	cat <<'EOF'
home/.config/fish/config.fish                 .config/fish/config.fish
home/.config/fish/functions/fish_prompt.fish  .config/fish/functions/fish_prompt.fish
home/.config/tmux/tmux.conf                   .config/tmux/tmux.conf
home/.config/nvim/init.lua                    .config/nvim/init.lua
home/.vimrc                                   .vimrc
home/.config/git/config                       .config/git/config
home/.ssh/config.d/10-hardening.conf          .ssh/config.d/10-hardening.conf
EOF
}
files_laptop() {
	cat <<'EOF'
home/.profile                                 .profile
home/.shrc                                    .shrc
home/.bashrc                                  .bashrc
profiles/laptop/.local/share/kxmlgui5/konsole/konsoleui.rc  .local/share/kxmlgui5/konsole/konsoleui.rc
bin/dotpush                                   .local/bin/dotpush
bin/android-connect.sh                        .local/bin/android-connect.sh
bin/android-install.sh                        .local/bin/android-install.sh
bin/android-devices.sh                        .local/bin/android-devices.sh
home/.config/tmux/tmux.conf                   .config/dotpush/files/.tmux.conf
home/.config/nvim/init.lua                    .config/dotpush/files/.config/nvim/init.lua
home/.vimrc                                   .config/dotpush/files/.vimrc
EOF
}
# mise is server-only: on the laptop the same tools come from pacman, and a second copy
# on PATH would only shadow them
files_server() {
	cat <<'EOF'
home/.config/mise/config.toml                 .config/mise/config.toml
EOF
}
files() { files_common; if [ "$PROFILE" = server ]; then files_server; else files_laptop; fi; }

# link SOURCE TARGET: make $HOME/TARGET a symlink to $REPO/SOURCE, backing up what's there
link() {
	local src=$REPO/$1 dst=$HOME/$2
	[ -e "$src" ] || err "missing in repo: $1"
	if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
		return 0
	fi
	if [ -e "$dst" ] || [ -L "$dst" ]; then
		say "  backup  ~/$2 -> ${BACKUP#"$HOME"/}/$2"
		run mkdir -p "$(dirname "$BACKUP/$2")"
		run mv "$dst" "$BACKUP/$2"
	fi
	say "  link    ~/$2"
	run mkdir -p "$(dirname "$dst")"
	run ln -s "$src" "$dst"
	CHANGED=1
}

# ssh: keep the host list private in ~/.ssh/config; append the shared defaults at the END,
# after `Match all` (an Include after a Host line would only apply to that host)
ssh_include() {
	local cfg=$HOME/.ssh/config marker='# dotfiles: shared defaults (keep this block last)'
	[ -d "$HOME/.ssh/sockets" ] || { run mkdir -p "$HOME/.ssh/sockets"; run chmod 700 "$HOME/.ssh" "$HOME/.ssh/sockets"; }
	if [ -f "$cfg" ] && grep -qF "$marker" "$cfg"; then return 0; fi
	say "  append  ~/.ssh/config: Match all + Include config.d/*.conf"
	if [ "$DRY" = 0 ]; then
		[ -f "$cfg" ] || { : >"$cfg"; chmod 600 "$cfg"; }
		printf '\n%s\nMatch all\nInclude config.d/*.conf\n' "$marker" >>"$cfg"
	fi
	CHANGED=1
}

# generated files: csw's fast `claude` function, when csw is installed
generated() {
	local out
	if ! has csw; then
		say "  note    csw not installed (optional): curl -fsSL https://raw.githubusercontent.com/ric-dg/csw/main/install.sh | sh"
		return 0
	fi
	for out in "fish .config/fish/functions/claude.fish" "sh .config/sh/csw.sh"; do
		# shellcheck disable=SC2086 # split "shell path" on purpose
		set -- $out
		if ! csw init "$1" | cmp -s - "$HOME/$2" 2>/dev/null; then
			say "  write   ~/$2 (csw init $1)"
			if [ "$DRY" = 0 ]; then mkdir -p "$(dirname "$HOME/$2")"; csw init "$1" >"$HOME/$2"; fi
			CHANGED=1
		fi
	done
}

cmd_install() {
	say "dotfiles: installing profile '$PROFILE' from $REPO$([ "$DRY" = 1 ] && echo ' (dry run)')"
	local src dst
	# here-document, not a pipe: the loop must run in this shell (errors stop it, and
	# CHANGED survives)
	while read -r src dst; do link "$src" "$dst"; done <<EOF
$(files)
EOF
	ssh_include
	[ "$PROFILE" = server ] || generated
	if [ "$CHANGED" = 0 ]; then say "dotfiles: already up to date"; else say "dotfiles: done"; fi
	[ "$PROFILE" = server ] || say "system steps (root): ./install.sh root"
}

cmd_check() {
	local src dst
	DRIFT=0
	while read -r src dst; do
		if [ -L "$HOME/$dst" ] && [ "$(readlink "$HOME/$dst")" = "$REPO/$src" ]; then
			say "  ok       ~/$dst"
		elif [ -e "$HOME/$dst" ]; then
			say "  DIFFERS  ~/$dst (not linked to the repo)"; DRIFT=1
		else
			say "  MISSING  ~/$dst"; DRIFT=1
		fi
	done <<EOF
$(files)
EOF
	if grep -qF '# dotfiles: shared defaults' "$HOME/.ssh/config" 2>/dev/null; then
		say "  ok       ~/.ssh/config includes the shared defaults"
	else
		say "  MISSING  ~/.ssh/config include"; DRIFT=1
	fi
	return $DRIFT
}

cmd_root() {
	cat <<EOF
# System steps for the laptop profile (Arch). Review, then run them yourself.
# dash as /bin/sh, kept there by pacman hooks (bash updates reset /usr/bin/sh):
sudo pacman -S --needed dash
sudo install -Dm644 $REPO/root/dash-as-sh.hook /etc/pacman.d/hooks/dash-as-sh.hook
sudo install -Dm644 $REPO/root/dash-removal-guard.hook /etc/pacman.d/hooks/dash-removal-guard.hook
sudo ln -sfT dash /usr/bin/sh
# login shell: POSIX sh (reads ~/.profile); fish stays the interactive shell inside tmux
chsh -s /bin/sh
EOF
}

cmd_tools() {
	if ! has mise; then
		say "installing mise (https://mise.run) to ~/.local/bin"
		[ "$DRY" = 1 ] || { curl -fsSL --proto '=https' --tlsv1.2 https://mise.run | sh; }
	fi
	PATH=$HOME/.local/bin:$PATH
	[ "$DRY" = 1 ] || mise install --yes
}

main() {
	local cmd=install
	PROFILE=''
	while [ $# -gt 0 ]; do
		case $1 in
		install | check | root | tools) cmd=$1 ;;
		--profile) PROFILE=${2:?--profile needs laptop or server}; shift ;;
		--profile=*) PROFILE=${1#*=} ;;
		--dry-run | -n) DRY=1 ;;
		-h | --help) sed -n '4,/^set -eu/p' "$0" | sed '$d; s/^# \{0,1\}//'; return 0 ;;
		*) err "unknown argument: $1 (see --help)" ;;
		esac
		shift
	done
	if [ -z "$PROFILE" ]; then
		if [ -n "${XDG_CURRENT_DESKTOP-}${WAYLAND_DISPLAY-}${DISPLAY-}" ]; then PROFILE=laptop; else PROFILE=server; fi
	fi
	case $PROFILE in laptop | server) ;; *) err "profile must be laptop or server" ;; esac
	case $cmd in
	install) cmd_install ;;
	check) cmd_check ;;
	root) cmd_root ;;
	tools) cmd_tools ;;
	esac
}

{ main "$@" || exit 1; } && exit 0
