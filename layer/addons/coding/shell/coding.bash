# Prime coding pack — terminal niceties for bash (sourced from ~/.bashrc while the pack
# is on; `prime-addon disable coding` removes that line). PRIME_PROMPT=0 keeps your prompt.
[[ $- == *i* ]] || return 0
command -v mise     >/dev/null && eval "$(mise activate bash)"          # language versions
command -v zoxide   >/dev/null && eval "$(zoxide init bash)"            # z <part of a folder name>
command -v fzf      >/dev/null && eval "$(fzf --bash 2>/dev/null)"      # Ctrl+R: search history
command -v starship >/dev/null && [ "${PRIME_PROMPT:-1}" != 0 ] && eval "$(starship init bash)"
if command -v eza >/dev/null; then
    alias ll='eza -l --icons --git --group-directories-first'
    alias la='eza -la --icons --git --group-directories-first'
    alias tree='eza --tree --icons --git-ignore'
fi
alias lg='lazygit'
