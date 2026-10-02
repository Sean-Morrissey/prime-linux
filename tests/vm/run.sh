#!/usr/bin/env bash
# Real-boot test: CachyOS in a VM → install.sh over SSH → boot into Prime →
# screenshot the desktop from inside the VM. Nothing touches this machine
# beyond files in tests/vm/.work/ (no sudo, no system changes), and every VM
# this starts is stopped before it returns.
#
#   tests/vm/run.sh fetch     download the newest CachyOS desktop ISO, verify its sha256
#   tests/vm/run.sh base      install a minimal CachyOS (no desktop) onto a fresh disk
#   tests/vm/run.sh prime     install Prime on a copy of that disk, reboot into Hyprland,
#                             check the session and take a screenshot (desktop.png)
#   tests/vm/run.sh all       fetch + base + prime
#   tests/vm/run.sh shell     boot the Prime disk with a window, to look around (you close it)
#   tests/vm/run.sh status | clean
#
# Needs: qemu-system-x86_64, OVMF (edk2-ovmf), bsdtar, curl, ssh. KVM if available.
# Settings: PRIME_VM_KB=de (keyboard layout the "installer" picks; default us),
#           PRIME_VM_MEM=8192, PRIME_VM_CPUS=4, PRIME_VM_GL=0 (no virgl → may not show Hyprland).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
WORK="$HERE/.work"
MIRROR="${PRIME_VM_MIRROR:-https://mirror.cachyos.org/ISO/desktop}"
BASE="$WORK/base.qcow2"; DISK="$WORK/prime.qcow2"
KEY="$WORK/id_ed25519"; PORT="${PRIME_VM_SSH_PORT:-2223}"
MEM="${PRIME_VM_MEM:-8192}"; CPUS="${PRIME_VM_CPUS:-4}"
mkdir -p "$WORK"

