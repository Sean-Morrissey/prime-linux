# Prime Linux — architecture

> **Prime is not an app in this distro. Prime *is* the supervisor of this distro.**
> You install Prime Linux, you talk to Prime, you tell it who you are, what you're
> studying, what you're building, and how you like your machine — and Prime does
> the setup. It stays on, it supervises updates, it fixes what breaks, and it can
> still drop into a terminal when a human wants to type.

This document is the design of record. Everything in `recipes/` follows from it.

---

## 1. The three layers

| Layer | What lives there | Who changes it |
|---|---|---|
| **Base image** | Fedora Atomic (Aurora/KDE) — kernel, drivers, firmware, desktop | upstream + daily CI rebuild |
| **Prime layer** | Hermes agent, voice stack, StudyHub, whiteboard, self-repair, branding | you, by editing `recipes/recipe.yml` (CI rebuilds) |
| **User layer** | identity, courses, projects, dotfiles, installed apps, habits | **Prime**, during and after the first-boot interview |

Nothing personal is baked into the image. The image ships *capability*; the
interview creates *a person's machine*. That separation is what makes one ISO work
for you, your buddy, and the next ten people.

---

## 2. What Prime can actually do (the honest capability table)

This is the part most "AI in the OS" pitches fake. On an atomic base — and as of
2026 Universal Blue images are bootc-based, where local package layering is
explicitly *not* a supported path — Prime's verbs are:

| User says | Prime does | Reboot? |
|---|---|---|
| "install Discord / Spotify / Anki" | flatpak install (system-wide, survives updates) | no |
| "I need Python 3.12, Node 18, a ROS toolchain" | distrobox container, exported to the app menu | no |
| "install something only in the system repos" | adds it to the *recipe*, CI rebuilds the image, `bootc upgrade`, activate | yes (one, guided) |
| "update my system" | atomic image upgrade; previous deployment stays bootable | yes |
| "it broke" | health check → plain-language report → roll back to previous deployment | yes |
| "tweak a config file" | `/usr` overlay for ephemeral testing, then promote into the recipe | maybe |
| "read my files / docs / notes / mail" | full, with per-path consent | no |
| "run this command" | shell, gated by the permission ladder (§4) | no |

The trade is deliberate: **Prime cannot brick the machine, because it can't write
to the system's real root.** Everything it changes is either user-space, a
container, or a whole new image that can be rolled back in one reboot. That is the
entire reason this is safe to hand to a freshman who has never used Linux.

---

## 3. The interview (first boot)

The installer stays stock — a normal Anaconda install from the ISO, no custom
partitioning wizardry. The *moment of Prime* is first login, where a full-screen
Prime conversation takes over:

**Prime asks (conversationally, voice or typed):**
1. Who are you — name, what you want to be called, pronouns, language.
2. Where are you — school, term, courses, meeting days, timezone.
3. What are you building — projects, languages, tools, repos.
4. How do you work — KDE or the Prime (Hyprland) session, dark/light, do you want
   the assistant to speak out loud, quiet hours, how much autonomy it gets.
5. Connect me — the user's *own* API key / account. Never bundled, never shipped.

**Prime then writes:**
- dotfiles into `~/.config` (session, Waybar, terminal, editor)
- `~/College/` year/term scaffolding + StudyHub data, populated from the courses
- scheduled reminders for class times and deadlines
- the app set (flatpaks/containers) their answers implied
- a memory vault — the "soul" file: identity, projects, preferences, goals. This is
  the seed of the persistent memory the agent carries forever after.

**Prime never:** stores credentials outside the user's home, phones home, or ships
one person's data to another install.

---

## 4. Safety model

An agent with shell access on someone else's machine needs a spine, not vibes.

- **Capability ladder** — per capability (read, write user files, install apps,
  system packages, network, run shell): `observe → suggest → approve-each → auto`.
  New users start at *suggest*. "Auto" is opt-in per capability, never global.
- **Rollback is the undo button** — any system-level change is a new deployment.
  If the next boot is unhealthy, Prime detects it and offers the previous one.
- **Audit log** — every command Prime runs is recorded (the activity-timeline hook
  already does this on Sean's machine) and viewable in plain language: what, when,
  why, what changed.
- **Spend cap** — a hard monthly ceiling on model calls, surfaced in the UI.
- **Two profiles** — `owner` (full) and `student` (stricter defaults, safer
  session, no destructive verbs without approval).

---

## 5. Why the shipped base is Fedora Atomic and not CachyOS/Arch

CachyOS is the right machine *for Sean*: rolling, fast, hand-tuned, and he can fix
it when it breaks. CachyOS is the wrong machine to hand to someone who has never
opened a terminal, for exactly one reason:

- **Arch + root agent = unrecoverable failure modes.** A rolling distro plus an
  agent that can install anything plus a user who can't read a pacman error is a
  machine that eventually dies in a way nobody can diagnose. Snapshots (btrfs +
  snapper + limine-snapper-sync) soften it, but the user still has to reason about
  which snapshot to boot and whether the fix "took."
- **Atomic + root agent = bounded failure.** The worst case is a bad image, and the
  boot menu already contains the fix. Non-negotiable when the user can't help.

Sean's own machine stays CachyOS. Prime Linux is what gets *shipped*.

---

## 6. Runtime shape

- `prime-agent.service` (user) — the supervising agent: health checks, update
  watching, scheduled reminders, voice listener.
- `prime-voice` — hotkey push-to-talk now (proven on CachyOS); wake word later.
- `prime-firstboot.service` (system, oneshot) — creates scaffolding, runs the
  interview once.
- `prime-whiteboard.service` — the whiteboard/timeline UI.
- **Terminal stays first-class** — Prime is the supervisor, not a cage. Every action
  Prime takes is a command the user could have typed, and can inspect.

---

## 7. Milestones

1. Bootable ISO from this repo: Aurora base, rebranded, stock install works. **← now**
2. Two sessions at login: "Desktop" (KDE, default) and "Prime" (Hyprland).
3. The interview: first-boot conversation that personalizes the install.
4. Supervision: update watcher, post-update health check, guided rollback.
5. Student layer: StudyHub, term scaffolding, whiteboard, math practice.
6. Always-on: voice service, reminders, spend cap UI, activity audit viewer.
7. Polish: logo, wallpaper, Plymouth, installer branding, `prime` CLI.
