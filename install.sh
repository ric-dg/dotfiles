#!/bin/sh
# shellcheck shell=dash
#
# dotfiles installer. Links the files in home/ into $HOME and installs the tools the
# dotfiles expect (tools.conf), on any OS: system packages with root/sudo, otherwise
# per user with mise.
#
#   ./install.sh setup     [--yes]                    interactive: profile, links, tool groups,
#                                                     language servers, system steps, optional extras
#   ./install.sh [install] [--profile laptop|server] [--dry-run]   link everything (default)
#   ./install.sh check     [--profile laptop|server]  report link drift (exit 1) + missing tools
#   ./install.sh tools     [GROUP...] [--system|--user] [--sudo=CMD] [--yes] [--dry-run]
#                          install missing tools of the saved groups (or the GROUPs given:
#                          core dev extra android lsp lsp:NAME). Default: system packages if
#                          you are root or have sudo / sudo-rs / doas / run0 (--sudo=CMD picks
#                          one), else per user with mise. --system / --user force a method.
#   ./install.sh lsp                                  which language servers Neovim can use here
#   ./install.sh root                                 print the sudo steps (never runs them)
#   ./install.sh uninstall [--dry-run]                remove our links + the ssh include (keeps
#                                                     backups, local files and installed tools)
#
# Profiles:
#   laptop  everything: shells (.profile/.shrc/.bashrc), fish, tmux, nvim, vim, git, ssh,
#           dotpush (+ its server file set); Konsole tab keys if Konsole is installed;
#           the Android helper scripts if the android tool group is selected.
#   server  the editor/terminal set: fish, tmux, nvim, vim, git, ssh. The server's own
#           .profile/.bashrc are left alone.
#   Default: laptop when a desktop session is running, otherwise server.
#
# Files are symlinked, so the repo stays the source of truth (`git diff` shows any edit).
# Anything already there is moved to ~/.local/state/dotfiles/backup/<time>/ first.
# Missing tools are listed in ~/.local/state/dotfiles/missing; your shells mention them
# once per boot (builtins only, no extra processes).
# Machine-specific things live in untracked local files the tracked ones load:
#   ~/.config/sh/local.sh, ~/.config/fish/conf.d/local.fish, ~/.config/nvim/local.lua,
#   ~/.config/git/config.local, and your host list in ~/.ssh/config.
set -eu

REPO=$(cd "$(dirname "$0")" && pwd)
STATE=${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP=$STATE/backup/$STAMP
DRY=0
YES=0
FORCE_USER=0
FORCE_SYSTEM=0
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
home/.config/fish/conf.d/dotfiles.fish        .config/fish/conf.d/dotfiles.fish
home/.config/tmux/tmux.conf                   .config/tmux/tmux.conf
home/.config/nvim/init.lua                    .config/nvim/init.lua
home/.config/nvim/lsp                         .config/nvim/lsp
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
bin/dotpush                                   .local/bin/dotpush
home/.config/tmux/tmux.conf                   .config/dotpush/files/.tmux.conf
home/.config/nvim/init.lua                    .config/dotpush/files/.config/nvim/init.lua
home/.config/nvim/lsp                         .config/dotpush/files/.config/nvim/lsp
home/.vimrc                                   .config/dotpush/files/.vimrc
EOF
}
# extras that only make sense where their program or tool group is present
files_optional() {
	has konsole && echo "profiles/laptop/.local/share/kxmlgui5/konsole/konsoleui.rc  .local/share/kxmlgui5/konsole/konsoleui.rc"
	groups_load
	case " $GROUPS_SEL " in *" android "*)
		for f in connect install devices; do echo "bin/android-$f.sh  .local/bin/android-$f.sh"; done ;;
	esac
	return 0
}
files() { files_common; [ "$PROFILE" = server ] && return 0; files_laptop; files_optional; }

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
	tools_summary
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
	tools_summary
	return $DRIFT
}

