# ~/.zshrc: interactive zsh, a full alternative to fish (and the login shell on macOS).
# The shared base from ~/.shrc (aliases, `t`, the missing-tools line), plus what fish has:
# completion, history, fzf + zoxide, fish's abbreviations as aliases, and the same prompt.
# Machine-specific additions: ~/.config/zsh/local.zsh (untracked).
unset _dotfiles_path
emulate sh -c '. "$HOME/.shrc"'
bindkey -e                       # emacs keys (zsh would pick vi keys because EDITOR=nvim)

setopt AUTO_CD INTERACTIVE_COMMENTS
setopt SHARE_HISTORY HIST_IGNORE_ALL_DUPS HIST_IGNORE_SPACE HIST_REDUCE_BLANKS
HISTFILE=${ZDOTDIR:-$HOME}/.zsh_history HISTSIZE=50000 SAVEHIST=50000

_c=${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles
[[ -d $_c ]] || mkdir -p $_c

# completion (+ Homebrew's): the full check (new completions, insecure directories) once a
# day, otherwise the cached dump as is; the dump is compiled (zcompile) so it loads faster.
# The first Homebrew found wins: on macOS /home is an automount, looking there costs ~20 ms.
_hb=   # the Homebrew prefix, reused for the plugins below
for _b in /opt/homebrew /home/linuxbrew/.linuxbrew; do
	[[ -d $_b/share/zsh/site-functions ]] && { _hb=$_b; fpath=($_b/share/zsh/site-functions $fpath); break; }
done
autoload -Uz compinit
_f=($_c/zcompdump(N.mh-24))
# compinit rewrites the dump only when something changed: touch it, or every shell after the first day would run the
# full check (~10 ms) instead of once a day
if (( $#_f )); then compinit -C -d $_c/zcompdump; else compinit -d $_c/zcompdump; touch $_c/zcompdump; fi
[[ $_c/zcompdump.zwc -nt $_c/zcompdump ]] || zcompile $_c/zcompdump
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'   # case-insensitive
zstyle ':completion:*' menu select

# tool init scripts cached and compiled; regenerated only when the tool is updated (as in
# config.fish). `source` picks the compiled .zwc when it is newer than the script.
_dotfiles_init() {   # <cache name> <command...>
	local f=$_c/$1.zsh bin=${commands[$2]}
	[[ -n $bin ]] || return 0
	[[ -s $f && ! $bin -nt $f ]] || { "${@:2}" >|$f && zcompile $f; }
	source $f
}
_dotfiles_init fzf fzf --zsh             # Ctrl-R history, Ctrl-T files, Alt-C dirs
_dotfiles_init zoxide zoxide init zsh    # z <part of a path>
unfunction _dotfiles_init
unset _b _c _f

# fish's abbreviations (ls, ll, v, g come from ~/.shrc)
alias la='eza -la --git --group-directories-first' cat='bat --paging=never'

# fish-like typing. Up/Down search the history for what is already typed (built in). When the packages are
# installed: grey suggestions from history as you type (zsh-autosuggestions; Right arrow or End accepts) and command
# colouring (zsh-syntax-highlighting, loaded last, at the end of this file, as it requires). Looked for in Homebrew,
# /usr/share/zsh/plugins (Arch, Alpine) and /usr/share (Debian, Fedora) with plain file tests.
autoload -Uz up-line-or-beginning-search down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
bindkey '^[[A' up-line-or-beginning-search
bindkey '^[OA' up-line-or-beginning-search
bindkey '^[[B' down-line-or-beginning-search
bindkey '^[OB' down-line-or-beginning-search
_zp=(${_hb:+$_hb/share} /usr/share/zsh/plugins /usr/share)
for _d in $_zp; do
	[[ -r $_d/zsh-autosuggestions/zsh-autosuggestions.zsh ]] || continue
	ZSH_AUTOSUGGEST_STRATEGY=(history)      # history only: the fast strategy, like fish's
	ZSH_AUTOSUGGEST_MANUAL_REBIND=1         # no re-wrapping of widgets at every prompt
	ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=40      # no suggestions for long pasted lines
	source $_d/zsh-autosuggestions/zsh-autosuggestions.zsh
	break
done

# prompt: the fish prompt's look. The repo is found with builtins (no process outside a
# repo); one `git status` inside gives branch + file states.
_dotfiles_prompt() {
	local st=$? d=$PWD g='' s='' branch
	while [[ ! -e $d/.git ]]; do
		if [[ $d == / ]]; then d=''; break; fi
		d=${d:h}
	done
	if [[ -n $d ]]; then
		local -a lines files
		lines=("${(@f)$(command git --no-optional-locks status --porcelain --branch 2>/dev/null)}")
		branch=${${lines[1]#\#\# }#No commits yet on }
		branch=${${branch%%...*}% \[*\]}
		[[ $branch == 'HEAD (no branch)' ]] && branch=detached
		files=("${(@)lines[2,-1]}")
		(( ${files[(I)[MARC]*]} )) && s+='%F{green}✚'
		(( ${files[(I)?M*]} )) && s+='%F{green}✱'
		(( ${files[(I)(D|?D)*]} )) && s+='%F{red}✖'
		(( ${files[(I)R*]} )) && s+='%F{magenta}➜'
		(( ${files[(I)(U?|?U|AA|DD)*]} )) && s+='%F{yellow}═'
		(( ${files[(I)\?\?*]} )) && s+='%F{red}≠'
		[[ -n $s ]] || s='%F{green}:'
		g="%F{white}(git$s%B%F{blue}${branch//\%/%%}%b%F{white})"
	fi
	local mark='%B%F{green}✔'
	(( st == 0 )) || mark='%B%F{red}✘'
	PROMPT="%K{black}%B%F{white}❰%F{green}%n%F{white}❙%F{yellow}%~%b$g%B%F{white}❱$mark%F{white}≻%b%f%k "
}
precmd_functions+=(_dotfiles_prompt)

[[ -r $HOME/.config/zsh/local.zsh ]] && source $HOME/.config/zsh/local.zsh

# command colouring last: it wraps every widget defined before it
for _d in $_zp; do
	[[ -r $_d/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] || continue
	source $_d/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
	break
done
unset _d _zp _hb
true