say()  { printf '\e[1m==>\e[0m %s\n' "$*"; }
die()  { printf '\e[31m✗\e[0m %s\n' "$*" >&2; exit 1; }
accel() { [ -w /dev/kvm ] && echo kvm || echo tcg; }
ovmf() {
    for c in /usr/share/edk2/x64/OVMF_CODE.4m.fd /usr/share/edk2-ovmf/x64/OVMF_CODE.fd /usr/share/OVMF/OVMF_CODE.fd \
             /usr/share/OVMF/OVMF_CODE_4M.fd; do   # Arch, Fedora, older Debian/Ubuntu, Ubuntu 24.04+
        [ -r "$c" ] && { echo "$c"; return; }
    done; die "no OVMF firmware (install edk2-ovmf)"
}
ovmf_vars() { local c v; c="$(ovmf)"; v="$(dirname "$c")/$(basename "$c" | sed 's/CODE/VARS/')"; [ -r "$v" ] || die "no OVMF vars ($v)"; echo "$v"; }
iso() { ls -1 "$WORK"/cachyos-desktop-linux-*.iso 2>/dev/null | sort | tail -1; }
ssh_vm() { ssh -q -i "$KEY" -p "$PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 alex@127.0.0.1 "$@"; }
scp_vm() { scp -q -i "$KEY" -P "$PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$@"; }
QPID=""
stop_vm() {   # never leave a VM behind: polite poweroff, then kill
    [ -n "$QPID" ] && kill -0 "$QPID" 2>/dev/null || return 0
    ssh_vm 'sudo systemctl poweroff' >/dev/null 2>&1 || true
    for _ in $(seq 60); do kill -0 "$QPID" 2>/dev/null || break; sleep 1; done
    kill "$QPID" 2>/dev/null; sleep 2; kill -9 "$QPID" 2>/dev/null; wait "$QPID" 2>/dev/null
    QPID=""
}
trap stop_vm EXIT INT TERM
wait_ssh() {  # wait_ssh <seconds>
    local t=0
    until ssh_vm true 2>/dev/null; do
        kill -0 "$QPID" 2>/dev/null || die "the VM stopped (serial log: $WORK/serial-*.log)"
        t=$((t+5)); [ $t -lt "$1" ] || die "no SSH after $1 s (serial log in $WORK)"; sleep 5
    done
}

cmd_fetch() {
    local latest name
    latest="$(curl -fsSL "$MIRROR/" | grep -oE 'href="[0-9]{6}/"' | grep -oE '[0-9]{6}' | sort -n | tail -1)"
    [ -n "$latest" ] || die "couldn't read the ISO list at $MIRROR"
    name="cachyos-desktop-linux-$latest.iso"
    say "newest CachyOS desktop ISO: $latest"
    curl -fsSL -o "$WORK/$name.sha256" "$MIRROR/$latest/$name.sha256" || die "no checksum published"
    if [ -f "$WORK/$name" ] && (cd "$WORK" && sha256sum -c --quiet "$name.sha256"); then say "already downloaded and verified"; return; fi
    say "downloading (~3 GB)…"
    curl -fL --progress-bar -C - -o "$WORK/$name" "$MIRROR/$latest/$name" || die "download failed"
    (cd "$WORK" && sha256sum -c "$name.sha256") || { rm -f "$WORK/$name"; die "checksum mismatch — deleted the download"; }
    ls "$WORK"/cachyos-desktop-linux-*.iso | grep -v "$name" | xargs -r rm -f || true   # nothing older: fine
}

cmd_base() {
    local i; i="$(iso)"; [ -n "$i" ] || die "no ISO — run: tests/vm/run.sh fetch"
    [ -f "$KEY" ] || ssh-keygen -q -t ed25519 -N '' -C prime-vm-test -f "$KEY"
    say "extracting the live kernel from $(basename "$i")"
    bsdtar -xf "$i" -C "$WORK" arch/boot/x86_64/vmlinuz-linux-cachyos arch/boot/x86_64/initramfs-linux-cachyos.img boot/syslinux/archiso_sys-linux.cfg
    local uuid; uuid="$(grep -m1 -oE 'archisosearchuuid=[^ ]+' "$WORK/boot/syslinux/archiso_sys-linux.cfg")"
    [ -n "$uuid" ] || die "couldn't find the ISO's archisosearchuuid"
    rm -f "$BASE"; qemu-img create -q -f qcow2 "$BASE" 40G
    cp "$(ovmf_vars)" "$WORK/vars-base.fd"
    # The live system's writable layer (archiso "cow_device") is a small ext4 disk we
    # prepare here: it already holds our install script and a unit that runs it at
    # boot, so no typing into the live session and no kernel-cmdline tricks.
    # fakeroot: the files must belong to root inside the VM. No sudo involved.
    local ov="$WORK/overlay"; rm -rf "$ov" "$WORK/overlay.img"
    local up="$ov/prime/upperdir"
    mkdir -p "$up/etc/systemd/system/multi-user.target.wants" "$up/root/prime" "$ov/prime/workdir"
    cp "$HERE/prime-vm-install.service" "$up/etc/systemd/system/"
    ln -s ../prime-vm-install.service "$up/etc/systemd/system/multi-user.target.wants/prime-vm-install.service"
    cp "$HERE/guest-install.sh" "$up/root/prime/guest-install.sh"
    echo "${PRIME_VM_KB:-us}" > "$up/root/prime/kb"
    cp "$KEY.pub" "$up/root/prime/pubkey"
    # and the test key for root, so a stuck install can be looked at: ssh -p 2224 root@127.0.0.1
    mkdir -p -m 700 "$up/root/.ssh"; cp "$KEY.pub" "$up/root/.ssh/authorized_keys"; chmod 600 "$up/root/.ssh/authorized_keys"
    truncate -s 8G "$WORK/overlay.img"
    fakeroot -- mkfs.ext4 -q -L PRIMECOW -d "$ov" "$WORK/overlay.img" || die "couldn't build the overlay disk"
    say "installing CachyOS into base.qcow2 (unattended; ~5-10 min; log: serial-base.log)"
    qemu-system-x86_64 -name prime-vm-base -accel "$(accel)" -machine q35 -cpu host -m "$MEM" -smp "$CPUS" \
        -drive "if=pflash,format=raw,readonly=on,file=$(ovmf)" -drive "if=pflash,format=raw,file=$WORK/vars-base.fd" \
        -drive "file=$BASE,if=virtio,format=qcow2" -drive "file=$WORK/overlay.img,if=virtio,format=raw" -cdrom "$i" \
        -kernel "$WORK/arch/boot/x86_64/vmlinuz-linux-cachyos" -initrd "$WORK/arch/boot/x86_64/initramfs-linux-cachyos.img" \
        -append "archisobasedir=arch $uuid cow_label=PRIMECOW cow_directory=prime cow_persistent=N copytoram=n console=ttyS0 systemd.unit=multi-user.target" \
        -netdev "user,id=n0,hostfwd=tcp:127.0.0.1:2224-:22" -device virtio-net-pci,netdev=n0 \
        -display none -serial "file:$WORK/serial-base.log" -no-reboot &
    QPID=$!
    local t=0
    while kill -0 "$QPID" 2>/dev/null; do sleep 10; t=$((t+10)); [ $t -lt 2400 ] || { kill "$QPID"; die "base install took over 40 min"; }; done
    QPID=""; rm -rf "$WORK/overlay" "$WORK/overlay.img"
    grep -q 'PRIME-VM-INSTALL: OK' "$WORK/serial-base.log" || die "base install failed — see $WORK/serial-base.log"
    say "base CachyOS installed ✓ ($(du -h "$BASE" | cut -f1))"
}

boot_disk() {   # boot_disk <log name> [extra qemu args…] — background, SSH on $PORT
    local log="$1"; shift
    local gpu=(-device virtio-vga -display none)
    [ "${PRIME_VM_GL:-1}" = 1 ] && gpu=(-device virtio-vga-gl -display egl-headless)
    [ "${PRIME_VM_WINDOW:-0}" = 1 ] && gpu=(-device virtio-vga-gl -display gtk,gl=on)
    qemu-system-x86_64 -name prime-vm -accel "$(accel)" -machine q35 -cpu host -m "$MEM" -smp "$CPUS" \
        -drive "if=pflash,format=raw,readonly=on,file=$(ovmf)" -drive "if=pflash,format=raw,file=$WORK/vars-prime.fd" \
        -drive "file=$DISK,if=virtio,format=qcow2" \
        -netdev "user,id=n0,hostfwd=tcp:127.0.0.1:$PORT-:22" -device virtio-net-pci,netdev=n0 \
        -device qemu-xhci -device usb-tablet "${gpu[@]}" \
        -serial "file:$WORK/serial-$log.log" "$@" &
    QPID=$!
}

cmd_prime() {
    [ -f "$BASE" ] || die "no base disk — run: tests/vm/run.sh base"
    say "fresh copy of the base disk"
    rm -f "$DISK"; qemu-img create -q -f qcow2 -b "$BASE" -F qcow2 "$DISK"
    cp "$WORK/vars-base.fd" "$WORK/vars-prime.fd"
    boot_disk prime1; wait_ssh 300
    say "booted CachyOS: $(ssh_vm 'uname -r')"
    say "copying this checkout in (as boot.sh would clone it)"
    git -C "$REPO" bundle create "$WORK/prime.bundle" HEAD >/dev/null 2>&1 || die "git bundle failed"
    scp_vm "$WORK/prime.bundle" alex@127.0.0.1:/tmp/prime.bundle
    ssh_vm 'rm -rf ~/prime-linux && git --version >/dev/null 2>&1 || sudo pacman -S --needed --noconfirm git >/dev/null' || die "no git in VM"
    # README "private repo" steps, word for word, except that `gh repo clone
    # Sean-Morrissey/prime-linux` (which needs a GitHub login) is this bundle
    ssh_vm 'git clone -q /tmp/prime.bundle ~/prime-linux'
    say "running the README's install command in the VM (log: install.log)"
    ssh_vm 'bash ~/prime-linux/install.sh' > "$WORK/install.log" 2>&1
    local rc=$?; tail -12 "$WORK/install.log"
    [ $rc = 0 ] || die "install.sh failed in the VM (exit $rc) — see $WORK/install.log"
    ssh_vm 'cat ~/.cache/prime-hyprpm.log 2>/dev/null' > "$WORK/hyprpm.log"
    say "dry-run on the installed system must change nothing"
    ssh_vm 'h=$(mktemp -d); HOME=$h XDG_STATE_HOME= bash ~/.local/share/prime-linux/install.sh --dry-run >/dev/null; w=$(cd $h && find . -mindepth 1 | head -20); [ -z "$w" ] || { echo "$w" | sed "s/^/      wrote: /"; exit 1; }' \
        && echo "    ✓ dry run left nothing behind" || echo "    ✗ dry run wrote files (listed above)"
    # test VM only: log straight into the "Prime" session (what a person picks on the login screen)
    ssh_vm 'sudo mkdir -p /etc/sddm.conf.d && printf "[Autologin]\nUser=alex\nSession=prime\n" | sudo tee /etc/sddm.conf.d/zz-prime-vm-autologin.conf >/dev/null'
    say "rebooting into the desktop"
    stop_vm
    boot_disk prime2; wait_ssh 300
    local w="" t=0
    while [ $t -lt 120 ]; do
        w="$(ssh_vm 'ls /run/user/1000 2>/dev/null | grep -m1 "^wayland-[0-9]*$"')" && [ -n "$w" ] && break
        sleep 5; t=$((t+5))
    done
    if [ -z "$w" ]; then
        echo "    ✗ no Wayland session after 2 min (journal → $WORK/journal.log)"
        ssh_vm 'journalctl -b --no-pager | tail -300' > "$WORK/journal.log" 2>&1
        die "Hyprland didn't start in the VM"
    fi
    sleep 25   # let the bar, wallpaper and services settle
    local E="XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=$w HYPRLAND_INSTANCE_SIGNATURE=\$(ls /run/user/1000/hypr | head -1)"
    say "checking the live session"
    ssh_vm "$E; export XDG_RUNTIME_DIR WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE
        ck() { if ( eval \"\$2\" ) >/dev/null 2>&1; then echo \"    ✓ \$1\"; else echo \"    ✗ \$1\"; fi; }
        # retried: at first login Hyprland is busy loading the title-bar plugin for a few seconds
        ck 'Hyprland running'            'for i in \$(seq 15); do hyprctl -j version && exit 0; sleep 2; done; exit 1'
        ck 'config loaded with no errors' '[ \"\$(hyprctl -j configerrors | jq -r \".[]\" | grep -c .)\" = 0 ]'
        ck 'top bar + dock running'      '[ \$(pgrep -cx waybar) -ge 2 ]'
        ck 'prime-session.target active' 'systemctl --user is-active prime-session.target'
        ck 'volume popups (swayosd)'     'pgrep -x swayosd-server'
        ck 'notifications (swaync)'      'pgrep -x swaync'
        if [ ${PRIME_VM_GL:-1} = 1 ]; then ck 'wallpaper (hyprpaper)' 'pgrep -x hyprpaper'
        else echo '    · wallpaper (hyprpaper): not checked: it needs a GPU render node and this VM has none (software rendering)'; fi
        ck 'window title bars (built at first login)' 'for i in \$(seq 48); do hyprctl plugin list | grep -qi hyprbars && exit 0; sleep 5; done; exit 1'
        ck 'keyboard layout applied'     'hyprctl -j devices | jq -e \".keyboards[] | select(.main) | .layout\"'
        ck 'binds have descriptions'     '[ \$(hyprctl -j binds | jq \"[.[] | select(.has_description | not)] | length\") = 0 ]'
        ck 'login health check clean'    '~/.local/share/prime-linux/layer/bin/prime-doctor --login'
        grim /tmp/desktop.png" | tee "$WORK/session-checks.log"
    scp_vm alex@127.0.0.1:/tmp/desktop.png "$WORK/desktop.png" && say "screenshot: $WORK/desktop.png"
    say "opening what a friend sees first: bar, Start menu, Spotlight, Prime menu, terminal greeting"
    scp_vm "$HERE/desktop-checks.sh" alex@127.0.0.1:/tmp/desktop-checks.sh
    ssh_vm "$E; export XDG_RUNTIME_DIR WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE; bash /tmp/desktop-checks.sh" \
        | tee -a "$WORK/session-checks.log"
    for p in start-menu spotlight prime-menu terminal; do scp_vm "alex@127.0.0.1:/tmp/$p.png" "$WORK/$p.png" 2>/dev/null; done
    # an empty desktop is one flat colour in the middle; a wallpaper is thousands
    local colours; colours="$("$(command -v magick || echo convert)" "$WORK/desktop.png" -gravity center -crop 40%x40%+0+0 -format %k info: 2>/dev/null || echo 0)"
    if [ "${colours:-0}" -gt 200 ]; then echo "    ✓ wallpaper visible ($colours colours mid-screen)" | tee -a "$WORK/session-checks.log"
    else echo "    ✗ no wallpaper on screen ($colours colours mid-screen)" | tee -a "$WORK/session-checks.log"; fi
    say "uninstall in the VM, then check the account is back"
    ssh_vm 'bash ~/.local/share/prime-linux/layer/bin/prime-uninstall --yes' > "$WORK/uninstall.log" 2>&1 \
        && echo "    ✓ prime-uninstall ran (log: uninstall.log)" || echo "    ✗ prime-uninstall failed"
    # (a running Hyprland writes a stub hyprland.conf when its config disappears — not Prime's)
    left="$(ssh_vm 'grep -l prime-linux ~/.config/hypr/*.conf 2>/dev/null; ls -d ~/.local/share/prime-linux ~/.config/prime ~/.config/systemd/user/prime-* ~/.local/bin/prime-* ~/.local/share/applications/prime-* /etc/pacman.d/hooks/zz-prime-* 2>/dev/null')"
    if [ -z "$left" ]; then echo "    ✓ nothing of Prime left" | tee -a "$WORK/session-checks.log"
    else echo "    ✗ left behind: $(echo $left)" | tee -a "$WORK/session-checks.log"; fi
    stop_vm
    grep -q '✗' "$WORK/session-checks.log" && die "some checks failed (session-checks.log)"
    say "real-boot test passed"
}

cmd_shell() {
    [ -f "$DISK" ] || die "no Prime disk — run: tests/vm/run.sh prime"
    PRIME_VM_WINDOW=1 boot_disk shell
    say "VM window open — ssh: ssh -i $KEY -p $PORT alex@127.0.0.1 (password prime). Close the window to stop it."
    wait "$QPID"; QPID=""
}

cmd_status() {
    ls -lh "$WORK" 2>/dev/null | sed 1d | awk '{print "    " $5 "  " $9}'
    pgrep -af 'qemu-system-x86_64 -name prime-vm' && echo "    ^ running" || echo "    no test VM running"
}

case "${1:-}" in
    fetch) cmd_fetch ;;
    base)  cmd_base ;;
    prime) cmd_prime ;;
    all)   cmd_fetch && cmd_base && cmd_prime ;;
    shell) cmd_shell ;;
    status) cmd_status ;;
    clean) rm -rf "$WORK"; say "removed $WORK" ;;
    *) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