# remove what install linked (only symlinks into this repo) and the ssh include block;
# backups and your local files stay. Tools are not uninstalled (they may predate us).
cmd_uninstall() {
	local src dst cfg=$HOME/.ssh/config tmp last
	say "dotfiles: uninstalling links into $REPO$([ "$DRY" = 1 ] && echo ' (dry run)')"
	PROFILE=laptop
	while read -r src dst; do
		if [ -L "$HOME/$dst" ] && [ "$(readlink "$HOME/$dst")" = "$REPO/$src" ]; then
			say "  unlink  ~/$dst"
			run rm "$HOME/$dst"
		fi
	done <<EOF
$(files; printf '%s\n' "profiles/laptop/.local/share/kxmlgui5/konsole/konsoleui.rc .local/share/kxmlgui5/konsole/konsoleui.rc" "bin/android-connect.sh .local/bin/android-connect.sh" "bin/android-install.sh .local/bin/android-install.sh" "bin/android-devices.sh .local/bin/android-devices.sh")
EOF
	if grep -qF '# dotfiles: shared defaults' "$cfg" 2>/dev/null; then
		say "  remove  the shared-defaults include from ~/.ssh/config"
		if [ "$DRY" = 0 ]; then
			tmp=$(mktemp "$cfg.XXXXXX")
			awk '/^# dotfiles: shared defaults/ { skip = 3 } skip > 0 { skip--; next } { print }' "$cfg" >"$tmp"
			chmod 600 "$tmp"
			mv "$tmp" "$cfg"
		fi
	fi
	run rm -f "$STATE/missing" "$STATE/repo" "$STATE/groups"
	last=''
	for tmp in "$STATE"/backup/*/; do [ -d "$tmp" ] && last=${tmp%/}; done # sorted: newest last
	[ -z "$last" ] || say "  your previous files are in ${last#"$HOME"/} (copy back what you want)"
	say "  kept: your local files (~/.config/sh/local.sh, …), installed tools, backups"
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

# --- tools (tools.conf) ------------------------------------------------------
# tools.conf columns: 1 group  2 command[|alt]  3 arch  4 debian  5 fedora  6 alpine
# 7 brew  8 mise. The package manager found here decides which column is used.
detect_pm() {
	PM='' COL=0 SUDO='' ROOT=no
	if has pacman; then PM=pacman COL=3
	elif has apt-get; then PM=apt COL=4
	elif has dnf; then PM=dnf COL=5
	elif has apk; then PM=apk COL=6
	elif has brew; then PM=brew COL=7
	fi
	# privileges: already root (no prefix); an explicit choice (--sudo=CMD / DOTFILES_SUDO);
	# else the first of sudo, sudo-rs, doas, run0. Homebrew installs as the user.
	local c
	if [ "$PM" = brew ] || [ "$(id -u)" = 0 ]; then ROOT=yes
	elif [ -n "${DOTFILES_SUDO-}" ]; then
		has "$DOTFILES_SUDO" || err "--sudo: '$DOTFILES_SUDO' not found"
		ROOT=$DOTFILES_SUDO SUDO=$DOTFILES_SUDO
	else
		for c in sudo sudo-rs doas run0; do
			if has "$c"; then ROOT=$c SUDO=$c; break; fi
		done
	fi
	[ "$FORCE_USER" = 0 ] || ROOT=no
	if [ "$FORCE_SYSTEM" = 1 ] && [ "$ROOT" = no ]; then
		err "--system needs root, sudo, sudo-rs, doas or run0 (or use --user)"
	fi
}

pm_install_cmd() { # the install command for this package manager (without packages)
	local y=''
	case $PM in
	pacman) [ "$YES" = 0 ] || y=' --noconfirm'; echo "$SUDO pacman -S --needed$y" ;;
	apt) [ "$YES" = 0 ] || y=' -y'; echo "$SUDO apt-get install$y" ;;
	dnf) [ "$YES" = 0 ] || y=' -y'; echo "$SUDO dnf install$y" ;;
	apk) echo "$SUDO apk add" ;;
	brew) echo "brew install" ;;
	esac
}

# selected groups: saved by `setup`/`tools GROUP...`; default by profile
groups_load() {
	GROUPS_SEL=''
	if [ -r "$STATE/groups" ]; then read -r GROUPS_SEL <"$STATE/groups" || true; fi
	if [ -z "$GROUPS_SEL" ]; then
		if [ "$PROFILE" = laptop ]; then GROUPS_SEL='core dev extra'; else GROUPS_SEL='core dev'; fi
	fi
}
groups_save() { run mkdir -p "$STATE"; [ "$DRY" = 1 ] || echo "$1" >"$STATE/groups"; GROUPS_SEL=$1; }

wanted() { # wanted GROUP-FIELD: is this manifest line selected? ("lsp" selects every lsp:NAME)
	local g
	for g in $GROUPS_SEL; do
		[ "$g" = "$1" ] && return 0
		[ "$g" = "${1%%:*}" ] && [ "$1" != "${1%%:*}" ] && return 0
	done
	return 1
}

have_cmd() { # have_cmd "a|b": any of the alternatives on PATH (or in mise's shims)
	local IFS='|' c
	for c in $1; do has "$c" && return 0; [ -x "$HOME/.local/share/mise/shims/$c" ] && return 0; done
	return 1
}

# plan: split the selected, missing tools into system packages, per-user (mise) and manual
plan() {
	local line g c pkg m
	SYS='' USR='' MAN='' MISSING='' NMISS=0
	while IFS= read -r line; do
		case $line in '' | '#'*) continue ;; esac
		# shellcheck disable=SC2086 # split the manifest line into fields on purpose
		set -- $line
		g=$1 c=$2
		wanted "$g" || continue
		have_cmd "$c" && continue
		MISSING="$MISSING $c"
		NMISS=$((NMISS + 1))
		pkg=-
		[ "$COL" = 0 ] || eval "pkg=\${$COL}"
		m=$8
		if [ "$ROOT" != no ] && [ "$pkg" != - ]; then
			case " $SYS " in *" $pkg "*) ;; *) SYS="$SYS $pkg" ;; esac
		elif [ "$m" != - ]; then
			USR="$USR $m"
		else
			MAN="$MAN ${c%%|*}"
		fi
	done <"$REPO/tools.conf"
	MISSING=${MISSING# }
}

# remember what's missing, for the once-per-boot shell notice
save_missing() {
	[ "$DRY" = 1 ] && return 0
	mkdir -p "$STATE"
	echo "$MISSING" >"$STATE/missing"
	echo "$REPO" >"$STATE/repo" # so shell notices can name this checkout, wherever it is
	rm -f "${XDG_RUNTIME_DIR:-/tmp}/dotfiles-warned" 2>/dev/null || true
}

ensure_mise() {
	MISE=$(command -v mise 2>/dev/null || true)
	[ -n "$MISE" ] || { [ -x "$HOME/.local/bin/mise" ] && MISE=$HOME/.local/bin/mise; }
	[ -n "$MISE" ] && return 0
	say "  installing mise (per-user tool manager, https://mise.run) to ~/.local/bin"
	curl -fsSL --proto '=https' --tlsv1.2 https://mise.run | sh >/dev/null || err "mise install failed"
	MISE=$HOME/.local/bin/mise
}

do_install() { # install the plan computed by `plan`
	if [ -n "$SYS" ]; then
		say "  system ($PM):$SYS"
		if [ "$DRY" = 0 ]; then
			[ "$PM" != apt ] || $SUDO apt-get update -qq || true
			# shellcheck disable=SC2086 # command and package list split on purpose
			$(pm_install_cmd) $SYS || say "  (system install failed or was cancelled)"
		fi
	fi
	if [ -n "$USR" ]; then
		say "  per user (mise):$USR"
		if [ "$DRY" = 0 ]; then
			ensure_mise
			# npm:/go: tools need their runtime first
			case $USR in *npm:*) "$MISE" use -g node@lts ;; esac
			case $USR in *go:*) "$MISE" use -g go@latest ;; esac
			# shellcheck disable=SC2086
			"$MISE" use -g $USR || say "  (mise install failed for some tools)"
		fi
	fi
	[ -z "$MAN" ] || say "  install by hand (not packaged here):$MAN"
}

cmd_tools() { # cmd_tools [GROUP...]
	detect_pm
	groups_load
	if [ $# -gt 0 ]; then
		local g new=$GROUPS_SEL
		for g; do case " $new " in *" $g "*) ;; *) new="$new $g" ;; esac; done
		groups_save "${new# }"
	fi
	plan
	say "tools for: $GROUPS_SEL  (package manager: ${PM:-none}, root: $ROOT)"
	if [ "$NMISS" = 0 ]; then say "  everything is installed"; save_missing; return 0; fi
	say "  missing ($NMISS): $MISSING"
	if [ "$YES" = 0 ] && [ "$DRY" = 0 ] && ! yes_no "Install them now?" y; then save_missing; return 0; fi
	do_install
	plan
	save_missing
	if [ "$NMISS" = 0 ]; then say "  all tools installed"; else say "  still missing: $MISSING"; fi
}

cmd_lsp() {
	local line g c
	say "Neovim language servers (each is enabled when its command is installed):"
	while IFS= read -r line; do
		case $line in lsp:*) ;; *) continue ;; esac
		# shellcheck disable=SC2086
		set -- $line
		g=${1#lsp:} c=$2
		if have_cmd "$c"; then say "  ok       $g ($c)"; else say "  missing  $g ($c)"; fi
	done <"$REPO/tools.conf"
	say "add some:  ./install.sh tools lsp:gopls lsp:ruff    all of them:  ./install.sh tools lsp"
	say "each server runs only while you edit its file type"
}

# --- interactive setup ----------------------------------------------------------
TTY=${DOTFILES_TTY:-/dev/tty}
ask() { # ask QUESTION DEFAULT: sets REPLY (the default with --yes or without a terminal)
	local ans=''
	if [ "$YES" = 1 ]; then REPLY=$2; say "$1 [$2] $2"; return 0; fi
	printf '%s [%s] ' "$1" "$2"
	read -r ans <&3 || ans=''
	[ -t 3 ] || printf '%s\n' "$ans" # scripted answers: show them, as a terminal would
	REPLY=${ans:-$2}
}
yes_no() { ask "$1" "$2"; case $REPLY in [Yy]*) return 0 ;; *) return 1 ;; esac; }

group_missing() { # group_missing GROUP: names of missing tools in that group
	local line out=''
	while IFS= read -r line; do
		case $line in "$1 "* | "$1:"*) ;; *) continue ;; esac
		# shellcheck disable=SC2086
		set -- $line
		have_cmd "$2" || out="$out ${2%%|*}"
	done <"$REPO/tools.conf"
	echo "${out# }"
}

cmd_setup() {
	local os g m sel='' def lsp=''
	# open it to know: /dev/tty can exist and be "readable" with no terminal attached (CI)
	[ "$YES" = 1 ] || { : <"$TTY"; } 2>/dev/null || { YES=1; say "(no terminal: using the defaults)"; }
	# one descriptor for all answers (reopening the terminal per question would restart a
	# scripted answer file at its first line)
	[ "$YES" = 1 ] || exec 3<"$TTY"
	detect_pm
	os=$(sed -n 's/^PRETTY_NAME="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' /etc/os-release 2>/dev/null || true)
	say "dotfiles setup on ${os:-$(uname -s)}: package manager ${PM:-none}, root: $ROOT"
	say "(per-user installs use mise when there is no root or no package)"
	say ""
	ask "1. Profile: laptop (everything) or server (editor/terminal only)?" "$PROFILE"
	case $REPLY in laptop | server) PROFILE=$REPLY ;; *) say "   keeping $PROFILE" ;; esac
	if yes_no "2. Link the config files into $HOME (anything there is backed up)?" y; then cmd_install >/dev/null && say "   linked"; fi
	groups_load
	say "3. Tool groups (from tools.conf):"
	for g in core dev extra android; do
		[ "$g" != android ] || [ "$PROFILE" = laptop ] || continue
		m=$(group_missing "$g")
		case " $GROUPS_SEL " in *" $g "*) def=y ;; *) def=n ;; esac
		[ "$g" != core ] || def=y
		if yes_no "   $g${m:+ (missing: $m)}?" "$def"; then sel="$sel $g"; fi
	done
	for g in $GROUPS_SEL; do case $g in lsp*) lsp="$lsp ${g#lsp:}" ;; esac; done
	say "   language servers available: $(sed -n 's/^lsp:\([a-z_]*\).*/\1/p' "$REPO/tools.conf" | tr '\n' ' ')"
	ask "   which ones (names, 'all', or '-' for none)?" "${lsp# }"
	case $REPLY in
	all) sel="$sel lsp" ;;
	- | none) ;;
	*) for g in $REPLY; do sel="$sel lsp:$g"; done ;;
	esac
	groups_save "${sel# }"
	if [ "$ROOT" != no ] && [ "$PM" != brew ] && [ "$FORCE_USER" = 0 ] && [ "$FORCE_SYSTEM" = 0 ]; then
		ask "   install as: system (packages via ${SUDO:-root}) or user (mise, in your home, no root)?" system
		case $REPLY in u*) FORCE_USER=1; ROOT=no ;; esac
	fi
	plan
	if [ "$NMISS" -gt 0 ]; then
		say "4. Missing tools ($NMISS):$([ -n "$SYS" ] && echo " system:$SYS")$([ -n "$USR" ] && echo " · per user:$USR")$([ -n "$MAN" ] && echo " · by hand:$MAN")"
		if yes_no "   Install them now?" y; then do_install; plan; fi
	else
		say "4. All selected tools are installed"
	fi
	save_missing
	if [ "$PROFILE" = laptop ] && [ "$PM" = pacman ]; then
		say "5. System steps (dash as /bin/sh + login shell); they need sudo:"
		cmd_root | sed 's/^/   /'
		if [ "$YES" = 0 ] && yes_no "   Run them now?" n; then cmd_root | grep -v '^#' | sh; fi
	fi
	if ! has csw; then
		if yes_no "6. Install csw (Claude Code across several accounts, github.com/ric-dg/csw)?" n; then
			[ "$DRY" = 1 ] || curl -fsSL --proto '=https' --tlsv1.2 https://raw.githubusercontent.com/ric-dg/csw/main/install.sh | sh
		fi
	fi
	say "done. Re-run any time: ./install.sh setup   ·   drift: ./install.sh check"
	[ "$NMISS" = 0 ] || say "still missing: $MISSING"
}

