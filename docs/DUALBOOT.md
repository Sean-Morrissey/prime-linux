# Dual-boot: Prime OS next to Windows, with a snapshot menu

Owner requirement, 2026-09-27: *"hes gonna be dual booting like me too so he needs the boot
menu for snapshots and windows and linux options like i do."*

That makes the boot layout a **product requirement, not an install detail**. This is the
reference implementation, taken from Sean's own CachyOS box (`prime-pc`) — and the rollback
capping that machine needed (see `PROJECT-STATE.md` / `prime-pc-machine-supervisor`) ships
in the template from day one, so a fresh install never grows one menu line per update.

## What the machine must end up with

```
systemd-boot (BootCurrent → systemd-bootx64.efi, ESP mounted /boot)
  ├── Windows Boot Manager            ← detected, never modified
  ├── Prime Linux                     ← default (@saved)
  ├── Prime Linux (LTS)               ← the "an update broke it" fallback
  └── Prime rollback — <date>         ← exactly ONE, the newest snapshot
```

Evidence from the reference machine (`bootctl list`, 2026-09-27): three Prime/Windows
entries plus the firmware entry, and a single capped `Prime rollback` line.

## The four things that must be true

1. **The installer never touches what it did not create.** Reuse the existing ESP, write
   only under `\EFI\prime\` (or `\EFI\Linux\`) and the loader's own `loader/` directory,
   never overwrite `\EFI\Microsoft\`, never reformat an EFI partition that already holds
   another OS, never auto-shrink a Windows partition — ask, and if there is no free space,
   stop and say so.
2. **Snapshots ship wired up.** btrfs root as a subvolume (`@`), snapper config `root`,
   `snap-pac` for a pre/post snapshot on every transaction, `/.snapshots` as a *nested*
   subvolume so snapshots survive the thing they protect. `/home` is a separate subvolume
   and is **not** snapshotted: rolling the OS back must never touch the user's files.
3. **The boot menu stays short.** `prime-pc boot-entry <N>` writes a bootable entry for
   snapshot N; `boot-entry-prune` keeps the newest `ROLLBACK_ENTRIES` (default 1) and drops
   the rest. Older snapshots stay in snapper and can be re-added in seconds with
   `prime-pc boot-entry <N>`. **Which loader provides the menu is an open decision**, and it
   changes who does the work: CachyOS's installer offers GRUB, rEFInd, systemd-boot and
   Limine (default **limine**), where Limine gets snapshot entries and Windows detection out
   of the box and GRUB reaches the same place through `grub-btrfs`; systemd-boot does neither
   and needs `prime-pc` to generate the single rollback entry itself — which is what the
   reference machine does, and which is already written and tested. Building the rollback
   story on `grub-btrfs` on *Sean's* box would be wrong (it has no GRUB); on a CachyOS
   install it is a supported path. Do not carry the constraint across bases.
4. **Nothing reboots into a bad state.** Boot-time verification (failed units, session,
   network, audio) with automatic rollback to the previous entry, and a hard stop after two
   bad boots so it cannot loop.

## Windows-specific hazards to handle, not hope about

| Hazard | What the installer/product does |
|---|---|
| Windows Fast Startup leaves NTFS dirty | Detect fast-startup state read-only; tell the user in plain language to turn it off (**Settings → Power → Fast Startup**) before the first shared-NTFS write. Never "fix" it silently. |
| BitLocker demands a recovery key after a boot-order change | Say it in the pre-install checklist: *write down your recovery key first*. The installer must not change Secure Boot state (that is what usually triggers it). |
| Clock skew between the two OSes | Prime runs the RTC in UTC (`timedatectl set-local-rtc 0`) and says so, instead of leaving the user with a wrong clock in Windows. |
| Secure Boot | Ship the signed shim/`systemd-boot` path; a stock `systemd-bootx64.efi` is not enrolled by every firmware. Detect the state and report it rather than guessing. |
| Two bootloaders fighting | Prime adds its own entries and sets itself default **once**, then honours `@saved` — it does not silently re-assert itself after the user picks Windows. |
| A user who removes Prime | An uninstall path must be able to remove its own EFI directory and boot entries and leave Windows bootable. Windows' own bootloader is never touched, so this is a delete, not a repair. |

## The first target machine already has Windows (confirmed 2026-09-27)

So install-alongside is the path, not a hypothetical, and the pre-install checklist is part
of the product rather than a support article. In this order, in plain language:

1. **Free space first.** Prime does not resize a Windows partition. Windows' own Disk
   Management must shrink it. If there is not enough unallocated space, the installer stops
   and says so — it never performs surgery on a partition another OS boots from.
2. **Check the EFI partition, don't assume it.** Windows' ESP is commonly 100–260 MB and is
   *reused* as `/boot`, never reformatted. A kernel plus initramfs has to fit beside it. A
   separate new ESP is a last resort: firmware does not reliably boot a second one.
3. **Get the BitLocker recovery key in hand before installing anything.** Changing the boot
   order is the classic trigger for a recovery prompt, and the installer must not change
   Secure Boot state either.
4. **Turn off Windows Fast Startup** (Control Panel → Power Options → Choose what the power
   buttons do). A dirty NTFS volume shared with another OS is how files get lost.
5. **Do not pre-select a partition layout.** `initialPartitioningChoice: none` is a safety
   property: with another OS on the disk, a one-click "erase everything" is the worst thing
   this product could put in front of a stranger. See
   `os/cachyos/archiso/calamares/modules/partition.conf`, rule 1.
6. **The clock.** Prime keeps the hardware clock in UTC and says so, instead of leaving the
   user with a wrong clock in Windows.

## Status

The buildset now exists — `os/cachyos/archiso/` (an overlay for CachyOS's own
`CachyOS-Live-ISO` builder: our package list, the boot-menu chooser in plain language, and
the partitioning rules above) — but **no ISO has ever been built**: there is no `archiso` on
the reference machine, and the Calamares files have been validated as YAML and diffed
against CachyOS's originals, not rendered by Calamares. The drivers that exist (`prime-pc` on
the reference machine) are the *source*, not a shipped
installer. Two gates belong in `SHIP-GATES.md` once the owner agrees the numbering:

- **A7 (install alongside):** on a machine with Windows already installed, Prime installs
  into free space, Windows still boots from the menu afterwards, and the user's data is
  intact — verified on a VM with a real Windows install, then on the first real machine.
- **C7 (dual-boot recovery):** from a deliberately broken Prime install, the user can boot
  the rollback entry, and from a broken Prime install the Windows entry still boots.

Neither is passable by reading this file; both need a boot on a machine that is not Sean's.
