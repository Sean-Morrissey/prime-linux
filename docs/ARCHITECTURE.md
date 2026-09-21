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

**Why Aurora specifically, of the Universal Blue images:** it is the quiet
productivity workstation of the set — KDE Plasma, drivers, codecs, flathub and
`brew` instead of layering, automatic silent update staging, and 3.46 GiB against
Bazzite's 4.69 GiB. Two things make it the right base for this project: its
identity is restrained, so there is little upstream branding and first-run tooling
to sand off before ours shows through; and it already ships **restic, rclone and
DejaDup**, which is most of the backup machinery this distro owes a student.

The one thing Bazzite does better is gaming — Steam, Proton, Lutris, HDR/VRR,
tweaked CPU schedulers, a Gamescope session. That matters for exactly one case: the
target machine is also the machine its owner games on, because a Linux laptop that
can't run the games already owned gets dual-booted back to Windows within a month.
If that becomes the case, the recipe swap is one line to
`ghcr.io/ublue-os/bazzite`, and rebasing between Universal Blue images later is a
single `bootc switch` — so this is not a one-way door.

One consequence for either base: downstream images must not fight the upstream
desktop. Aurora documents which mutations it doesn't support, and anything we
change that upstream owns (look-and-feel, splash, first-run tooling) has to be
either a supported hook or a deliberate, documented override.

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

---

## 8. The hard problems

Four objections get raised against this design. Three have answers; one is a real
long-term bet.

### 8.1 The onboarding conversation is the entire product

Correct, with one correction to the usual framing: **the failure mode is not
"too many questions", it is "a form".** Asking eight questions before anything
happens is a traditional installer with a chat skin.

The contract instead:

- **Prime acts while it asks.** Inside the first sixty seconds it does something
  visible and useful — profiles the hardware, sets up the desktop, reports what it
  found ("your Wi-Fi, printer and display are working; you have 460 GB free"). The
  user sees competence before being asked for anything.
- **Each answer produces an immediate visible effect.** Courses typed in → the term
  scaffolding and reminders appear, right there, on screen.
- **Terse by design, inferred by default.** Name, what you study, what you mostly
  do, do you code, do you game, accessibility needs, light/dark, anything else.
  Everything else is inferred from the machine or deferred until first needed
  ("I'll set up LaTeX when you first need it").
- **Interruption is free.** Skip, stop, come back, or say "actually, change my
  dark mode" a year later. The interview never really ends — it just gets quieter.
- **Not chat-only.** A novice mis-hearing an AI is worse than a form. The interview
  is a small wizard Prime narrates and drives, with voice optional.

### 8.2 Memory architecture decides whether Prime is still useful in week two

The shape is right and **most of it already exists in shipping form on Sean's
machine** — this is the strongest evidence the design is buildable:

| Piece | Existing implementation |
|---|---|
| Identity / preference seed | `~/.hermes/memories/USER.md` + `MEMORY.md` (curated, char-capped) |
| Episodic log (what happened, when) | `~/.hermes/state.db` + full-text search over every past session |
| Event log (what Prime *did*, outcome) | `~/College/whiteboard/activity.jsonl` via the activity-timeline hook |
| Retrieval layer | `session_search` + memory injection per turn; `ai-search` over archived transcripts |
| Procedures (how to do recurring tasks) | skills |
| Long-term archive | `~/AI-Transcripts-Archive/` Markdown transcripts |

What the distro adds is not the mechanism, it is **ownership and legibility**: the
memory is visible and editable by the user, exportable, and never leaves the
machine. The real gaps to design are the pruning policy (a capped store needs
consolidation rules, not just appends) and *proactive recall* — nothing surfaces
last Tuesday's group project unless something triggers the search.

### 8.3 Cloud dependency vs local inference

The usual answer — bolt on a small local model for offline mode — is the wrong
first move, because **most supervision does not need a model at all.** Prime's
routine work is deterministic: is the disk filling, did the last update boot
cleanly, is the printer reachable, is the snapshot chain intact, is the service
alive. That has to be scripts: free, offline, instant, auditable, and impossible to
hallucinate.

So the tiering is three rungs, not two:

1. **Scripts** — health, updates, rollback, reminders, setup actions. Always
   available, no network, no cost. This is the majority of "always on".
2. **Cloud model** — conversation, novel reasoning, coursework help, the interview
   itself. Needs network and money: hence a spend cap, a free-tier provider
   option, and honest degradation ("I can't reach the model right now; the system
   itself is fine and healthy").
3. **Local model** — optional, later, for talking to Prime offline. Not v1.

### 8.4 Who maintains it for years

The real risk, and the honest answer is *make the maintenance surface small enough
to survive one person.*

- The overlay is a **recipe and a file tree**, not a fork: no kernel, no drivers, no
  desktop source. Upstream carries security updates, hardware support and the
  desktop; the daily CI rebuild absorbs them without a human.
- **Publish it rebasable.** The artifact is the recipe — anyone can point it at
  their own registry and carry it. That is what stops the project from dying with
  one person's enthusiasm.
- **Upstream the layer.** The agent packaging, voice stack and self-repair belong
  in the upstream project, not a private fork of it.
- The per-Fedora-release work is real and recurring; the mitigation is thinness,
  not heroics.

---

## 9. Base-agnostic supervision (and the honest Arch story)

The question that keeps coming back: can this work on Arch, like Sean's own CachyOS?
The answer splits cleanly, and the split is the useful part.

**The agent layer does not care what distro it runs on.** hw-probe, the interview,
the identity seed, the capability ladder, the voice stack, the reminders — none of
it is Fedora-specific. What is base-specific is exactly one thing: *how a bad update
gets undone.* So supervision is an interface with swappable backends:

| Verb | What it means |
|---|---|
| `check_update` | is there a newer version, and what changed |
| `apply_update` | take it, and leave the previous state reachable |
| `list_rollbacks` | what points can we go back to, in plain language |
| `apply_rollback` | go back |
| `health_check` | did the machine come up sane — services, network, audio, disk, session |

Three backends implement it:

1. **Atomic image (bootc/ostree)** — Aurora, Bazzite, Bluefin. Rollback is a boot
   menu entry; the previous image is always there. Failure is bounded and rare.
2. **btrfs snapshots** — CachyOS / Arch with `snapper` plus `limine-snapper-sync`,
   which snapshots every pacman transaction and exposes the snapshots *in the
   bootloader*, so recovery is "pick the older entry", not "chroot and pray".
   CachyOS documents this as a first-class feature.
3. **Arch image systems** — `arkdep` (Arkane Linux) and Manjaro Immutable. Real,
   image-based, and interesting — but small community projects with narrower
   hardware coverage. Not what ships to a beginner.

Two honest differences, in opposite directions:

- **On Arch, Prime's powers are stronger.** `pacman -S` is synchronous, so "install
  this for me" actually installs instead of triggering an image rebuild and a
  reboot. The async limitation in §2 is a Fedora-Atomic property, not a universal
  one.
- **On Arch, failure is more frequent.** Rolling updates break things more often,
  and recovery still requires a human at a boot menu when the system doesn't come
  up. Rollback makes Arch *recoverable*; it does not make it *safe for someone who
  cannot diagnose it*. So atomic stays the default for the shipped distro and
  snapshot-based Arch is the power option: Prime Linux (Atomic) and Prime Linux
  (Arch edition) are two backends over one supervisor, not two rival ideas.