tools_summary() { # one line for install/check, and refresh the shell notice list
	detect_pm
	groups_load
	plan
	save_missing
	if [ "$NMISS" = 0 ]; then say "  tools    all installed ($GROUPS_SEL)"
	else say "  tools    missing: $MISSING  (./install.sh tools)"; fi
}

main() {
	local cmd=install
	PROFILE=''
	while [ $# -gt 0 ]; do
		case $1 in
		# group names after `tools` are groups ("tools lsp" = the lsp group, not the lsp command)
		core | dev | extra | android | lsp | lsp:*)
			if [ "$cmd" = tools ]; then TOOL_ARGS="${TOOL_ARGS-} $1"
			elif [ "$1" = lsp ]; then cmd=lsp
			else err "groups go after 'tools'"; fi
			;;
		install | check | root | setup | uninstall) cmd=$1 ;;
		tools) cmd=tools ;;
		--yes | -y) YES=1 ;;
		--user) FORCE_USER=1 ;;
		--system) FORCE_SYSTEM=1 ;;
		--sudo=*) DOTFILES_SUDO=${1#*=} ;;
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
	tools)
		# shellcheck disable=SC2086 # group list split on purpose
		cmd_tools ${TOOL_ARGS-}
		;;
	lsp) cmd_lsp ;;
	setup) cmd_setup ;;
	uninstall) cmd_uninstall ;;
	esac
}

{ main "$@" || exit 1; } && exit 0
