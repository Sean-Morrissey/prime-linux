# os/cachyos/archiso — the Prime OS buildset for the CachyOS live ISO

We do **not** hand-roll an ISO builder. CachyOS publishes one
([`CachyOS/CachyOS-Live-ISO`](https://github.com/CachyOS/CachyOS-Live-ISO), `buildiso.sh`
with a `-p <profile>` flag), and the installer UI is Calamares from the
`cachyos-calamares-next` package. This directory is the overlay we apply to a clone of that
repo.

## How it is applied

```bash
git clone https://github.com/CachyOS/CachyOS-Live-ISO.git ~/Projects/cachyos-archiso
~/Projects/prime-linux.capture/tools/apply-buildset.sh ~/Projects/cachyos-archiso
cd ~/Projects/cachyos-archiso && sudo ./buildiso.sh -p desktop
```

`tools/apply-buildset.sh` does the work and **verifies its own output** — it exits non-zero
if any of the twelve checks fail, so a broken buildset cannot be mistaken for a good one.

## Why nothing here is a vendored copy

The installer config is fetched from the real package at apply time
(`cachyos-calamares-next`, the one the ISO's package list installs and its launcher
reinstalls at boot). Vendoring its ~800-line `netinstall.yaml` into this repo would drift
silently against upstream; instead the script fetches, edits programmatically, and asserts.
The only file we author ourselves is `shellprocess_prime_target.conf`.

```
archiso/
  packages_prime.x86_64            target-side package list (single source of truth)
  calamares/modules/
    shellprocess_prime_target.conf our post-install step for the installed system
  airootfs/                        copied into the live image
    etc/calamares/scripts/prime-target-setup      runs inside the install target
    etc/pacman.d/hooks/95-prime-os-overrides.hook fires when the installer package lands
    usr/local/bin/prime-live-overrides            copies the staged config into place
```

## The two mechanisms that make the overrides stick

**1. Into the live image, after the packages land.** archiso copies `airootfs/` in *before*
packages are installed, so a config file dropped there is simply overwritten by the package
version. Our staged tree therefore lives at `/usr/share/prime/overrides/` and a pacman hook
copies it over the packaged files in a `PostTransaction` run.

That hook deliberately does **not** carry CachyOS's `remove from airootfs` marker: their
`zzzz99-…` hook deletes every hook containing it, and our hook has to survive into the live
session because `calamares-online.sh` reinstalls `cachyos-calamares-next` right before
launching the installer. Without that, the reinstall would restore the packaged config and
quietly undo everything. The hook's `Exec` is written so it cannot fail a transaction inside
the target, where the script does not exist.

The authoritative settings file is `/usr/share/calamares/settings_online.conf`: the launcher
copies it to `/etc/calamares/settings.conf` at start-up, so a copy sitting only at the
destination would be replaced on every boot.

**2. Into the installed system, after it installs.** A Calamares `shellprocess` step
(`shellprocess@prime_target`, appended after `shellprocess@btrfs_snapshot`, which is already
after `- bootloader`) runs `prime-target-setup` *inside* the new system. It caps the boot
menu at one rollback entry, excludes post-update snapshots so the surviving entry is never
the broken state, and points the rollback tool at the boot entry by the name the system
gives itself in `/etc/os-release` — so a later rebrand cannot silently break rollbacks.

### Modes are not preserved (this cost a build)

`mkarchiso` copies `airootfs` with `cp -af --no-preserve=ownership,mode`, so **every file
arrives in the live image as `0644`** — nothing from `airootfs` is executable there. Both of
our scripts are therefore invoked through an interpreter (`sh`, `/bin/bash`) and the hook
tests `-f`, never `-x`.

A gate that tests the executable bit fails *silently*: the hook runs, the test fails, the
overrides are never applied, and the image looks fine until someone inspects the installer's
actual configuration. That is exactly what the first build did — caught only by checking the
built root's `/etc/calamares/modules/packagechooser_desktop.conf` and finding upstream's
default still in it. Verify by inspecting the built image, not by trusting that a hook ran.

## What the buildset changes, and nothing else

| Change | Why |
|---|---|
| Desktop chooser offers **Prime Desktop** and pre-selects it | the product's desktop, not a menu of twenty |
| Package source pinned to our local list | upstream's is a floating `groupsUrl` on GitHub `master`; a machine installed in a year must not depend on it |
| Boot-manager chooser descriptions rewritten in plain language | every option says what the menu gives him; no loader trivia |
| Partition step asserted to pre-select **nothing** | the first target machine already has Windows |
| One rollback entry, post-update snapshots hidden | owner's requirement: rollback is Prime's safety net, not a feature the user browses |

## Limine (settled)

The installer's own default is `limine`, and CachyOS packages the whole story:
`limine-snapper-sync` (snapshots as boot entries, with a "restore now" prompt at login),
`limine-mkinitcpio-hook` (kernels as entries), `limine-entry-tool` (finds the Windows Boot
Manager). The author chose it over matching his own systemd-boot rig, which does **not** do
snapshots — there the single rollback entry is produced by `prime-pc` instead.

## Not done yet

- The Prime layer itself (theme, bars, assistant scripts = `../payload/`) is **not** wired
  into an install: nothing runs `tools/expand-payload.py` after the target installs. That is
  the next milestone, and it decides the shape of the installer package we ship.
- Branding: the installed system still calls itself CachyOS (`os-release`, boot entry,
  Calamares branding). The rollback tooling reads that name instead of hardcoding one, so
  branding is a rename plus a `limine-update`, not a repair.
- AUR-only items (cursor/theme packages, `libastal`) need a local repo or a first-boot step.
- Until a built ISO boots on real hardware and installs to a dual-boot machine, none of this
  is "working" — it is a tested buildset, which is a weaker claim.
