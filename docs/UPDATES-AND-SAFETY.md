# Updates and safety

How Prime Linux keeps a CachyOS machine current without ever breaking it, how a
beginner undoes an update, and which safety defaults it sets. Status 2026-10-01.

## What the person sees

- **Nothing, most nights.** Updates install during *update hours* (03:00–06:00 by
  default), a safety snapshot first, a health check after. In the morning one
  notification: *"Updated while you were away — 212 update(s), all good."*
- **Prime menu → Update → Update settings** (`prime-updates-settings`): four choices
  in plain words — **Automatic (recommended)**, **Ask me first**, **Only security
  fixes**, **Off** — plus update hours, pause for a week, update now, undo.
- **Update everything** (`prime-update`): five numbered steps, every failure says
  what happened, whether anything changed, and what to do next.
- **Undo the last update** (`prime-update --undo`): where the safe copy is and the
  exact steps for *this* computer's boot menu. If the computer was started from a
  snapshot, it says so and offers to make it permanent.

## Pieces

| File (in `layer/`) | Installed to | Runs as |
|---|---|---|
| `system/updates/prime-system-update` | `/usr/local/lib/prime-linux/` | root (timer, or `sudo` from prime-update) |
| `system/updates/prime-system-update.{service,timer}` | `/etc/systemd/system/` | — |
| `system/updates/updates.conf` | `/etc/prime/updates.conf` (created once, kept) | read by the updater |
| `system/libalpm/prime-desktop-backup-all` + `system/zz-prime-desktop-backup.hook` | `/usr/share/libalpm/scripts/`, `/etc/pacman.d/hooks/` | root → each user via `runuser` |
| `system/security/90-prime-security.conf` | `/etc/sysctl.d/` | — |
| `bin/prime-security` | also copied to `/usr/local/lib/prime-linux/` | user (report), root (`apply`) |
| `system/install-system.sh` | — | root: `install / uninstall / status / needs-update` |
| `bin/prime-update`, `bin/prime-update-policy`, `bin/prime-updates-settings`, `bin/prime-doctor` | `~/.local/share/prime-linux` | user |

**Rule: nothing that runs as root lives in a home folder.** The timer and the pacman
hook run root-owned copies; `prime-update` re-copies them (with the person's
password) when the layer changes (`install-system.sh needs-update`).

## The update, step by step (`prime-system-update apply`)

1. **Ready?** pacman lock free (waits for another installer; removes a lock left by
   a crash only when no package tool is running), ≥ `MIN_FREE_GB` on `/`, ≥ 120 MB
   on the boot partition (a kernel that doesn't fit = a computer that doesn't start).
2. **Check:** `pacman -Sy`; mirror errors → `cachyos-rate-mirrors` (or reflector), retry.
3. **Keyring first:** `archlinux-keyring` / `cachyos-keyring` on their own, so the
   rest doesn't fail signature checks.
4. **Download everything** (`pacman -Suw`) **before installing anything** — a dropped
   connection can't leave a half-updated system. Failure → "nothing was changed".
5. **Snapshot** (`snapper -c root create`, labelled *Prime: before update*, important).
   Can't take one although the disk supports it → refuse.
6. **Install** from the cache (`pacman -Su`) under `systemd-inhibit` (no shutdown,
   sleep or lid-close). Runs in its own session with HUP/INT/PIPE ignored, so closing
   the window or Ctrl+C can't interrupt it. The service never SIGKILLs (`SendSIGKILL=no`).
   Stopped part-way → retried once; still stuck → *broken*, the person is told.
7. **System App Store apps** (`flatpak update --system`).
8. **Health:** `pacman -Dk`; every installed kernel has its `vmlinuz` + initramfs and
   mkinitcpio reported no error — otherwise rebuild (`mkinitcpio -P` /
   `limine-mkinitcpio` / dracut); services that failed *since the update* (not
   before) are restarted, then reported; new `.pacnew` files counted with advice;
   restart advice when the kernel (or systemd/glibc/mesa/Hyprland/firmware) changed.
9. **Report:** `/var/lib/prime-linux/updates/last-run.json` (readable by everyone, no
   secrets), `history.log`, the full pacman log of the run (newest 7 kept).

It **never reboots**. Rolling back a running Arch system in place is how machines get
bricked, so recovery is booting the snapshot (below), guided in plain words.

