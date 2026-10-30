#!/usr/bin/env bash
# the terminal greeting's fastfetch config follows the new PRIME wordmark
#
# fastfetch's config is seeded once and then belongs to the person, so updates
# never touch it. But a copy that is still exactly one of Prime's earlier seeds
# (nobody edited it) was sized for the stacked P/R/I/M/E logo (16 columns): next
# to the wordmark (38 columns) the system details would print over the logo.
# Only those untouched copies are replaced; an edited one is left alone.
LAYER="${PRIME_LAYER:?}"
CONF="$HOME/.config/fastfetch/config.jsonc"
[ -f "$CONF" ] || exit 0
case "$(sha256sum "$CONF" | cut -d' ' -f1)" in
    580e21896e569c41a1ed40e9cca1731187b1854c9dba4cb3b8522fb04e09d33e|\
    14915742b0d47a1d53ec988ab6f05ecbd7608ede6fcc243891121d6ffc064693)
        install -m644 "$LAYER/seed/fastfetch/config.jsonc" "$CONF" ;;
esac
exit 0
