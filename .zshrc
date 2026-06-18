# Created by newuser for 5.8.1

[[ -f ~/.zsh_aliases ]] && source ~/.zsh_aliases # zsh specific (global and suffix aliases)
[[ -f ~/.aliases ]] && source ~/.aliases # for both bash and zsh
[[ -f ~/.functions ]] && source ~/.functions # for functions from mathiasbynens repo


# History settings
HISTFILE=~/.zsh_history
HISTSIZE=100000
SAVEHIST=100000
setopt SHARE_HISTORY          # share history across sessions
setopt HIST_IGNORE_DUPS       # don't record duplicates
setopt HIST_IGNORE_SPACE      # don't record commands starting with space

# other options
setopt nocaseglob # case insensitive globbing as it says on the tin
setopt incappendhistory # append commands to history immediately rather than on exit
setopt CORRECT # spell-correct commands (zsh has no cd-specific cdspell equivalent)
setopt autocd # type dir name to cd to it

# Emacs mode
bindkey -e
autoload -Uz edit-command-line
zle -N edit-command-line
bindkey '^X^E' edit-command-line     # emacs-style chord

# Better completion
autoload -Uz compinit && compinit
zstyle ':completion:*' menu select          # arrow-key menu
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'  # case-insensitive

# Plugins (order matters: syntax-highlighting must be last)
source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh
bindkey '^ ' forward-word           # Ctrl-Space goes forward

source ~/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# Prompt: starship if enabled & installed, else a lightweight manual prompt.
# Toggles are machine-local (set in ~/.zshenv, untracked -> no dotfiles diff):
#   STARSHIP_ENABLE=0  skip starship entirely; use the manual prompt below.
#   STARSHIP_NODE=0    keep starship but disable the slow shell-out modules
#                      (nodejs, package) via ~/.config/starship-lite.toml.
# Both default to on when unset. Benchmark with ./bench-prompt.zsh.
if [[ "${STARSHIP_ENABLE:-1}" == 1 ]] && command -v starship >/dev/null 2>&1; then
    if [[ "${STARSHIP_NODE:-1}" != 1 ]]; then
        export STARSHIP_CONFIG="$HOME/.config/starship-lite.toml"
    fi
    eval "$(starship init zsh)"
else
    # cwd, then a prompt char that turns red on a nonzero exit status.
    PROMPT='%F{cyan}%~%f %(?.%F{green}.%F{red})%#%f '
fi

export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_ALT_C_COMMAND='fd --type d --hidden --follow'

# fzf
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# Ctrl-G: ripgrep + fzf (fuzzy), open match in nvim at line + approx column
rg-fzf() {
  local rg_cmd='rg --line-number --no-heading --color=always --smart-case'

  local previewer
  if   command -v bat    >/dev/null; then previewer='bat'
  elif command -v batcat >/dev/null; then previewer='batcat'
  fi
  local preview="${previewer:+$previewer --color=always {1} --highlight-line {2}}"
  : "${preview:=cat {1}}"   # fallback if neither exists

  local out
  out=$(eval "$rg_cmd ''" | \
        fzf --ansi --delimiter=: --print-query \
            --preview "$preview" \
            --preview-window 'up,60%,border-bottom')

  local query=${out%%$'\n'*}
  local match=${out#*$'\n'}
  [[ -z $match || $match == $query ]] && return   # esc / no selection

  local file line text
  IFS=: read -r file line text <<< "$match"

  local col=1
  if [[ -n $query ]]; then
    local nee=${query[1]} hay=$text
    [[ $query == ${query:l} ]] && { hay=${text:l}; nee=${nee:l}; }   # smart-case
    local pre=${hay%%[$nee]*}
    [[ $pre != $hay ]] && col=$(( ${#pre} + 1 ))
  fi

  nvim "$file" "+call cursor($line, $col)" -c "normal! zz"
}
zle -N rg-fzf
bindkey '^[g' rg-fzf

# Lazy loading of node since normally it massively increases start times
export NVM_DIR="$HOME/.nvm"
nvm() {
  unset -f nvm node npm npx
  [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"
  [[ -s "$NVM_DIR/bash_completion" ]] && source "$NVM_DIR/bash_completion"
  nvm "$@"
}
node() { unset -f nvm node npm npx; source "$NVM_DIR/nvm.sh"; node "$@" }
npm()  { unset -f nvm node npm npx; source "$NVM_DIR/nvm.sh"; npm "$@" }
npx()  { unset -f nvm node npm npx; source "$NVM_DIR/nvm.sh"; npx "$@" }

# add to path
export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/bin:$PATH"

# nvim editor
export EDITOR='nvim'

# opencode
export PATH=/home/interrobang/.opencode/bin:$PATH

