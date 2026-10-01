#!/usr/bin/env bash
# Prime Linux installer — turns a CachyOS (or Arch) install into Prime Linux.
#
#   bash install.sh                 install for the current user
#   bash install.sh --dry-run       say exactly what would happen, change nothing
#   bash install.sh --fresh         redo every step (default: an unfinished
#                                   install picks up where it stopped)
#   bash install.sh --yes           don't stop to ask anything (automation)
#   bash install.sh --no-packages   skip pacman (tests, or packages already in place)
#
# Run it as your normal user — it asks for your password once, for packages.
# Safe to re-run. Anything of yours it replaces is copied to
# ~/.config-backups/prime-install-<time>/ first, and everything it does is
# written down so `prime-uninstall` can put the computer back as it was.
# A full log goes to ~/.local/state/prime/logs/.
set -euo pipefail

PRIME_HOME="$HOME/.local/share/prime-linux"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/prime"
PROGRESS="$STATE_DIR/install.progress"   # which steps finished (resume)
MANIFEST="$STATE_DIR/install.manifest"   # what we changed (uninstall)
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$HOME/.config-backups/prime-install-$STAMP"
TOTAL=8
DRY=0; PKGS=1; FRESH=0; YES=0
for a in "$@"; do
    case "$a" in
        --dry-run)     DRY=1 ;;
        --no-packages) PKGS=0 ;;
        --fresh)       FRESH=1 ;;
        --yes|-y)      YES=1 ;;
        -h|--help)     sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $a (try --help)" >&2; exit 2 ;;
    esac
done

A=$'\e[38;2;248;113;113m'; D=$'\e[2m'; B=$'\e[1m'; G=$'\e[32m'; R=$'\e[0m'
[ -t 1 ] || { A=""; D=""; B=""; G=""; R=""; }
N=0
step() { N=$((N+1)); printf '\n%s[%d/%d]%s %s%s%s\n' "$A" "$N" "$TOTAL" "$R" "$B" "$*" "$R"; }
info() { printf '    %s\n' "$*"; }
ok()   { printf '    %s✓%s %s\n' "$G" "$R" "$*"; }
warn() { printf '    %s!%s %s\n' "$A" "$R" "$*"; }
die()  { printf '\n  %s✗ %s%s\n' "$A" "$*" "$R" >&2; [ -n "${LOG:-}" ] && printf '    The full log is %s\n' "$LOG" >&2; exit 1; }
run()  { if [ $DRY = 1 ]; then printf '    %s[dry-run]%s %s\n' "$D" "$R" "$*"; else "$@"; fi; }
note() { [ $DRY = 1 ] || printf '%s\n' "$*" >> "$MANIFEST"; }   # remember a change for prime-uninstall
done_step() { [ $DRY = 1 ] || echo "step $1" >> "$PROGRESS"; }
skip_step() { [ "$RESUME" = 1 ] && grep -qx "step $1" "$PROGRESS" 2>/dev/null; }
ask_yes() {   # ask_yes "question" → 0 for yes; --yes and dry runs answer yes
    [ $YES = 1 ] || [ $DRY = 1 ] && return 0
    local ans; read -rp "    $1 [Y/n] " ans </dev/tty || return 0; [ -z "$ans" ] || [ "${ans,,}" = y ] || [ "${ans,,}" = yes ]
}

# ── preflight ────────────────────────────────────────────────────────────────
[ "$(id -u)" -ne 0 ] || { echo "Run this as your normal user, not root (it uses sudo when it needs to)." >&2; exit 1; }
[ -n "${HOME:-}" ] && [ "$HOME" != / ] && [ -d "$HOME" ] || { echo "HOME is not set." >&2; exit 1; }
command -v pacman >/dev/null || { echo "Prime Linux needs CachyOS or Arch Linux (pacman not found)." >&2; exit 1; }

# a finished install is redone in full (that's an update/repair); an unfinished one resumes
RESUME=0
if [ $FRESH = 0 ] && [ -f "$PROGRESS" ] && ! grep -qx complete "$PROGRESS"; then
    RESUME=1
    prev="$(sed -n 's/^backup //p' "$PROGRESS" | tail -1)"; [ -n "$prev" ] && BACKUP="$prev"
