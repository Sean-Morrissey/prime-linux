# Prime coding pack — terminal niceties for zsh (sourced from ~/.zshrc while the pack
# is on; `prime-addon disable coding` removes that line). PRIME_PROMPT=0 keeps your prompt.
[[ -o interactive ]] || return 0
(( $+commands[mise] ))     && eval "$(mise activate zsh)"
(( $+commands[zoxide] ))   && eval "$(zoxide init zsh)"
(( $+commands[fzf] ))      && eval "$(fzf --zsh 2>/dev/null)"
(( $+commands[starship] )) && [[ "${PRIME_PROMPT:-1}" != 0 ]] && eval "$(starship init zsh)"
if (( $+commands[eza] )); then
    alias ll='eza -l --icons --git --group-directories-first'
    alias la='eza -la --icons --git --group-directories-first'
    alias tree='eza --tree --icons --git-ignore'
fi
alias lg='lazygit'
