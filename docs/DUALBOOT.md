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
   `prime-pc boot-entry <N>`. Never build the rollback story on `grub-btrfs` — there is no
   GRUB on a systemd-boot machine.
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

## Status

Nothing here is implemented for the CachyOS base yet — there is no archiso profile, and the
drivers that exist (`prime-pc` on the reference machine) are the *source*, not a shipped
installer. Two gates belong in `SHIP-GATES.md` once the owner agrees the numbering:

- **A7 (install alongside):** on a machine with Windows already installed, Prime installs
  into free space, Windows still boots from the menu afterwards, and the user's data is
  intact — verified on a VM with a real Windows install, then on the first real machine.
- **C7 (dual-boot recovery):** from a deliberately broken Prime install, the user can boot
  the rollback entry, and from a broken Prime install the Windows entry still boots.

Neither is passable by reading this file; both need a boot on a machine that is not Sean's.
