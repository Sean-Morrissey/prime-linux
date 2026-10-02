# Master review — a prompt for a full audit of Prime Linux

Paste everything below the line into a fresh session that has this repository
checked out. It asks for a review and a plan, not a rewrite. Nothing is pushed
until you say so.

---

You are reviewing **Prime Linux** as a principal engineer who has shipped a desktop
operating system people love: part kernel and systems engineer, part product designer
with Apple-level taste, part Windows-scale support lead who knows what breaks on a
stranger's computer at 2 a.m. You are honest, specific and hard to impress. You
praise only what earns it. Every finding you make is something you checked yourself.

## What Prime is

- A desktop layer on **CachyOS / Arch + Hyprland** (`layer/`, installed to
  `~/.local/share/prime-linux` by `install.sh`). It also has an ISO path
  (`os/cachyos/archiso`, `os/arch`) and an older atomic image path (`recipes/`,
  `disk_config/`).
- **P.R.I.M.E = Please Relax, I'll Manage Everything.** It's for students and
  non-technical friends first. The owner uses it daily on a Ryzen 5 7500X3D and a
  Radeon RX 9060 XT with two monitors.
- **Rules that are not up for debate.** Flag any place that breaks one:
  1. No terminal anywhere a normal person goes. Every fix is a button or a sentence.
  2. Plain language. No jargon in anything a person reads (`tests/check-static.py`
     enforces part of this).
  3. Every surface says Prime. Nothing is borrowed from Apple, Microsoft or anyone
     else: no logos, product names, icon sets or trade dress.
  4. One text-size setting drives every font. No hardcoded font sizes.
  5. State is never shown by colour alone: there is always a word or a symbol too.
  6. Prime never installs an SSH server.
  7. Every setting changed through Prime is backed up, logged and undoable
     (`layer/bin/prime-settings`: change_setting, undo_last, audit log).
  8. Everything works without AI. The assistant (Hermes, `os/cachyos/payload/skel/.hermes`,
     `layer/addons/ai`) is an optional extra on top.
  9. Updates are safe: snapshot first, signed releases on the stable channel
     (`layer/bin/prime-update`, `prime-release-verify`), one-click undo.
- **The main pieces:** the top bar (`layer/default/waybar`, `prime-bar`); the dock
  (`prime-dock`, nwg-dock-hyprland); Start, Prime Search and Settings
  (`prime-start`, `prime-spotlight`, `prime-system-settings`: 29 pages, GTK4 and
  libadwaita); Hyprland config (`layer/default/hypr`); theme (`prime-theme`); idle
  and lock (`prime-idle`, `prime-lock`); health check (`prime-doctor`); updates
  (`prime-update`); packs (`layer/addons`); no-AI everyday actions (`prime-do`).
- **The docs worth reading first:** `docs/ARCHITECTURE.md`, `docs/PRIME-LAYER.md`,
  `docs/USER-GUIDE.md`, `docs/UPDATES-AND-SAFETY.md`, `docs/PRIME-AND-HERMES.md`,
  `docs/REVIEW-2026-10-FULL.md` (the last audit; check whether its findings were
  really fixed).

## How to work

1. **Read before you judge.** Start with the docs above, then `install.sh`, then
   `layer/bin/` (about 70 tools), `layer/default/`, `layer/systemd/`,
   `.github/workflows/desktop-layer.yml` and `tests/`.
2. **Run what can run here:** `bash tests/check-shellcheck.sh`, `check-syntax.sh`,
   `check-static.sh`, `check-settings-app.sh`, `check-menus.sh`, `check-snap.sh`,
   `check-prime-do.sh`, `check-update-rewritten.sh`. A GTK4 Python plus `xvfb-run`
   lets the Settings self-test build every page
   (`PRIME_TEST_PY=python3.12 bash tests/check-settings-app.sh`). Report what you ran
   and what happened. `check-install.sh` and `check-uninstall.sh` only work inside
   CI's container.
3. **Walk the person's path in your head,** as a 17-year-old who has never used
   Linux. Cover the first boot, the first login, Wi-Fi, opening apps, workspaces,
   the dock, a screenshot, an update that fails halfway, a dead battery
   mid-update, a second monitor plugged in, a game, forgotten Wi-Fi, "my sound
   stopped", and uninstalling Prime. Where does it confuse, stall, lie or need a
   terminal?
4. **Then think as an attacker and as entropy.** What can a malicious package,
   web page, pack, `menu.json` or pushed commit do? What breaks after six months of
   CachyOS and Hyprland updates? (Watch Hyprland config syntax changes, hyprpm
   plugins, nwg-dock flags, waybar options.)
5. **Prove each finding.** Give a file and line, a command you ran, or an exact
   sequence of steps. If you can't prove it, label it **suspected** and say what
   would confirm it.

## What to look at

- **Architecture and code health:** duplication across the `layer/bin` tools,
  shared helpers (`prime-panel` is imported by others), error handling, races at
  login (bar, dock, idle, title bars), restart storms, what happens offline.
- **Reliability and updates:** `prime-update` end to end, snapshots and rollback,
  signed releases, the repository-history-restart case, migrations
  (`layer/migrations`, `prime-migrate`), packages missing after an update,
  uninstall leaving a clean system.
- **Security and privacy:** `prime-askpass`, password handling (`prime-passwd`),
  sudo use, anything run from user-editable files, file permissions, the firewall
  defaults, what the assistant may do without asking, and whether any personal
  information could end up in logs or help reports.
- **UX polish, to the Apple and Windows standard:** visual consistency (spacing,
  icons, one palette, motion), Settings coverage (what a person expects to find and
  can't), empty states, error messages, first-run, discoverability, keyboard-only
  use, screen readers (accessible names), multi-monitor behaviour, HiDPI.
- **Performance:** login time, the bar and the dock polling (`interval`, `exec`
  loops, `prime-dock` edge watcher), Python start-up costs, anything that wakes the
  CPU every second.
- **Gaming on this hardware:** VRR, tearing, gamemode, Steam, the AMD RX 9060 XT
  driver stack, the 7500X3D (X3D scheduling / core parking).
- **Branding and IP:** anything still borrowed (names, art, icons, colours, words).
- **Tests and CI:** what's untested that matters most, flaky patterns, whether the
  VM boot test really proves the desktop works.
- **Docs:** wrong, stale or missing. Does `USER-GUIDE.md` match what the code does?

## What to hand back

1. **Scorecard:** a score out of 10 for each area above, with one line on why, and
   what would make it a 10.
2. **Top 10 issues, worst first.** For each: what's wrong; the proof (file:line,
   command or steps); who it hurts and how badly; the exact fix as a diff or precise
   steps; and the effort (S, M or L).
3. **All other findings,** grouped by area. Use the same format, kept short.
4. **Quick wins:** things under an hour each that a person would notice.
5. **Missing features a complete desktop OS should have,** ranked by how much a
   student would miss each one.
6. **A three-step roadmap:** this week, this month, before giving it to friends.
7. **What not to change:** the parts that are genuinely good and should be left
   alone.

**Ground rules:** No generic advice. "Add more tests" doesn't count; name the test
and what it must catch. Don't suggest anything that breaks the rules in "What Prime
is". Never put a person's name, handle or email into the repository. Don't push,
merge or delete anything. Write your report to `docs/REVIEW-<today's date>.md` and
stop.
