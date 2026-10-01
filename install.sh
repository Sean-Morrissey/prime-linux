#!/usr/bin/env bash
# Prime Linux installer — turns a CachyOS (or Arch) install into Prime Linux.
#
#   bash install.sh              install for the current user
#   bash install.sh --dry-run    say what would happen, change nothing
#   bash install.sh --no-packages   skip pacman (tests, or packages already in place)
#
# Run it as your normal user (it asks for your password once, for packages).
# Safe to re-run: it skips what is already done, and anything of yours it
# replaces is copied to ~/.config-backups/prime-install-<time>/ first.
# Undo it all with: prime-uninstall
set -euo pipefail

PRIME_HOME="$HOME/.local/share/prime-linux"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
INSTALL_CONF="$HOME/.config/prime/install.conf"
RUN_BACKUP="$HOME/.config-backups/prime-install-$STAMP"
# A re-run keeps the first install's backup folder: it holds the originals prime-uninstall puts back.
BACKUP="$(sed -n 's/^BACKUP=//p' "$INSTALL_CONF" 2>/dev/null || true)"
[ -n "$BACKUP" ] && [ -d "$BACKUP" ] || BACKUP="$RUN_BACKUP"
DRY=0; PKGS=1
for a in "$@"; do
    case "$a" in
        --dry-run)     DRY=1 ;;
        --no-packages) PKGS=0 ;;
        -h|--help)     sed -n '2,11p' "$0"; exit 0 ;;
        *) echo "unknown option: $a" >&2; exit 2 ;;
    esac
done

A=$'\e[38;2;248;113;113m'; D=$'\e[2m'; B=$'\e[1m'; R=$'\e[0m'
step() { printf '\n%s==>%s %s%s%s\n' "$A" "$R" "$B" "$*" "$R"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '    %s!%s %s\n' "$A" "$R" "$*"; }
run()  { if [ $DRY = 1 ]; then printf '    %s[dry-run]%s %s\n' "$D" "$R" "$*"; else "$@"; fi; }

# ── preflight ────────────────────────────────────────────────────────────────
[ "$(id -u)" -ne 0 ] || { echo "Run this as your normal user, not root (it uses sudo when it needs to)." >&2; exit 1; }
[ -n "${HOME:-}" ] && [ "$HOME" != / ] || { echo "HOME is not set." >&2; exit 1; }
command -v pacman >/dev/null || { echo "Prime Linux needs CachyOS or Arch Linux (pacman not found)." >&2; exit 1; }

printf '\n  %s%sPrime Linux%s installer\n' "$B" "$A" "$R"
. /etc/os-release 2>/dev/null || true
case "${ID:-}" in
    cachyos) info "Base: CachyOS ✓" ;;
    arch)    info "Base: Arch Linux — works, but CachyOS is what Prime Linux is tested on" ;;
    *)       warn "Base: ${PRETTY_NAME:-unknown} — only CachyOS and Arch are supported" ;;
esac
if [ "$(findmnt -no FSTYPE / 2>/dev/null)" = btrfs ]; then info "Disk: btrfs ✓ (system snapshots possible)"
else warn "Disk: not btrfs — system updates can't be rolled back from the boot menu"; fi
[ $DRY = 1 ] && info "Dry run: nothing will be changed."

