#!/bin/sh
# privacy.sh: fail if tracked files contain things a public dotfiles repo must not:
# private IP addresses, private keys, API tokens, real email addresses. Your own
# sensitive words (company names, hostnames, ...) go one per line in the untracked
# ~/.config/dotfiles/private-terms; they're checked too but never published.
# Runs in CI and as the pre-commit hook (git config core.hooksPath .githooks).
set -u
cd "$(dirname "$0")/.." || exit 2
files=$(git ls-files 2>/dev/null; git diff --cached --name-only --diff-filter=AM 2>/dev/null)
[ -n "$files" ] || exit 0
fail=0
hit() { printf 'privacy: %s\n' "$*" >&2; fail=1; }
scan() { # scan LABEL EXTENDED-REGEX [ALLOWED-REGEX]
	out=$(printf '%s\n' "$files" | sort -u | while read -r f; do [ -f "$f" ] && grep -nIHE -- "$2" "$f"; done |
		grep -v 'privacy: allow' | grep -vE -- "${3:-^\$}")
	[ -z "$out" ] || hit "$1:
$out"
}
scan "private IPv4 address" '(^|[^0-9.])(10\.[0-9]{1,3}|192\.168|172\.(1[6-9]|2[0-9]|3[01]))\.[0-9]{1,3}\.[0-9]{1,3}([^0-9]|$)'
scan "private key" '-----BEGIN [A-Z ]*PRIVATE KEY-----'
scan "API token" '(sk-ant-[a-z0-9]+-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9]{30,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,})'
scan "email address (use a noreply address)" '[A-Za-z0-9._%+-]+@([A-Za-z0-9-]+\.)+[a-z]{2,}' \
	'noreply|@openssh\.com|@libssh\.org' # algorithm names like aes128-gcm@openssh.com are not emails
terms=${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/private-terms
if [ -r "$terms" ]; then
	while IFS= read -r t; do
		[ -n "$t" ] && case $t in '#'*) ;; *) scan "private term from $terms" "$(printf '%s' "$t" | sed 's/[][\.*^$/]/\\&/g')" ;; esac
	done <"$terms"
fi
[ "$fail" = 0 ] && echo "privacy: clean"
exit $fail