## The nightly decision (`cycle`, hourly timer)

Hourly and cheap: no network until all of these hold.
- policy not *off*, not paused, fewer than `FAIL_LIMIT` (2) failed runs in a row
  (then it waits for a person — `prime-update` or `clear-failure`);
- at most one real check per ~20 h;
- **inside update hours** and the person is away (`IDLE_MINUTES`, or screen locked);
  or **overdue** (`CATCH_UP_DAYS`, the computer is off at night) and the person is
  away; or overdue twice over (someone at it every night) — nothing restarts anyway;
- **no game or fullscreen window** (gamescope, wineserver, Steam games, a fullscreen
  Hyprland window); **power**: on AC, or battery ≥ `MIN_BATTERY`; not **metered**;
  no other package tool running; enough disk.

Policies: **auto** installs; **ask** sends one notification with *Install now* (opens
`prime-update`, the person consents with their password); **security** does a full
update only when `arch-audit` reports a fix waiting, at least every
`SECURITY_MAX_DAYS` (weekly without arch-audit) — Arch does not support partial
upgrades, so "security only" means *when*, not *which*; **off** does nothing.

**AUR packages are never installed unattended** — built from volunteer scripts no one
reviews (malware has been found there). The nightly run mentions waiting AUR updates
once; `prime-update` asks before running `paru -Sua`.

Notifications reach the desktop through the person's own session manager
(`systemd-run --user -M user@`). During quiet hours (22–08) only critical ones show;
the rest arrive as one summary at the next login (`prime-updates-settings
--login-summary`, called by `prime-doctor --login`).

## Undo

| Boot menu | Snapshots in the menu via | Prime checks | Making it permanent |
|---|---|---|---|
| Limine (CachyOS default) | `limine-snapper-sync` (snapper plugin) | package installed, service enabled | `sudo limine-snapper-restore` (offered by `prime-update --undo`) |
| GRUB | `grub-btrfs` + `grub-btrfsd` | service enabled, `grub-btrfs-overlayfs` hook | Btrfs Assistant → Snapper → Restore |
| systemd-boot / rEFInd | — (can't list snapshots) | says so | Btrfs Assistant from the running desktop |
| not btrfs | — | says updates can't be undone | desktop settings only (Restore desktop settings) |

The boot loader is read from the `LoaderInfo` EFI variable (works without root).
`prime-doctor` reports all of this and flags a computer started from a snapshot.

## Safety defaults (`prime-security`)

- **Firewall: ufw** — CachyOS ships it switched on, it has app profiles, one tool
  avoids two firewalls fighting. Incoming denied; allowed only from private ranges
  (10/8, 172.16/12, 192.168/16, fe80::/10, fd00::/8): mDNS (printers, casting), and
  when installed Steam Remote Play / local transfers, KDE Connect, LocalSend. Routed
  traffic is left as CachyOS set it (Docker/libvirt keep working). firewalld in charge
  → left alone.
- **sysctl** (`90-prime-security.conf`): no ICMP redirects in/out, no source routing,
  RFC 1337. Deliberately *not* disabling user namespaces (Flatpak, Steam, Chrome),
  not ptrace_scope ≥ 2 (debuggers), not ip_forward (Docker). CachyOS already sets the rest.
- **SSH** stays off; if it is on, the report says how exposed it is (every network?
  passwords?) and `prime-security ssh off|on` (on = home network only).
- **Report** (`prime-security`): firewall + open ports, SSH, automatic updates and
  last update, signature checking, AUR count, kernel protections, screen lock,
  private-file permissions, disk encryption. `prime-security fix-permissions` (run
  quietly at each login) keeps `~/.config/prime`, `ai.key`, `~/.config-backups` private.

## Tests

- `bash backends/arch/test-system-update.sh` — 103 sandbox checks, no root, fake
  pacman/snapper/systemctl (the updater refuses test mode if any resolves to the real one).
- `bash backends/arch/test-system-in-container.sh` — 26 checks in a clean Arch
  container as user *alex*; `FULL=1` adds a real update through the updater (29).
- The older bootc-style supervisor in `backends/arch/` keeps its P0 fixes (idle units,
  rollback loop bounded): `test-autoupdate.sh` 40, `test-idle.sh` 9, `test-boot-health.sh` 7.