fi
LOG=""
if [ $DRY = 0 ]; then
    mkdir -p "$STATE_DIR/logs"
    LOG="$STATE_DIR/logs/install-$STAMP.log"
    exec > >(tee -a "$LOG") 2>&1
    if [ $RESUME = 0 ]; then printf 'started %s\nbackup %s\n' "$STAMP" "$BACKUP" > "$PROGRESS"; fi
    printf '# %s install run (%s)\n' "$STAMP" "$(git -C "$SRC" rev-parse --short HEAD 2>/dev/null || echo unknown)" >> "$MANIFEST"
fi

printf '\n  %s%sPrime Linux%s installer\n' "$B" "$A" "$R"
[ $DRY = 1 ] && info "${B}Dry run${R}: this shows what would happen and changes nothing."
[ $RESUME = 1 ] && info "Picking up an unfinished install (steps already done are skipped — --fresh redoes them)."
[ -n "$LOG" ] && info "${D}Log: $LOG${R}"

. /etc/os-release 2>/dev/null || true
case "${ID:-}" in
    cachyos) ok "Base: CachyOS" ;;
    arch)    info "Base: Arch Linux — works, but CachyOS is what Prime Linux is tested on" ;;
    *)       warn "Base: ${PRETTY_NAME:-unknown} — only CachyOS and Arch are supported"
             ask_yes "Carry on anyway?" || exit 1 ;;
esac