# ── 1. packages ──────────────────────────────────────────────────────────────
if [ $PKGS = 1 ]; then
    step "Installing packages (asks for your password once)"
    mapfile -t pkgs < <(grep -vE '^\s*(#|$)' "$SRC/os/arch/packages.txt")
    missing=()
    for p in "${pkgs[@]}"; do pacman -Qq "$p" >/dev/null 2>&1 || pacman -Qqg "$p" >/dev/null 2>&1 || missing+=("$p"); done
    if [ ${#missing[@]} -eq 0 ]; then info "All ${#pkgs[@]} packages already installed"
    else info "${#missing[@]} to install: ${missing[*]}"; run sudo pacman -S --needed --noconfirm "${missing[@]}"; fi
fi

# ── 2. put Prime Linux in place (~/.local/share/prime-linux) ─────────────────
step "Installing Prime Linux into $PRIME_HOME"
if [ "$SRC" = "$PRIME_HOME" ]; then
    info "Already running from there"
else
    origin="$(git -C "$SRC" remote get-url origin 2>/dev/null || true)"
    branch="$(git -C "$SRC" symbolic-ref --short -q HEAD || echo main)"
    commit="$(git -C "$SRC" rev-parse HEAD)"
    if [ -d "$PRIME_HOME/.git" ]; then
        info "Updating the existing copy"
        run git -C "$PRIME_HOME" fetch --quiet "$SRC" "$commit"
    else
        run mkdir -p "$(dirname "$PRIME_HOME")"
        run git clone --quiet --no-checkout "$SRC" "$PRIME_HOME"
    fi
    run git -C "$PRIME_HOME" checkout --quiet -B "$branch" "$commit"
    # updates come from the published repo, not from wherever this ran
    [ -n "$origin" ] && run git -C "$PRIME_HOME" remote set-url origin "$origin"
fi
LAYER="$PRIME_HOME/layer"

# ── 3. your config files (seeded once; existing ones backed up first) ────────
step "Setting up your config files"
backup() {   # backup <file relative to ~/.config> [folder]: copy it aside before it is replaced
    local rel="$1" to="${2:-$BACKUP}"
    [ -e "$BACKUP/$rel" ] && to="$RUN_BACKUP"   # never overwrite the first copy, it's what prime-uninstall restores
    run mkdir -p "$to/$(dirname "$rel")"; run cp -a "$HOME/.config/$rel" "$to/$rel"
    # recorded straight away, so an interrupted run still leaves prime-uninstall a way back
    if [ "$to" = "$BACKUP" ] && [ $DRY = 0 ]; then
        mkdir -p "$(dirname "$INSTALL_CONF")"
        if grep -q '^BACKUP=' "$INSTALL_CONF" 2>/dev/null; then sed -i "s|^BACKUP=.*|BACKUP=$BACKUP|" "$INSTALL_CONF"
        else printf 'BACKUP=%s\n' "$BACKUP" >> "$INSTALL_CONF"; fi
    fi
    info "~/.config/$rel — yours backed up to $to, replaced"
}
seed() {   # seed <file relative to ~/.config>
    local rel="$1" dst="$HOME/.config/$1" src="$SRC/layer/seed/$1"
    if [ -f "$dst" ] && grep -q 'prime-linux' "$dst" 2>/dev/null; then info "~/.config/$rel — already Prime's, kept"; return; fi
    if [ -e "$dst" ]; then backup "$rel"; else info "~/.config/$rel — created"; fi
    run mkdir -p "$(dirname "$dst")"; run cp "$src" "$dst"
}
seed hypr/hyprland.conf
seed kitty/kitty.conf
for f in monitors.conf addons.conf; do
    [ -e "$HOME/.config/hypr/$f" ] || run bash -c "printf '# managed by Prime Linux (%s)\n' '$f' > '$HOME/.config/hypr/$f'"
done
[ -e "$HOME/.config/prime/addons" ] || run bash -c "mkdir -p '$HOME/.config/prime' && printf '# enabled add-ons, one per line — manage with: prime-addon\n' > '$HOME/.config/prime/addons'"

# hardware.conf: what this machine's GPU needs for video decode
gpu="$(lspci -nn 2>/dev/null | grep -iE 'vga|3d|display' || true)"
hw="${TMPDIR:-/tmp}/prime-hw.$$"
{
    echo "# Written by the Prime Linux installer for this machine ($(date +%F))."
    # by PCI vendor id: a name match finds "ati" in "Intel Corporation"
    if   grep -qi '\[10de:' <<<"$gpu"; then
        echo "env = LIBVA_DRIVER_NAME,nvidia"
        echo "env = __GLX_VENDOR_LIBRARY_NAME,nvidia"
        echo "env = NVD_BACKEND,direct"
        echo "cursor {"; echo "    no_hardware_cursors = true"; echo "}"
    elif grep -qi '\[1002:' <<<"$gpu"; then
        echo "env = LIBVA_DRIVER_NAME,radeonsi"
    elif grep -qi '\[8086:' <<<"$gpu"; then
        echo "env = LIBVA_DRIVER_NAME,iHD"
    fi
} > "$hw"
info "GPU: $(sed -E 's/^[^:]*: //' <<<"$gpu" | head -1 | cut -c1-70)"
if [ ! -e "$HOME/.config/hypr/hardware.conf" ]; then run cp "$hw" "$HOME/.config/hypr/hardware.conf"
elif cmp -s <(tail -n +2 "$hw") <(tail -n +2 "$HOME/.config/hypr/hardware.conf"); then info "~/.config/hypr/hardware.conf — unchanged, kept"
else  # an edited copy of ours is not an original for prime-uninstall to put back
    if head -1 "$HOME/.config/hypr/hardware.conf" | grep -q '^# Written by the Prime Linux installer'; then backup hypr/hardware.conf "$RUN_BACKUP"
    else backup hypr/hardware.conf; fi
    run cp "$hw" "$HOME/.config/hypr/hardware.conf"; fi
rm -f "$hw"

# ── 4. theme ─────────────────────────────────────────────────────────────────
step "Applying the theme"
run "$LAYER/bin/prime-theme" --apply
run gsettings set org.gnome.desktop.interface gtk-theme adw-gtk3-dark
run gsettings set org.gnome.desktop.interface color-scheme prefer-dark
run gsettings set org.gnome.desktop.interface icon-theme Papirus-Dark
run gsettings set org.gnome.desktop.interface cursor-theme Breeze_Light
run gsettings set org.gnome.desktop.interface font-name 'Inter 10'
run gsettings set org.gnome.desktop.interface monospace-font-name 'JetBrainsMono Nerd Font 11'
run gsettings set org.cinnamon.desktop.default-applications.terminal exec kitty 2>/dev/null || true
info "Dark GTK + Qt, Papirus icons, Inter font, $(sed -n 's/^ACCENT=/accent #/p' "$HOME/.config/prime/theme.conf" 2>/dev/null)"

# ── 5. services, commands, default apps ──────────────────────────────────────
step "Services and commands"
run mkdir -p "$HOME/.config/systemd/user" "$HOME/.local/bin"
for u in "$LAYER"/systemd/*; do run ln -sfn "$u" "$HOME/.config/systemd/user/$(basename "$u")"; done
run systemctl --user daemon-reload 2>/dev/null || info "(user services load at next login)"
for c in prime-update prime-uninstall prime-addon prime-theme prime-doctor prime-about; do
    run ln -sfn "$LAYER/bin/$c" "$HOME/.local/bin/$c"
done
info "Commands in ~/.local/bin: prime-update, prime-addon, prime-doctor, prime-theme, prime-about, prime-uninstall"
# Prime's tools in the app list (Spotlight, App menu) with their icons
run mkdir -p "$HOME/.local/share/applications"
for d in "$LAYER"/applications/*.desktop; do
    run bash -c "sed 's|@LAYER@|$LAYER|g' '$d' > '$HOME/.local/share/applications/$(basename "$d")'"
done
run xdg-user-dirs-update
run mkdir -p "$HOME/Pictures/Screenshots" "$HOME/Pictures/Wallpapers"
run xdg-mime default nemo.desktop inode/directory
# the bar already shows the network; a second tray icon from nm-applet is noise
run mkdir -p "$HOME/.config/autostart"
run bash -c "printf '[Desktop Entry]\nType=Application\nName=nm-applet (hidden by Prime Linux)\nHidden=true\n' > '$HOME/.config/autostart/nm-applet.desktop'"

# ── 6. system pieces (backups before updates, app store, login screen) ──────
step "System pieces (sudo)"
run sudo install -Dm755 "$LAYER/system/libalpm/prime-desktop-backup-all" /usr/share/libalpm/scripts/prime-desktop-backup-all
run sudo install -Dm644 "$LAYER/system/zz-prime-desktop-backup.hook" /etc/pacman.d/hooks/zz-prime-desktop-backup.hook
info "Desktop settings are saved before every package update"
if command -v flatpak >/dev/null; then
    run sudo flatpak remote-add --if-not-exists --system flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    info "App Store: Flathub enabled"
fi
if ! systemctl is-enabled display-manager.service >/dev/null 2>&1; then
    if pacman -Qq sddm >/dev/null 2>&1; then run sudo systemctl enable sddm.service; info "Login screen: SDDM enabled"
    else warn "No login screen is enabled — start Hyprland from the console with: uwsm start hyprland.desktop"; fi
else info "Login screen: $(basename "$(readlink -f /etc/systemd/system/display-manager.service)" .service) ✓"; fi

# ── 7. window title bars (hyprpm builds hyprbars for this Hyprland) ──────────
step "Window title bars (downloads and builds a plugin — takes a minute)"
mkdir -p "$HOME/.cache"
if [ $DRY = 1 ]; then info "[dry-run] hyprpm update / add hyprland-plugins / enable hyprbars"
elif { hyprpm update && { hyprpm list 2>/dev/null | grep -q hyprbars || hyprpm add https://github.com/hyprwm/hyprland-plugins; } && hyprpm enable hyprbars; } >"$HOME/.cache/prime-hyprpm.log" 2>&1; then
    info "Title bars ready"
else
    warn "Couldn't build the title bars now (it needs internet) — prime-update will retry. Everything else works without them."
fi

# ── done ─────────────────────────────────────────────────────────────────────
[ $DRY = 1 ] || { mkdir -p "$HOME/.config/prime"; printf 'INSTALLED=%s\nVERSION=%s\nBACKUP=%s\n' "$(date +%F)" \
    "$(git -C "$PRIME_HOME" rev-parse --short HEAD 2>/dev/null)" "$BACKUP" > "$HOME/.config/prime/install.conf"; }
printf '\n  %s%sPrime Linux is installed.%s\n\n' "$B" "$A" "$R"
info "Log out, pick ${B}Hyprland${R} on the login screen, and log in."
info "Then:  Super+Space search · Super+Alt+Space menu · Super+/ every shortcut"
[ -d "$BACKUP" ] && info "Your previous configs are in $BACKUP"
[ "$RUN_BACKUP" != "$BACKUP" ] && [ -d "$RUN_BACKUP" ] && info "Files replaced on this run are in $RUN_BACKUP"
echo
