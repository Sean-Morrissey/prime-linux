#!/usr/bin/env bash
# GTK3 follows Text size; the title bars survive a mid-session Hyprland update;
# prime-notify is a command
#
# Three things that used to live only on the machine they were fixed on:
#   prime-text-sync.path      copies Text size into ~/.config/gtk-3.0/settings.ini
#                             whenever prime-theme rewrites the theme
#   prime-hyprpm-watch.timer  every 10 min, rebuilds hyprbars if Hyprland's commit
#                             moved (a no-op otherwise)
#   prime-notify              notifications with Open / Dismiss buttons, on the
#                             session's PATH (~/.local/bin via environment.d)
# The unit files are already linked by prime-update; this switches them on.
LAYER="${PRIME_LAYER:?}"
mkdir -p "$HOME/.local/bin" "$HOME/.config/environment.d"
for c in prime-notify prime-text-sync prime-hyprpm-doctor; do
    [ -x "$LAYER/bin/$c" ] && ln -sfn "$LAYER/bin/$c" "$HOME/.local/bin/$c"
done
ENVF="$HOME/.config/environment.d/60-prime-path.conf"
[ -e "$ENVF" ] || printf '# Prime Linux: its commands (prime-notify, prime-update, …) live here\nPATH=$HOME/.local/bin:${PATH}\n' > "$ENVF"
systemctl --user daemon-reload 2>/dev/null
for u in prime-text-sync.path prime-hyprpm-watch.timer; do
    systemctl --user enable --now "$u" >/dev/null 2>&1 || systemctl --user enable "$u" >/dev/null 2>&1 || true
done
"$LAYER/bin/prime-text-sync" >/dev/null 2>&1 || true
exit 0
