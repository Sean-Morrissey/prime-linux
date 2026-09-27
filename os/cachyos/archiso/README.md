# os/cachyos/archiso — the Prime OS buildset for the CachyOS live ISO

We do **not** hand-roll an ISO builder. CachyOS publishes one
([`CachyOS/CachyOS-Live-ISO`](https://github.com/CachyOS/CachyOS-Live-ISO), `buildiso.sh`
with a `-p <profile>` buildset flag), and the installer UI is Calamares from the
`cachyos-calamares` package. This directory is the overlay we drop into a clone of that
repo — nothing more.

## What is in here

```
archiso/
  packages_prime.x86_64                  target-side packages for the Prime layer
  calamares/modules/
    packagechooser_bootloader.conf       our default + plain-language descriptions
    partition.conf                       CachyOS's file, annotated for a Windows dual-boot
```

Calamares does **not** merge config files: an override replaces the whole file. Every file
here is therefore the complete real one (copied out of `cachyos-calamares` 3.4.2-4 and
edited), never a partial fragment — a fragment would silently drop the settings it does not
mention.

## Build (never run on Sean's machine)

```bash
git clone https://github.com/cachyos/cachyos-live-iso.git cachyos-archiso
cd cachyos-archiso
# copy this directory's contents over archiso/ (packages_prime.x86_64 is additive)
./buildiso.sh -p desktop
```

The build needs `archiso`/`mkarchiso` and root, and it is a **container or CI job**, not a
package install on the reference desktop. Nothing here has been built yet — there is no
`archiso` on Sean's CachyOS box and no ISO has ever been produced from this profile. Say
that plainly until a boot says otherwise.

## The desktop stack it installs

`packages_prime.x86_64` is derived from `pacman -Qe` on the reference desktop
(2026-09-27), filtered to what the product actually needs: Hyprland, the two Waybar bars'
dependencies, rofi, the notification daemon, the PipeWire stack, fonts, and the
snapshot/rollback tooling. AUR-only items (cursor and theme packages, `uv`) are listed in a
clearly marked section — they cannot come from a repo during image build and need either a
local repo or a first-boot install step, which does not exist yet.

## Loader choice — the open owner decision

CachyOS's installer offers five loaders (`grub`, `refind`, `refind-ai`, `systemd-boot`,
`limine`) and defaults to **limine**. Their own descriptions, which we are replacing, say
systemd-boot does **not** do snapshots while limine has "Btrfs snapshot integration out of
the box" plus Windows dual-boot via `limine-scan`. Sean's own rig runs **systemd-boot**,
where the single rollback entry is produced by `prime-pc` rather than by the loader.

So the boot-menu requirement in [`docs/DUALBOOT.md`](../../../docs/DUALBOOT.md) resolves
differently per loader, and picking one is a product decision, not an implementation detail:
ship the loader that gives the menu for free (limine/grub + snapshots), or ship the one the
reference machine runs and own the rollback entry ourselves (`prime-pc`, already written and
tested). `packagechooser_bootloader.conf` currently keeps limine as the default with a
comment pointing here.

## Unverified, and not to be described otherwise

- No ISO has been built, so no profile file here has been executed by `mkarchiso`.
- The Calamares overrides have not been rendered by Calamares.
- The `archiso/` layout above is CachyOS's, read from their repository tree; our files are
  meant to be copied into it, and that copy has not been rehearsed either.
- First-boot wiring for the payload (`os/cachyos/README.md` → `tools/expand-payload.py`)
  does not exist yet: nothing runs it after the install.
