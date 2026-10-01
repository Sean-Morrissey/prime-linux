# Real-boot test — CachyOS in a VM, then Prime

`tests/install-in-container.sh` proves the install on a clean Arch account, but a
container never boots: no login screen, no Hyprland, no GPU, no systemd. This
directory boots the real thing. Everything lives in `tests/vm/.work/`
(git-ignored); nothing on the host is changed, and every VM is powered off (or
killed) before the script returns.

```bash
tests/vm/run.sh all      # = fetch + base + prime   (~20-30 min the first time)
tests/vm/run.sh status   # what's on disk / running
tests/vm/run.sh shell    # boot the Prime disk in a window to look around
tests/vm/run.sh clean    # delete .work/ (ISO, disks, logs)
```

## What each stage does

| Stage | How | Automated? |
|---|---|---|
| **fetch** | reads `mirror.cachyos.org/ISO/desktop/`, takes the newest dated folder, downloads the ISO and its published `.sha256`, verifies it (a mismatch deletes the download) | fully |
| **base** | boots the ISO's own kernel + initramfs headless with `systemd.unit=multi-user.target`; the live system's writable layer (archiso `cow_label=`) is a small ext4 disk built here without root (`fakeroot mkfs.ext4 -d`) that already contains `prime-vm-install.service` + `guest-install.sh`, so the live system runs the install by itself: GPT + btrfs (`@`, `@home`), `pacstrap` of `base linux-cachyos` from the ISO's CachyOS repos, systemd-boot, NetworkManager, sshd, user `alex`, the keyboard layout as the CachyOS installer would set it (`PRIME_VM_KB`). **No desktop, no login screen** — the hardest starting point for `install.sh`. The VM powers itself off. | fully |
| **prime** | copy-on-write copy of the base disk; boots it (UEFI/OVMF, KVM, virtio-gpu with virgl through `egl-headless`), SSH with a generated test key; ships this checkout as a git bundle (like `boot.sh` clones), runs `install.sh --yes`, checks `--dry-run` writes nothing, sets SDDM autologin into Hyprland (test VM only), reboots, waits for the Wayland socket, checks the live session (Hyprland, no config errors, both bars, prime-session.target, swayosd, swaync, hyprpaper, keyboard layout, every bind described, `prime-doctor --login`), takes a `grim` screenshot inside the VM → `.work/desktop.png`, then runs `prime-uninstall --yes` and checks Prime is gone | fully; a human looks at `desktop.png` |

What it does **not** cover: the CachyOS *graphical* installer (Calamares) and the
KDE/GNOME editions' preinstalled desktops. For a release, do one manual pass:
`run.sh fetch`, boot the ISO in a window
(`qemu-system-x86_64 -enable-kvm -m 8G -cdrom .work/cachyos-*.iso -bios /usr/share/edk2/x64/OVMF.4m.fd`),
install the KDE edition, run the README's one-liner, log into Hyprland, and
check that Plasma is still offered on the login screen.

## Logs

`.work/serial-base.log` (the unattended install, ends with `PRIME-VM-INSTALL: OK`),
`.work/install.log` (install.sh inside the VM), `.work/session-checks.log`,
`.work/uninstall.log`, `.work/journal.log` (only when the desktop didn't come up).

Test-only settings that never ship: the `alex`/`prime` account with
passwordless sudo, the SSH test key, and SDDM autologin.
