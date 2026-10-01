# Build state — 2026-09-27 (evening)

Where Prime OS stands after the first real ISO build and the first boot test. Read this
before touching `os/cachyos/archiso/` or rebuilding.

## Short version

The CachyOS-based ISO **builds, boots under UEFI, and carries Prime's installer
configuration** — verified from inside the running live system, not from logs. It **cannot
install yet**, and the reason is upstream, not ours: CachyOS's Calamares package is built
against a Boost version the repos no longer ship.

## The artifact

    ~/Projects/cachyos-archiso/out/desktop/cachyos-desktop-linux-260927.iso   3.1 GB
    sha1   575dfb48d66a837be5a2bbfbc5a8b695377d794b
    sha256 758f6f195d067c89d122d877264b59e79ba9d39baa42514b92d490d059854c2c

Build: `~/Projects/cachyos-archiso` (clone of CachyOS-Live-ISO, buildset applied).
Tooling installed to do it: `archiso` (mkarchiso, xorriso, mksquashfs).

## Verified in the booted image (VM, UEFI, QEMU + OVMF)

- boots to a live KDE desktop, no errors
- installer config, read from a terminal **inside the running live session**:
  `default: "Prime-Desktop"` in `/etc/calamares/modules/packagechooser_desktop.conf`
- our pacman hook fires at the live session's reinstall of the installer package:
  `prime: applied 8 installer override file(s)` — this is the mechanism that stops the
  launcher's reinstall from restoring upstream's config. It is load-bearing; do not
  "simplify" it away.
- from the ISO's squashfs: UEFI boot files present, our desktop chooser, our 62-package
  group, the local-only package source, our post-install step in the exec sequence

Screenshots of the boot test are kept in `~/.hermes/cache/scratch/primevm/` (scratch prunes
after 72h).

## The blocker (upstream)

`cachyos-calamares-next` 3.4.2-13 ships `libcalamares.so.3.4.1`, built against
`libboost_python314.so.1.91.0`. The repos ship `boost-libs` **1.92.0**, which provides only
`…so.1.92.0`. The package depends on the *name* `boost-libs`, so pacman reports everything
satisfied. Result:

    calamares: error while loading shared libraries: libboost_python314.so.1.91.0

Any CachyOS ISO built today has a non-launching installer, theirs included. A soname symlink
was tried and **does not work** (`undefined symbol: …boost::python::detail::init_module`) —
the ABI is gone, so the binary needs rebuilding upstream.

## Options when we pick this up

1. **Wait for CachyOS to rebuild the package, then rebuild the ISO** (about one command plus
   the build time). Cleanest; nothing to ship but our own config.
2. Pin `boost-libs` 1.91 into the live image from Arch's package archive (local repo in the
   ISO). Works today; ships a downgrade in the live environment to patch someone else's bug.
3. Build Calamares ourselves into the image. Real work for a problem that fixes itself.

## How to resume

    cd ~/Projects/prime-linux.capture
    ./tools/apply-buildset.sh ~/Projects/cachyos-archiso     # 15 checks, exits non-zero on any failure
    cd ~/Projects/cachyos-archiso && sudo ./buildiso.sh -p desktop

Then boot it in a VM (QEMU + OVMF + usb-tablet; drive keys with the monitor socket, do not
aim clicks at guessed pixel coordinates — that is how a click meant for "Launch installer"
opened a forum page instead).

## Still not done (unchanged by today)

- the Prime layer itself (theme, bars, assistant scripts) is not wired into an install —
  nothing runs `tools/expand-payload.py` against the installed system
- branding: the ISO and the installed system still say CachyOS
- no install has ever been completed to a disk, on this base or the older Fedora one