# which desktop(s) this CachyOS edition came with — they stay on the login screen
sessions="$(ls /usr/share/wayland-sessions/*.desktop /usr/share/xsessions/*.desktop 2>/dev/null | xargs -rn1 basename 2>/dev/null | sed 's/\.desktop$//' | sort -u || true)"
have_desktops=()
grep -qE '^plasma' <<<"$sessions" && have_desktops+=("KDE Plasma")
grep -qE '^gnome' <<<"$sessions" && have_desktops+=("GNOME")
grep -qE '^cosmic' <<<"$sessions" && have_desktops+=("COSMIC")
grep -qE '^xfce' <<<"$sessions" && have_desktops+=("Xfce")
grep -qE '^cinnamon' <<<"$sessions" && have_desktops+=("Cinnamon")
grep -qE '^(budgie|lxqt|mate|i3|sway|niri|wayfire|qtile|bspwm|openbox|lxde)' <<<"$sessions" && have_desktops+=("$(grep -m1 -oE '^(budgie|lxqt|mate|i3|sway|niri|wayfire|qtile|bspwm|openbox|lxde)' <<<"$sessions")")
desk_list="$(printf '%s, ' "${have_desktops[@]}")"; desk_list="${desk_list%, }"
dm=""; [ -L /etc/systemd/system/display-manager.service ] && dm="$(basename "$(readlink -f /etc/systemd/system/display-manager.service)" .service)"
if [ ${#have_desktops[@]} -gt 0 ]; then
    ok "Desktop already here: $desk_list — it stays; pick it or Hyprland on the login screen"
elif grep -qE '^hyprland' <<<"$sessions" && [ -f "$HOME/.config/hypr/hyprland.conf" ]; then
    info "Hyprland is already set up (CachyOS Hyprland edition?) — your config is backed up, then replaced"
else
    info "No desktop yet (CLI install) — Prime brings everything it needs"
fi
[ -n "$dm" ] && ok "Login screen: $dm" || info "Login screen: none yet — Prime will set one up (SDDM)"

if [ "$(findmnt -no FSTYPE / 2>/dev/null)" = btrfs ]; then ok "Disk: btrfs (system snapshots possible)"
else warn "Disk: not btrfs — system updates can't be rolled back from the boot menu"; fi

# packages: what's missing decides whether we need internet and room
missing=()
if [ $PKGS = 1 ]; then mapfile -t missing < <(bash "$SRC/layer/bin/prime-missing-packages" "$SRC/os/arch/packages.txt"); fi
free_root=$(( $(df -Pk / | awk 'NR==2 {print $4}') / 1024 ))
free_home=$(( $(df -Pk "$HOME" | awk 'NR==2 {print $4}') / 1024 ))
need_root=$(( ${#missing[@]} > 0 ? 4096 : 200 ))
[ "$free_root" -ge "$need_root" ] || die "Not enough free disk space: ${free_root} MB free on /, Prime needs about $((need_root/1024+1)) GB. Free some space and run this again."
[ "$free_home" -ge 300 ] || die "Not enough free space in your home folder (${free_home} MB). Prime needs about 300 MB."
ok "Disk space: $((free_root/1024)) GB free"

online=1
curl -fsS --max-time 8 -o /dev/null https://cachyos.org 2>/dev/null \
  || curl -fsS --max-time 8 -o /dev/null https://archlinux.org 2>/dev/null || online=0
if [ $online = 1 ]; then ok "Internet: connected"
elif [ ${#missing[@]} -gt 0 ]; then die "No internet connection — Prime needs to download ${#missing[@]} packages. Connect (Wi-Fi: run 'nmtui') and run this again."
else warn "No internet — carrying on (everything needed is installed; window title bars will wait)"; fi

if [ ${#missing[@]} -gt 0 ] || [ $DRY = 0 ]; then
    command -v sudo >/dev/null || die "sudo is missing — install it as root first: pacman -S sudo"
fi
if [ -e /var/lib/pacman/db.lck ]; then
    if pgrep -x pacman >/dev/null || pgrep -f 'paru|yay|pamac|octopi' >/dev/null; then
        die "Another install or update is running. Let it finish, then run this again."
    fi
    die "pacman is locked (/var/lib/pacman/db.lck) but nothing is running — probably an interrupted update. Remove the lock with: sudo rm /var/lib/pacman/db.lck — then run this again."
fi

# ask for the password once, and keep sudo awake for the rest of the run
if [ $DRY = 0 ]; then
    info "Prime needs your password once (for packages and system settings)."
    sudo -v || die "sudo didn't accept the password."
    ( while kill -0 $$ 2>/dev/null; do sudo -n true 2>/dev/null; sleep 50; done ) &
    KEEPALIVE=$!
    trap 'kill $KEEPALIVE 2>/dev/null; if ! grep -qx complete "$PROGRESS" 2>/dev/null; then printf "\n  %sThe install stopped before the end.%s Run the same command again — it carries on from where it stopped.\n  Log: %s\n\n" "$A" "$R" "$LOG"; fi' EXIT
fi

# ── 1. packages ──────────────────────────────────────────────────────────────
step "Packages"
if skip_step 1; then info "done earlier"
elif [ $PKGS = 0 ]; then info "skipped (--no-packages)"; done_step 1
else
    if [ ${#missing[@]} -eq 0 ]; then ok "All of Prime's packages are already installed"
    else
        info "${#missing[@]} to install: ${missing[*]}"
        info "(this also brings the rest of the system up to date — a few minutes on a fresh install)"
        if [ $DRY = 0 ]; then
            # packages installed now are listed, so prime-uninstall --packages can take exactly these away
            sudo pacman -Syu --needed --noconfirm "${missing[@]}" \
                || die "Installing packages failed (see the messages above). Fix that, then run this again — it carries on from here."
            for p in "${missing[@]}"; do pacman -Qq "$p" >/dev/null 2>&1 && note "pkg $p"; done
        else run sudo pacman -Syu --needed --noconfirm "${missing[@]}"; fi
        ok "Packages installed"
    fi
    done_step 1
fi

# ── 2. put Prime Linux in place (~/.local/share/prime-linux) ─────────────────
step "Installing Prime Linux into ${PRIME_HOME/#$HOME/\~}"
if [ "$SRC" = "$PRIME_HOME" ]; then
    ok "Already running from there"
else
    origin="$(git -C "$SRC" remote get-url origin 2>/dev/null || true)"
    branch="$(git -C "$SRC" symbolic-ref --short -q HEAD || echo main)"
    commit="$(git -C "$SRC" rev-parse HEAD)"
    if [ -d "$PRIME_HOME/.git" ]; then
        info "Updating the existing copy"
        run git -C "$PRIME_HOME" fetch --quiet "$SRC" "$commit"
    else
        [ -e "$PRIME_HOME" ] && { run mv "$PRIME_HOME" "$PRIME_HOME.old-$STAMP"; warn "an old non-git copy was moved to $PRIME_HOME.old-$STAMP"; }
        run mkdir -p "$(dirname "$PRIME_HOME")"
        run git clone --quiet --no-checkout "$SRC" "$PRIME_HOME"
    fi
    run git -C "$PRIME_HOME" checkout --quiet -B "$branch" "$commit"
    # updates come from the published repo, not from wherever this ran
    [ -n "$origin" ] && run git -C "$PRIME_HOME" remote set-url origin "$origin"
    ok "Prime Linux $(git -C "$SRC" describe --tags --always 2>/dev/null)"
fi
LAYER="$PRIME_HOME/layer"; [ $DRY = 1 ] && [ ! -d "$LAYER" ] && LAYER="$SRC/layer"
done_step 2

# ── 3. your config files (seeded once; existing ones backed up first) ────────
step "Your config files"
backup() {   # backup <path relative to ~/.config> — copy it into this install's backup
    local rel="$1"
    run mkdir -p "$BACKUP/$(dirname "$rel")"; run cp -a "$HOME/.config/$rel" "$BACKUP/$rel"
    grep -qxF "backup $BACKUP" "$MANIFEST" 2>/dev/null || note "backup $BACKUP"
    note "replaced $HOME/.config/$rel"
}
seed() {     # seed <file relative to ~/.config>
    local rel="$1" dst="$HOME/.config/$1" src="$SRC/layer/seed/$1"
    if [ -f "$dst" ] && grep -q 'prime-linux' "$dst" 2>/dev/null; then info "~/.config/$rel — already Prime's, kept"; return; fi
    if [ -e "$dst" ]; then backup "$rel"; info "~/.config/$rel — yours backed up, replaced"
    else note "created $dst"; info "~/.config/$rel — created"; fi
    run mkdir -p "$(dirname "$dst")"; run cp "$src" "$dst"
}
retire() {   # retire <file relative to ~/.config> — something from before Prime that would override Prime
    local rel="$1" dst="$HOME/.config/$1"
    [ -e "$dst" ] && ! grep -q 'prime-linux' "$dst" 2>/dev/null || return 0
    backup "$rel"; run rm -f "$dst"; info "~/.config/$rel — from your old setup, backed up and moved aside"
}
create() {   # create <path> <content> — only if it isn't there yet
    [ -e "$1" ] && return 0
    note "created $1"
    if [ $DRY = 1 ]; then printf '    %s[dry-run]%s create %s\n' "$D" "$R" "${1/#$HOME/\~}"
    else mkdir -p "$(dirname "$1")"; printf '%s' "$2" > "$1"; fi
}
if skip_step 3; then info "done earlier"
else
    seed hypr/hyprland.conf
    seed kitty/kitty.conf
    retire waybar/config.jsonc      # a bar config from another setup would replace Prime's bar
    retire waybar/sidebar.jsonc
    create "$HOME/.config/hypr/monitors.conf" $'# Screens — Menu → Settings → Displays rewrites this file.\n'
    create "$HOME/.config/hypr/addons.conf"   $'# managed by Prime Linux (prime-addon)\n'
    create "$HOME/.config/prime/addons"       $'# enabled add-ons, one per line — manage with: prime-addon\n'
    # the keyboard layout chosen when CachyOS was installed, so typing works from the first login
    layout="$(localectl status 2>/dev/null | sed -n 's/^ *X11 Layout: *//p' | tr -d ' ' || true)"
    create "$HOME/.config/hypr/keyboard.conf" "$(printf '# Keyboard layouts — written by Settings → Keyboard layout (prime-keyboard).\n# Switch between them with Super+Ctrl+Space. You can edit this file too.\ninput {\n    kb_layout = %s\n}\n' "${layout:-us}")"
    info "Keyboard: ${layout:-us}"

    # hardware.conf: what this machine's GPU needs for video decode
    gpu="$(lspci -nn 2>/dev/null | grep -iE 'vga|3d|display' || true)"
    hw="# Written by the Prime Linux installer for this machine ($(date +%F)). Safe to delete."$'\n'
    if   grep -qi nvidia <<<"$gpu"; then
        hw+=$'env = LIBVA_DRIVER_NAME,nvidia\nenv = __GLX_VENDOR_LIBRARY_NAME,nvidia\nenv = NVD_BACKEND,direct\ncursor {\n    no_hardware_cursors = true\n}\n'
    elif grep -qiE 'amd|ati|radeon' <<<"$gpu"; then hw+=$'env = LIBVA_DRIVER_NAME,radeonsi\n'
    elif grep -qi intel <<<"$gpu"; then hw+=$'env = LIBVA_DRIVER_NAME,iHD\n'
    fi
    info "GPU: $(sed -E 's/^[^:]*: //' <<<"$gpu" | head -1 | cut -c1-70)"
    [ -e "$HOME/.config/hypr/hardware.conf" ] || note "created $HOME/.config/hypr/hardware.conf"
    if [ $DRY = 1 ]; then printf '    %s[dry-run]%s write ~/.config/hypr/hardware.conf\n' "$D" "$R"; else printf '%s' "$hw" > "$HOME/.config/hypr/hardware.conf"; fi
    done_step 3
fi

# ── 4. theme ─────────────────────────────────────────────────────────────────
step "Look and feel"
if skip_step 4; then info "done earlier"
else
    # remember the current look first, so prime-uninstall can put it back (it matters
    # when GNOME is installed too: it reads the same settings)
    if [ $DRY = 0 ] && command -v gsettings >/dev/null && ! grep -q '^gsetting ' "$MANIFEST" 2>/dev/null; then
        for k in gtk-theme color-scheme icon-theme cursor-theme font-name monospace-font-name accent-color; do
            v="$(gsettings get org.gnome.desktop.interface "$k" 2>/dev/null || true)"
            [ -n "$v" ] && note "gsetting org.gnome.desktop.interface $k $v"
        done
    fi
    if [ $DRY = 0 ] && ! grep -q '^mime ' "$MANIFEST" 2>/dev/null; then
        old_dir="$(xdg-mime query default inode/directory 2>/dev/null || true)"
        note "mime inode/directory ${old_dir:--}"
    fi
    run "$LAYER/bin/prime-theme" --apply
    gs() { run gsettings set org.gnome.desktop.interface "$1" "$2" 2>/dev/null || true; }
    gs gtk-theme adw-gtk3-dark; gs color-scheme prefer-dark; gs icon-theme Papirus-Dark
    gs cursor-theme Breeze_Light; gs font-name 'Inter 10'; gs monospace-font-name 'JetBrainsMono Nerd Font 11'
    run gsettings set org.cinnamon.desktop.default-applications.terminal exec kitty 2>/dev/null || true
    run xdg-mime default nemo.desktop inode/directory
    [ ${#have_desktops[@]} -gt 0 ] && info "(GTK apps in $desk_list may pick up the dark theme too — prime-uninstall puts it back)"
    ok "Dark theme, Papirus icons, Inter font, $(sed -n 's/^ACCENT=/accent #/p' "$HOME/.config/prime/theme.conf" 2>/dev/null)"
    done_step 4
fi

# ── 5. services, commands, app-list entries ──────────────────────────────────
step "Desktop services and commands"
if skip_step 5; then info "done earlier"
else
    run mkdir -p "$HOME/.config/systemd/user" "$HOME/.local/bin"
    for u in "$LAYER"/systemd/*; do run ln -sfn "$u" "$HOME/.config/systemd/user/$(basename "$u")"; done
    run systemctl --user daemon-reload 2>/dev/null || info "(user services load at next login)"
    for c in prime-update prime-uninstall prime-addon prime-theme prime-doctor prime-about prime-migrate prime-webapp \
             prime-security prime-update-policy prime-updates-settings prime-settings prime-welcome; do
        run ln -sfn "$LAYER/bin/$c" "$HOME/.local/bin/$c"
    done
    ok "Commands: prime-update, prime-doctor, prime-addon, prime-theme, prime-webapp, prime-about, prime-uninstall"
    run mkdir -p "$HOME/.local/share/applications"
    for d in "$LAYER"/applications/*.desktop; do
        [ -f "$d" ] || continue
        run bash -c "sed 's|@LAYER@|$LAYER|g' '$d' > '$HOME/.local/share/applications/$(basename "$d")'"
    done
    run xdg-user-dirs-update
    run mkdir -p "$HOME/Pictures/Screenshots" "$HOME/Pictures/Wallpapers" "$HOME/Videos/Recordings"
    # the bar already shows the network; a second tray icon from nm-applet is noise
    if [ -e "$HOME/.config/autostart/nm-applet.desktop" ] && ! grep -q 'hidden by Prime' "$HOME/.config/autostart/nm-applet.desktop"; then
        backup autostart/nm-applet.desktop
    elif [ ! -e "$HOME/.config/autostart/nm-applet.desktop" ]; then note "created $HOME/.config/autostart/nm-applet.desktop"; fi
    run mkdir -p "$HOME/.config/autostart"
    run bash -c "printf '[Desktop Entry]\nType=Application\nName=nm-applet (hidden by Prime Linux)\nHidden=true\nOnlyShowIn=Hyprland;\n' > '$HOME/.config/autostart/nm-applet.desktop'"
    ok "Bar, dock, clipboard history, volume popups and battery warnings start with the desktop"
    done_step 5
fi

# ── 6. system pieces (sudo) ──────────────────────────────────────────────────
step "System settings (login screen, Bluetooth, printing, backups)"
enable_svc() {   # enable_svc <unit> <what it is> — enable a system service if it isn't already
    systemctl cat "$1" >/dev/null 2>&1 || return 0
    if systemctl is-enabled "$1" >/dev/null 2>&1; then ok "$2: on"; return 0; fi
    if [ $DRY = 1 ]; then run sudo systemctl enable "$1"; else sudo systemctl enable "$1" >/dev/null 2>&1 && note "service $1"; fi
    run sudo systemctl start "$1" 2>/dev/null || true
    ok "$2: switched on"
}
if skip_step 6; then info "done earlier"
else
    # nightly updates, snapshot-before-update, desktop-settings backup hook,
    # firewall + safe defaults — root-owned copies in /usr/local/lib/prime-linux
    if run sudo bash "$LAYER/system/install-system.sh" install --user "$(id -un)" --policy "${PRIME_UPDATE_POLICY:-auto}"; then
        note "system install-system.sh"
        ok "Nightly updates (snapshot first, never reboots), backups before every update, firewall on"
    else
        warn "Couldn't set up nightly updates and the firewall — run prime-update later to retry"
    fi
    run "$LAYER/bin/prime-security" fix-permissions >/dev/null 2>&1 || true
    if command -v flatpak >/dev/null; then
        run sudo flatpak remote-add --if-not-exists --system flathub https://dl.flathub.org/repo/flathub.flatpakrepo
        ok "App Store: Flathub enabled"
    fi
    if [ -z "$dm" ] && ! systemctl is-enabled display-manager.service >/dev/null 2>&1; then
        if ! pacman -Qq sddm >/dev/null 2>&1; then
            info "Installing a login screen (SDDM)"
            run sudo pacman -S --needed --noconfirm sddm && note "pkg sddm"
        fi
        run sudo systemctl enable sddm.service && note "service sddm.service"
        ok "Login screen: SDDM (starts at the next boot)"
    fi
    enable_svc bluetooth.service "Bluetooth"
    enable_svc cups.socket "Printing"
    if pacman -Qq power-profiles-daemon >/dev/null 2>&1; then enable_svc power-profiles-daemon.service "Power modes"; fi
    done_step 6
fi

# ── 7. window title bars (hyprpm builds hyprbars for this Hyprland) ──────────
step "Window title bars (downloads Hyprland's build files — about a minute)"
# hyprpm can fetch the build files (needs sudo — we still have it) from anywhere, but it
# can only add the plugin inside a running Hyprland: prime-titlebars finishes that at
# the first login (layer/default/hypr/autostart.conf), in the background.
if skip_step 7; then info "done earlier"
elif [ $DRY = 1 ]; then info "[dry-run] hyprpm update   (the plugin itself is added at the first Hyprland login)"
elif [ $online = 0 ]; then warn "Skipped (no internet) — done at your first login instead"; done_step 7
else
    mkdir -p "$HOME/.cache"
    if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
        "$LAYER/bin/prime-titlebars" --rebuild >/dev/null 2>&1 && ok "Title bars ready" || warn "Title bars: not yet — retried at the next login"
    elif hyprpm update >"$HOME/.cache/prime-hyprpm.log" 2>&1 </dev/null; then
        ok "Build files ready — the title bars switch on at your first login"
    else
        warn "Couldn't prepare the title bars now (log: ~/.cache/prime-hyprpm.log) — retried at login. Everything else works without them."
    fi
    done_step 7
fi

# ── 8. finish ────────────────────────────────────────────────────────────────
step "Finishing"
# a new install already has the current layout: no migration needs to run for it
run "$LAYER/bin/prime-migrate" --mark-all
if [ $DRY = 0 ]; then
    mkdir -p "$HOME/.config/prime"
    printf 'INSTALLED=%s\nVERSION=%s\nBACKUP=%s\nMANIFEST=%s\n' "$(date +%F)" \
        "$(git -C "$PRIME_HOME" describe --tags --always 2>/dev/null)" "$BACKUP" "$MANIFEST" > "$HOME/.config/prime/install.conf"
    echo complete >> "$PROGRESS"
fi
ok "Done"

printf '\n  %s%sPrime Linux is installed.%s\n\n' "$B" "$A" "$R"
if [ -n "$dm" ]; then info "Log out, pick ${B}Hyprland${R} on the login screen ($dm: the session menu), and log in."
else info "Restart the computer, choose ${B}Hyprland${R} on the login screen, and log in."; fi
info "Then:  Super+Space search · Super+Alt+Space menu · Super+/ every shortcut"
[ -d "$BACKUP" ] && info "Your previous settings are saved in ${BACKUP/#$HOME/\~}"
info "Changed your mind? prime-uninstall puts everything back."
echo
