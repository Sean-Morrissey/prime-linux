# Changelog

What changed in each release, in the words a person using Prime would use.
Versions are calendar-based (`YEAR.MONTH.N`); see [docs/RELEASE.md](docs/RELEASE.md).

## Unreleased

### Changed

- **Start menu and keys: one of everything.** No more duplicate rows (App Store,
  Packs, Power mode, Animations, Text size, Get help) and no plumbing rows like
  Restart the bar. Super+T and Super+W are free for your own shortcuts.
- **Troubleshooting is one button.** Check and fix (Super+H) now also restarts
  sound and notifications and offers to turn power modes on.
- **Settings** groups its pages under Connections, Desktop, Devices, Apps, System
  and Help. Processor and Graphics are one page.
- **Welcome** is four short steps. It only asks how much the assistant may do once
  you've connected one.
- **Prime Search** shows each place once, and says Open when that's all it does.
- **The install line checks what it downloads**: on the stable channel it runs only
  a release signed by Prime's release key.
- Prime Linux is now free software under the GPL (version 3 or later).

## v2026.10.0 — 2026-10-03

The first release. Everything below is new because there is nothing before it.

### New

- **The desktop.** Hyprland with a top bar, a dock that appears when the pointer
  touches the bottom edge, a side bar that hides until the pointer reaches the left
  edge, five workspaces that keep their apps, and title bars with minimise, maximise
  and close. Super+Space searches, Super+I opens Settings, Super+/ lists every
  shortcut, Super+arrows snap a window to half the screen.
- **Settings, in plain words.** Display, Sound, Wi-Fi & Network, Printers, Graphics,
  Processor, Dock, Top Bar, Windows & Workspaces, Lock & Sleep, Startup Apps,
  Accessibility, Privacy & Security, Updates, Troubleshooting, About & Help.
- **Updates that can be undone.** Nightly updates in a window you choose, a snapshot
  before every update on a btrfs disk, the snapshots listed in the boot menu, and
  Undo an update when something goes wrong.
- **A health check** (Super+H) that reports in sentences and offers a button for each
  repair rather than a command to type.
- **File History** — snapshots of your home disk, and Get a file back.
- **Packs** you turn on and off: gaming, coding, creator, student, AI.
- **The assistant**, with a permission level you set, a toolbox it is allowed to use,
  and a tutor mode that teaches rather than does.
- **Remove Prime** from Settings → Troubleshooting: puts the computer back as it was,
  restores the files it replaced, and keeps your Prime settings in `~/.config-backups`.

### Upgrading

Nothing to do — this is the first release. Installing is one line in the
[README](README.md).
