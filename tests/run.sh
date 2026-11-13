#!/bin/sh
# shellcheck disable=SC2016,SC2086,SC2012 # inner `sh -c` scripts expand their own $1; $SH may be "busybox ash" (split on purpose); ls only counts backups
# dotfiles tests: every run uses a throwaway $HOME, so nothing on this machine changes.
#   tests/run.sh            (SHELLS="dash bash" by default)
set -u
REPO=$(cd "$(dirname "$0")/.." && pwd)
PASS=0 FAIL=0
ok() { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL [%s] %s\n' "$SH" "$*"; }
check() { d=$1; shift; if "$@" >/dev/null 2>&1; then ok; else bad "$d"; fi; }
linked() { [ "$(readlink "$H/$1")" = "$REPO/$2" ]; }
has() { printf '%s' "$1" | grep -q -- "$2"; }

suite() { # suite SHELL
	SH=$1
	H=$(mktemp -d)
	export HOME="$H" XDG_STATE_HOME="$H/.local/state" XDG_CURRENT_DESKTOP=KDE
	unset XDG_CONFIG_HOME
	i() { $SH "$REPO/install.sh" "$@"; }

	# a machine that already has some config
	mkdir -p "$H/.ssh"
	printf 'Host special\n    HostName 192.0.2.1\n    ControlPath /tmp/special-%%C\n' >"$H/.ssh/config"
	chmod 600 "$H/.ssh/config"
	echo '" my old vimrc' >"$H/.vimrc"

	i --dry-run >/dev/null
	check "dry run changes nothing" [ ! -L "$H/.vimrc" ] && check "dry run leaves ssh config alone" sh -c '! grep -q "dotfiles:" "$1"' _ "$H/.ssh/config"

	out=$(i --profile laptop)
	check "laptop: fish config linked" linked .config/fish/config.fish home/.config/fish/config.fish
	check "laptop: .profile linked" linked .profile home/.profile
	check "laptop: tmux linked" linked .config/tmux/tmux.conf home/.config/tmux/tmux.conf
	check "laptop: dotpush linked" linked .local/bin/dotpush bin/dotpush
	check "laptop: android scripts NOT linked unless the android group is selected" [ ! -e "$H/.local/bin/android-connect.sh" ]
	check "laptop: no mise config is linked (mise keeps its own, untracked)" [ ! -e "$H/.config/mise/config.toml" ]
	check "laptop: fish notice linked" linked .config/fish/conf.d/dotfiles.fish home/.config/fish/conf.d/dotfiles.fish
	check "install records where the repo is" [ "$(cat "$H/.local/state/dotfiles/repo")" = "$REPO" ]
	check "laptop: dotpush server set uses the same tmux file" linked .config/dotpush/files/.tmux.conf home/.config/tmux/tmux.conf
	check "existing file backed up" sh -c 'grep -q "my old vimrc" "$1"/.local/state/dotfiles/backup/*/.vimrc' _ "$H"
	check "ssh include appended once" [ "$(grep -c 'dotfiles: shared defaults' "$H/.ssh/config")" = 1 ]
	check "ssh config stays mode 600" [ "$(stat -c %a "$H/.ssh/config")" = 600 ]
	check "ssh: per-host value still wins" sh -c 'ssh -G -F "$1/.ssh/config" special 2>/dev/null | grep -q "^controlpath /tmp/special-"' _ "$H"
	check "ssh: shared defaults apply elsewhere" sh -c 'ssh -G -F "$1/.ssh/config" other 2>/dev/null | grep -q "^controlmaster auto"' _ "$H"
	check "sockets dir private" [ "$(stat -c %a "$H/.ssh/sockets")" = 700 ]

	out=$(i --profile laptop)
	check "second run changes nothing" sh -c 'printf "%s" "$1" | grep -q "already up to date"' _ "$out"
	check "second run makes no new backup" [ "$(ls "$H/.local/state/dotfiles/backup" | wc -l)" = 1 ]
	check "ssh include still once" [ "$(grep -c 'dotfiles: shared defaults' "$H/.ssh/config")" = 1 ]
	check "check passes when installed" i check --profile laptop

	rm "$H/.vimrc"
	echo 'x' >"$H/.vimrc"
	check "check reports drift" sh -c '! "$@"' _ $SH "$REPO/install.sh" check --profile laptop

	# configs load in their real programs (where installed)
	check "sh files parse" dash -n "$H/.profile" "$H/.shrc"
	check "bashrc parses" bash -n "$H/.bashrc"
	if command -v fish >/dev/null; then check "fish files parse" fish -n "$H/.config/fish/config.fish" "$H/.config/fish/functions/fish_prompt.fish"; fi
	if command -v tmux >/dev/null; then check "tmux config loads" tmux -L dotfiles-test -f "$H/.config/tmux/tmux.conf" start \; kill-server; fi
	if command -v nvim >/dev/null; then check "nvim config loads" nvim --clean --headless -u "$H/.config/nvim/init.lua" +q; fi
	check "git config parses" git config -f "$H/.config/git/config" --list
	# dev layer: native LSP enables only installed servers; install hints; nested tmux
	check "nvim lsp dir linked" linked .config/nvim/lsp home/.config/nvim/lsp
	if command -v nvim >/dev/null && nvim --headless -c 'if has("nvim-0.11") | qa | else | cq | endif' 2>/dev/null; then
		mkdir -p "$H/fakelsp"; printf '#!/bin/sh\nexit 0\n' >"$H/fakelsp/gopls"; chmod +x "$H/fakelsp/gopls"
		out=$(PATH="$H/fakelsp:$PATH" nvim --headless -c 'lua io.write(table.concat(vim.tbl_keys(vim.lsp._enabled_configs or {}), ","))' +q 2>&1)
		check "nvim enables gopls when its command exists" has "$out" gopls
		# the CI image ships some servers (e.g. clangd), so check the rule, not a fixed list:
		# every enabled server's command must exist
		out=$(PATH="$H/fakelsp:$PATH" nvim --headless -c 'lua local bad = {} for name in pairs(vim.lsp._enabled_configs or {}) do local c = vim.lsp.config[name] if vim.fn.executable(c.cmd[1]) ~= 1 then bad[#bad + 1] = name end end io.write(#bad == 0 and "all-installed" or table.concat(bad, ","))' +q 2>&1)
		check "nvim enables only servers whose command exists" [ "$out" = all-installed ]
	fi
	out=$(PATH="$H/fakelsp:/usr/bin:/bin" i lsp)
	check "install.sh lsp reports a missing server" has "$out" 'missing  ruff'
	check "install.sh lsp says how to add servers" has "$out" 'install.sh tools lsp:'
	if command -v tmux >/dev/null; then
		check "tmux: status bar at the bottom locally" [ "$(env -u SSH_CONNECTION tmux -L dt1 -f "$H/.config/tmux/tmux.conf" start \; show -gv status-position \; kill-server)" = bottom ]
		check "tmux: status bar on top inside ssh (nested)" [ "$(SSH_CONNECTION='1.2.3.4 1 5.6.7.8 22' tmux -L dt2 -f "$H/.config/tmux/tmux.conf" start \; show -gv status-position \; kill-server)" = top ]
	fi
	check "root prints the hook commands" sh -c '"$@" | grep -q "dash-as-sh.hook"' _ $SH "$REPO/install.sh" root

	# android group: selecting it links the helper scripts
	i tools android --dry-run >/dev/null
	mkdir -p "$H/.local/state/dotfiles"; echo "core dev extra android" >"$H/.local/state/dotfiles/groups"
	i --profile laptop >/dev/null
	check "android group links the helper scripts" linked .local/bin/android-connect.sh bin/android-connect.sh

	# tools: plan split (system with root/sudo, per user with mise) on a PATH without the tool
	echo "core lsp:gopls" >"$H/.local/state/dotfiles/groups"
	out=$(i tools --dry-run)
	check "tools plan lists a missing tool" has "$out" 'missing (.*gopls'
	out=$(i tools --dry-run --user)
	check "tools --user plans mise for it" has "$out" 'per user (mise):.*go:golang.org/x/tools/gopls'
	out=$(i lsp)
	check "lsp lists servers from tools.conf" has "$out" 'gopls (gopls)'

	# shell notice: once per boot, re-checked with builtins, names this checkout
	echo "no-such-tool-xyz sh|zzz" >"$H/.local/state/dotfiles/missing"
	rm -f "$H/run/dotfiles-warned"; mkdir -p "$H/run"
	out=$(env -i HOME="$H" PATH="$PATH" XDG_RUNTIME_DIR="$H/run" ENV="$H/.shrc" dash -i -c 'exit' 2>&1 </dev/null)
	check "notice names the missing tool" has "$out" 'missing no-such-tool-xyz'
	check "notice skips tools that are installed (sh)" sh -c '! printf "%s" "$1" | grep -q " sh"' _ "$out"
	check "notice points at this checkout" has "$out" "$REPO/install.sh tools"
	out=$(env -i HOME="$H" PATH="$PATH" XDG_RUNTIME_DIR="$H/run" ENV="$H/.shrc" dash -i -c 'exit' 2>&1 </dev/null)
	check "notice shows only once per boot" sh -c '! printf "%s" "$1" | grep -q "^dotfiles:"' _ "$out"
	rm -f "$H/.local/state/dotfiles/repo" "$H/run/dotfiles-warned"
	out=$(env -i HOME="$H" PATH="$PATH" XDG_RUNTIME_DIR="$H/run" ENV="$H/.shrc" dash -i -c 'exit' 2>&1 </dev/null)
	check "notice without a recorded repo path prints no error" sh -c '! printf "%s" "$1" | grep -q "cannot open"' _ "$out"
	if command -v fish >/dev/null; then
		rm -f "$H/run/dotfiles-warned"
		out=$(env -i HOME="$H" PATH="$PATH" XDG_RUNTIME_DIR="$H/run" fish -i -c 'exit' 2>&1 </dev/null)
		check "fish notice names the missing tool" has "$out" 'missing no-such-tool-xyz'
	fi

	# setup with scripted answers (dry run: nothing installed or written)
	printf 'server\nn\ny\ny\nn\ngopls\nn\nn\n' >"$H/answers"
	out=$(DOTFILES_TTY="$H/answers" i setup --dry-run 2>&1)
	check "setup takes scripted answers in order" has "$out" 'which ones.*gopls'
	check "setup plans the chosen language server" has "$out" 'gopls'
	out=$(i setup --yes --dry-run 2>&1)
	check "setup --yes runs on defaults" has "$out" 'done. Re-run any time'

	# csw's generated files, with a fake csw
	mkdir -p "$H/bin"
	printf '#!/bin/sh\necho "# generated for $2"\n' >"$H/bin/csw"
	chmod +x "$H/bin/csw"
	PATH="$H/bin:$PATH" i --profile laptop >/dev/null
	check "csw init fish written" grep -q 'generated for fish' "$H/.config/fish/functions/claude.fish"
	check "csw init sh written" grep -q 'generated for sh' "$H/.config/sh/csw.sh"

	# dotpush delivers the server set as real files (fake ssh runs the remote side here)
	mkdir -p "$H/remote" "$H/fakebin"
	printf '#!/bin/sh\nwhile [ "$1" != -- ]; do shift; done; shift; shift\nHOME=$FAKEHOME exec sh -c "$1"\n' >"$H/fakebin/ssh"
	chmod +x "$H/fakebin/ssh"
	PATH="$H/fakebin:$PATH" FAKEHOME="$H/remote" "$H/.local/bin/dotpush" srv >/dev/null
	check "dotpush: tmux arrives as a real ~/.tmux.conf" sh -c '[ -f "$1/.tmux.conf" ] && [ ! -L "$1/.tmux.conf" ]' _ "$H/remote"
	check "dotpush: nvim and vim configs arrive" [ -f "$H/remote/.config/nvim/init.lua" ] && check "dotpush: vimrc" [ -f "$H/remote/.vimrc" ]
	rm -rf "$H"

	# server profile: leaves the server's own shell files alone
	H=$(mktemp -d)
	export HOME="$H" XDG_STATE_HOME="$H/.local/state"
	unset XDG_CURRENT_DESKTOP WAYLAND_DISPLAY DISPLAY
	echo '# distro bashrc' >"$H/.bashrc"
	i >/dev/null
	check "server is the default without a desktop" linked .config/nvim/init.lua home/.config/nvim/init.lua
	check "server: .bashrc untouched" grep -q 'distro bashrc' "$H/.bashrc"
	check "server: no .profile link" [ ! -L "$H/.profile" ]
	check "server: no dotpush" [ ! -e "$H/.local/bin/dotpush" ]
	check "server: no mise config linked" [ ! -e "$H/.config/mise/config.toml" ]
	check "server: check passes" i check
	rm -rf "$H"
}

for s in ${SHELLS:-dash bash}; do
	command -v "$s" >/dev/null 2>&1 || continue
	before=$FAIL
	suite "$(command -v "$s")"
	[ "$FAIL" = "$before" ] && printf '  ok   [%s]\n' "$s"
done
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
