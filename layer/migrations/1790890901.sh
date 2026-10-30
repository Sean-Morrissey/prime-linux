#!/usr/bin/env bash
# the terminal greeting spells P.R.I.M.E (Please Relax I'll Manage Everything)
#
# Puts Prime's logo where fastfetch looks (~/.config/prime/prime-logo.txt, also
# done by every theme refresh) and gives fastfetch Prime's config — but only when
# there is none yet, or the one there is the earlier hand-made Prime greeting
# (it points at prime-logo.txt and isn't marked prime-linux). That one is backed
# up first. A fastfetch config of the person's own is left alone.
LAYER="${PRIME_LAYER:?}"
for t in prime-logo.txt prime-logo.plain.txt; do
    install -Dm644 "$LAYER/branding/terminal/$t" "$HOME/.config/prime/$t"
done
CONF="$HOME/.config/fastfetch/config.jsonc"
SEED="$LAYER/seed/fastfetch/config.jsonc"
if [ ! -e "$CONF" ]; then
    install -Dm644 "$SEED" "$CONF"
elif grep -q 'prime-logo' "$CONF" && ! grep -q 'prime-linux' "$CONF"; then
    BACKUP="$HOME/.config-backups/prime-migrate-$(date +%Y%m%d-%H%M%S)/fastfetch"
    mkdir -p "$BACKUP" && cp -a "$CONF" "$BACKUP/config.jsonc"
    install -m644 "$SEED" "$CONF"
fi
exit 0
