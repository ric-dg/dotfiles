function fish_prompt --description 'Write out the prompt'
    # Same look as before, but cheap: 0 processes outside a git repo, 1 inside (was 1 and 6-7).
    set -l laststatus $status

    # find the repo by walking up for .git using builtins only (no fork)
    set -l d $PWD
    while not test -e $d/.git
        if test "$d" = /
            set d
            break
        end
        set d (path dirname $d)
    end

    set -l git_info
    if set -q d[1]
        # one git call gives branch + file states; --no-optional-locks avoids index writes
        set -l lines (command git --no-optional-locks status --porcelain --branch 2>/dev/null)
        set -l branch (string replace -r '^## (No commits yet on )?' '' -- $lines[1] |
            string replace -r '\.\.\..*| \[.*\]$' '' |
            string replace 'HEAD (no branch)' detached)
        set -l st $lines[2..]
        set -l s
        string match -qr '^[MARC]' -- $st; and set -a s (set_color green)✚
        string match -qr '^.M' -- $st; and set -a s (set_color green)✱
        string match -qr '^(D|.D)' -- $st; and set -a s (set_color red)✖
        string match -qr '^R' -- $st; and set -a s (set_color purple)➜
        string match -qr '^(U.|.U|AA|DD)' -- $st; and set -a s (set_color brown)═
        string match -qr '^\?\?' -- $st; and set -a s (set_color red)≠
        set -q s[1]; or set s (set_color green):
        set git_info "(git"(string join "" $s)(set_color -o blue)"$branch"(set_color white)")"
    end

    # Disable PWD shortening by default.
    set -q fish_prompt_pwd_dir_length
    or set -lx fish_prompt_pwd_dir_length 0

    set_color -b black
    printf '%s%s%s%s%s%s%s%s%s%s%s%s%s' (set_color -o white) '❰' (set_color green) $USER (set_color white) '❙' (set_color yellow) (prompt_pwd) (set_color white) $git_info (set_color white) '❱' (set_color white)
    if test $laststatus -eq 0
        printf "%s✔%s≻%s " (set_color -o green) (set_color white) (set_color --reset)
    else
        printf "%s✘%s≻%s " (set_color -o red) (set_color white) (set_color --reset)
    end
end
