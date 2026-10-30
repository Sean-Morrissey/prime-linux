# Prime coding pack — terminal niceties for fish (loaded by
# ~/.config/fish/conf.d/prime-coding.fish while the pack is on). PRIME_PROMPT=0 keeps your prompt.
status is-interactive; or exit 0
type -q mise;   and mise activate fish | source
type -q zoxide; and zoxide init fish | source
type -q fzf;    and fzf --fish 2>/dev/null | source
if type -q starship; and test "$PRIME_PROMPT" != 0
    starship init fish | source
end
if type -q eza
    alias ll 'eza -l --icons --git --group-directories-first'
    alias la 'eza -la --icons --git --group-directories-first'
    alias tree 'eza --tree --icons --git-ignore'
end
alias lg lazygit
