#!/bin/sh
# manifest.sh: check every package name in tools.conf against the distributions'
# package indexes (network; read-only). Arch: archlinux.org JSON; Debian: madison
# (stable); Fedora: mdapi (rawhide); Alpine: pkgs.alpinelinux.org (edge); Homebrew:
# formulae.brew.sh; mise: `mise registry` if mise is on PATH (npm:/go: entries are
# backends, checked by name only). Exit 1 if any name is unknown.
set -u
cd "$(dirname "$0")/.." || exit 2
get() { curl -fsS -m 20 -A dotfiles-manifest-check -o /dev/null -w '%{http_code}' "$1" 2>/dev/null || true; }
check() { # check DISTRO PACKAGE
	case $1 in
	arch) out=$(curl -fsS -m 20 "https://archlinux.org/packages/search/json/?name=$2" 2>/dev/null)
		case $out in *'"pkgname": "'"$2"'"'* | *'"pkgname":"'"$2"'"'*) return 0 ;; esac; return 1 ;;
	debian) curl -fsS -m 20 "https://qa.debian.org/madison.php?package=$2&s=stable&text=on" 2>/dev/null | grep -q . ;;
	fedora) [ "$(get "https://mdapi.fedoraproject.org/rawhide/pkg/$2")" = 200 ] ;;
	alpine) curl -fsS -m 20 "https://pkgs.alpinelinux.org/packages?name=$2&branch=edge&arch=x86_64" 2>/dev/null | grep -q "/package/edge/[a-z]*/x86_64/$2\"" ;;
	brew) [ "$(get "https://formulae.brew.sh/api/formula/$2.json")" = 200 ] ;;
	mise) case $2 in npm:* | go:*) return 0 ;; esac
		command -v mise >/dev/null 2>&1 || return 0
		mise registry 2>/dev/null | grep -q "^$2 " ;;
	esac
}
grep -v '^#' tools.conf | while read -r group cmd arch debian fedora alpine brew mise; do
	[ -n "$group" ] || continue
	for pair in "arch $arch" "debian $debian" "fedora $fedora" "alpine $alpine" "brew $brew" "mise $mise"; do
		# shellcheck disable=SC2086 # "distro name" split on purpose
		set -- $pair
		[ "$2" = - ] && continue
		if check "$1" "$2"; then :; else echo "UNKNOWN  $1: $2  (tool $cmd)"; echo x >>"${TMPDIR:-/tmp}/manifest.fail.$$"; fi
	done
done
if [ -e "${TMPDIR:-/tmp}/manifest.fail.$$" ]; then rm -f "${TMPDIR:-/tmp}/manifest.fail.$$"; exit 1; fi
echo "manifest: every package name exists"
