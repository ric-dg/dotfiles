# dotfiles: once per boot, name tools the dotfiles expect but this machine lacks. The
# list is written by the dotfiles install.sh; entries are re-checked here with builtins.
status is-interactive; or return
set -l state (set -q XDG_STATE_HOME; and echo $XDG_STATE_HOME; or echo $HOME/.local/state)/dotfiles/missing
set -l marker (set -q XDG_RUNTIME_DIR; and echo $XDG_RUNTIME_DIR; or echo /tmp)/dotfiles-warned
test -s $state; and not test -e $marker; or return
read -l line <$state
set -l repo dotfiles
test -r (path dirname $state)/repo; and read repo <(path dirname $state)/repo
set -l miss
for spec in (string split ' ' -- $line)
    set -l ok 0
    for c in (string split '|' -- $spec)
        command -q $c; and set ok 1
    end
    test $ok = 1; or set -a miss (string split -m1 '|' -- $spec)[1]
end
set -q miss[1]; and printf 'dotfiles: missing %s (install: %s/install.sh tools)\n' "$miss" $repo >&2
true >$marker
