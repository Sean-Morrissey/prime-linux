# Prime Linux — the interview

> The interview is the product. Everything else is infrastructure.

This document specifies the first-boot conversation between Prime and a new user:
what Prime says, what it does while it talks, what each answer writes to the
machine, and what the UI looks like. It is the companion to §3 and §8.1 of
[ARCHITECTURE.md](ARCHITECTURE.md).

---

## Decisions locked

Three calls made, so the rest of this document has a fixed target:

1. **The UI is a Hermes Desktop page, not a new app.** Desktop's plugin SDK already
   has a full-page contribution surface (`ROUTES_AREA`, plus a sidebar nav row), so
   the interview is a route the agent shell renders — no second UI stack, no
   GTK-vs-Electron fork, and Phase 2 is not a rewrite. `hw-probe.sh` is already
   written and runs in ~0.2s (`files/system/usr/libexec/prime/hw-probe.sh`).
2. **All interview logic lives in shell scripts and YAML files, never in the UI.**
   The UI renders state and collects answers; `hw-probe.sh`, the file writers, and
   `~/.config/prime/*.yaml` are the actual implementation. Any front-end that can
   read those files can drive this — including a CLI over SSH on a headless install.
   The waist stays narrow; the UI is replaceable.
3. **Accessibility is part of Beat 4, not a follow-up.** A student distro that
   ignores accommodation needs is a student distro that gets uninstalled in
   September. See Beat 4.

---

## Design principles

1. **Act while you ask.** Prime never waits idle for a response. The first thing
   the user sees is Prime *doing something useful* — before it asks a single
   question. Every answer produces an immediate, visible effect on screen.

2. **A conversation, not a form.** The interview is not a wizard with "Next"
   buttons, not a chat window waiting for typed input, and not a voice assistant
   that talks for sixty seconds. It is a narrated setup screen — a simple,
   attractive panel that Prime fills in as it works, with voice optional and
   keyboard always available.

3. **Terse by default, deferred by design.** Ask only what cannot be inferred
   from the hardware or safely defaulted. Everything else happens later, on first
   use. "I'll set up LaTeX when you first open a .tex file" is better than
   asking a freshman whether they need LaTeX.

4. **Interruption is free.** Skip any question. Quit the interview. Come back
   tomorrow. Say "actually change that" a year later. The interview never really
   ends — it just gets quieter.

5. **No secrets in transit.** The API key question is a paste field on the local
   machine. Nothing is transmitted except to the provider the user chose. If the
   user skips it, Prime runs in script-only mode until they connect.

---

## The sixty-second open (before any question)

Prime's first-boot service (`prime-firstboot.service`) has already created
`/etc/skel/College/` scaffolding and the welcome file. When the user logs in for
the first time and the interview UI launches, Prime does the following
**immediately, without asking anything**:

| Second | Prime does | User sees |
|---|---|---|
| 0–5 | Detect hardware: CPU, GPU, RAM, disk, display(s), network | Panel fades in. Prime's name and a calm "Setting up your machine…" |
| 5–15 | Probe peripherals: Wi-Fi, Bluetooth, printer, audio in/out, webcam | A short hardware summary appears, line by line, with check marks: "✓ Wi-Fi connected · ✓ Display 1920×1080 · ✓ 460 GB free · ✓ Audio output working" |
| 15–25 | Derive the timezone from system locale and keyboard layout | "Your timezone is America/New_York — tell me if that's wrong." |
| 25–35 | Verify Flatpak remotes are configured; stage default app set | "Your apps are ready: Firefox, Files, Terminal, Settings." |
| 35–45 | Run initial system health check (disk, battery, thermals) | "Your machine looks healthy." or an honest report if something is wrong |
| 45–60 | Transition to the first question | "Now let me learn about you." |

**What this buys:** the user's first experience of Prime is competence.
Something happened — visibly, quickly, without being asked. Trust before
questions.

### Implementation

The hardware probe is a shell script (`/usr/libexec/prime/hw-probe.sh`), not a
model call. It uses `lscpu`, `lspci`, `free`, `df`, `ip`, `pactl`,
`bluetoothctl`, `lpstat`, and `timedatectl`. The results are written to
`~/.config/prime/hardware.json` and displayed in the interview UI. The probe
runs in < 5 seconds on any modern hardware.

---

## The questions

The interview has **six beats**, not six sequential form fields. Each beat is a
cluster: Prime says something short (voice + text), a UI element appears for the
user to respond (input field, toggle, dropdown, or just "skip"), and when the
user answers, *something happens immediately on screen*.

Beats can be skipped, reordered by the user scrolling past, or answered later.
Every beat has a sensible default if skipped.

### Beat 1 — Who are you

**Prime says:** "What should I call you?"

**UI:** A single text field, pre-focused. Below it: optional toggles for
pronouns (he/him, she/her, they/them, type your own) and preferred language
(defaulted from system locale). No last name, no email, no account creation.

**On answer:** Prime's header immediately changes from "Setting up your
machine…" to "Setting up **[name]**'s machine." The name is written to the
identity seed.

**Writes:**
```yaml
# ~/.config/prime/identity.yaml
name: Alex
pronouns: they/them
language: en
```

**If skipped:** Name defaults to the Unix username. Pronouns default to
they/them. Language from locale.

---

### Beat 2 — What are you studying

**Prime says:** "Are you in school? Tell me what you're taking this term — or
skip this if you're not a student."

**UI:** A small form:
- School name (text, optional — used for branding/context only)
- Term (dropdown: "Fall 2026", "Spring 2027", auto-generated from current date)
- Courses: a repeating row — course code, course name, instructor, days/times.
  Start with one row, "+ Add another" button. Each row is minimal: code and name
  are the only required fields.

**On answer:** For each course entered, the corresponding directory appears
*immediately* in a file-tree sidebar panel:

```
~/College/
  Autumn-2026/
    MATH-1010/
      notes/
      assignments/
    ENGL-1100/
      notes/
      assignments/
      essays/
    COLL-1000/
      notes/
      assignments/
```

Reminders are scheduled for class times (if days/times were entered). The
StudyHub dashboard data file is initialized with the courses.

**Writes:**
```yaml
# ~/.config/prime/identity.yaml (appended)
school: Example Community College
term: Autumn-2026
courses:
  - code: MATH-1010
    name: College Algebra
    instructor: Prof. Sam Patel
    schedule: "MWF 10:00"
  - code: ENGL-1100
    name: Composition I
    instructor: Prof. Dana Reyes
    schedule: "async"
  - code: COLL-1000
    name: First Year Seminar
    instructor: Prof. Jordan Lee
    schedule: "async"
```
```
~/College/dashboard/studyhub-data.json  (initialized)
~/.config/prime/reminders.yaml          (class schedule)
```

**If skipped:** `~/College/` exists (from firstboot) but is empty. No reminders.
StudyHub data file left blank. The user can say "I just enrolled" six weeks in
and Prime runs this beat then.

---

### Beat 3 — What are you building

**Prime says:** "Do you code, make things, or have any projects? Tell me what
tools you use — or skip this if you're just getting started."

**UI:** Three paths, selectable:
- **"I code"** → checklist: Python, JavaScript/Node, Java, C/C++, Rust, Go,
  "other" (text). Selecting any shows a sub-toggle: "Set up now" / "Set up when
  I first need it" (default: deferred).
- **"I make things"** → checklist: 3D printing, graphic design, video editing,
  music production, "other". Same deferred toggle.
- **"I'm just getting started"** → skip; Prime notes it and moves on.

**On answer:** If anything is marked "set up now":
- Programming languages → Distrobox container created with the toolchain,
  exported to the app menu. A small progress indicator shows the pull.
- Creative tools → Flatpak install triggered for the relevant app (Blender,
  GIMP, Kdenlive, Audacity). Progress shown.
- Everything marked "deferred" is stored and triggers setup on first use. (e.g.,
  user opens a `.py` file → Prime says "Want me to set up Python? I remember you
  said you code in it." → one click → done.)

**Writes:**
```yaml
# ~/.config/prime/identity.yaml (appended)
projects:
  languages: [python, javascript]
  creative: [3d-printing]
  deferred: [java, video-editing]
```

**If skipped:** Nothing installed. Deferred setup still works — Prime infers
from file extensions and offers to set things up on first encounter.

---

### Beat 4 — How do you like your machine

**Prime says:** "Last few preferences — pick what feels right."

**UI:** A compact settings panel (not a list of questions):

| Setting | Control | Default |
|---|---|---|
| Desktop session | Toggle: "Desktop" (KDE) / "Prime" (Hyprland) | Desktop |
| Appearance | Toggle: Light / Dark | Dark |
| Prime speaks out loud | Toggle: Yes / No | No |
| Quiet hours | Time range picker | 22:00–08:00 |
| Text size | Slider: normal / large / huge | normal |
| Reduce motion | Toggle | off |
| Colour-blind-safe palette | Toggle | off |
| Screen reader (Orca) | Toggle + start | off |
| How much should Prime do on its own? | Slider: "Ask me first" ← → "Just do it" | Ask me first |

Accessibility is a first-class beat, not an afterthought: colleges issue
accommodation letters, and a student who can't read the screen has no path back
through a settings menu they can't see. All four settings write through to the
desktop's real accessibility switches (KDE and Hyprland both), and the interview
must be navigable by keyboard alone from the first frame.

The autonomy slider maps directly to the capability ladder from ARCHITECTURE.md
§4:
- **Ask me first** (default) → all capabilities at `suggest`. Prime tells you
  what it would do and waits for approval.
- **Middle** → user-space actions at `auto`, system-level at `approve-each`.
- **Just do it** → everything at `auto` except destructive verbs, which stay at
  `approve-each` always.

**On answer:** If the user picks Dark, the desktop theme switches *right now* —
they see it happen. If they pick Hyprland, the panel notes "The Prime session
will be available at your next login." If they toggle voice on, Prime says
"Hello, [name]" out loud.

**Writes:**
```yaml
# ~/.config/prime/identity.yaml (appended)
preferences:
  session: desktop       # or "prime"
  theme: dark
  voice: false
  quiet_hours: "22:00-08:00"
  autonomy: suggest      # or "auto-user" or "auto-all"
```
```
~/.config/prime/capability-ladder.yaml   (generated from autonomy level)
```

**If skipped:** All defaults. KDE, dark, no voice, suggest-mode. Changeable
anytime ("Prime, switch to dark mode" / "Prime, stop asking before installing
apps").

---

### Beat 5 — Connect me

**Prime says:** "To have a real conversation with you — help with homework,
explain things, remember what we talked about — I need an AI account. Paste an
API key below, or skip this and I'll work in offline mode."

**UI:**
- Provider dropdown: OpenAI, Anthropic, Google (Gemini), DeepSeek, "Other
  (OpenAI-compatible endpoint)"
- API key paste field (masked, never logged, never transmitted except to the
  chosen provider)
- A small "What's an API key?" help expander with a 3-sentence explanation and
  a link to each provider's key page
- "Test connection" button → on success, a green check; on failure, a clear
  error

**On answer:** Key is written to a 0600-permission file in the user's home. Prime
confirms: "Connected. I'm using [provider] — you can change this anytime." The
spend cap is set to a default ($5/month) and shown: "I'll let you know when
you're approaching your limit."

**Writes:**
```
~/.config/prime/provider.yaml            (provider name, endpoint, model)
~/.config/prime/secrets/api-key          (0600, the actual key)
~/.config/prime/spend-cap.yaml           (monthly limit, current usage)
```

**If skipped:** Prime runs in script-only mode. Health checks, updates,
rollback, reminders, file scaffolding — all work. Conversation, coursework
help, novel reasoning — unavailable, and Prime says so honestly: "I can keep
your machine healthy, but I can't help with homework until you connect an AI
account." The "Connect" option lives in the Prime settings panel permanently.

---

### Beat 6 — Anything else

**Prime says:** "Anything else I should know about you? Type whatever you
want — hobbies, goals, how you learn best, things that annoy you. This goes
into my memory and I'll use it to be more useful. Or just hit Done."

**UI:** A large freeform text area. No structure, no parsing hints. Whatever the
user types goes into the memory seed verbatim, to be consolidated by the agent
over time.

**On answer:** The text is appended to the identity seed's freeform section. Prime
confirms: "Got it. I'll keep this in mind."

**Writes:**
```yaml
# ~/.config/prime/identity.yaml (appended)
freeform: |
  I learn better with examples than explanations. I hate being talked at
  in long command lists. I play games on Steam. I want to learn
  to use the terminal but I don't know where to start.
```

**If skipped:** Freeform section is empty. Prime learns from interaction instead.

---

## After the interview

When the user clicks "Done" (or skips to the end), Prime:

1. **Assembles the memory vault.** The identity seed
   (`~/.config/prime/identity.yaml`) is the structured data; the freeform
   section is the unstructured data. Together they become the initial
   `~/.config/prime/memories/USER.md` — the file Prime reads at the start of
   every session, the equivalent of Hermes's `~/.hermes/memories/USER.md`.

2. **Writes dotfiles.** Based on the session choice and theme:
   - KDE → apply dark/light Plasma global theme (scripted, not a model call)
   - Hyprland → write `~/.config/hypr/hyprland.conf`,
     `~/.config/waybar/config`, `~/.config/waybar/style.css`,
     `~/.config/kitty/kitty.conf` from templates, themed to match.

3. **Starts the agent service.** If an API key was provided,
   `prime-agent.service` (user) starts — the always-on supervisor. If not, only
   the health-check timer and update-watcher start (scripts, no model).

4. **Shows a summary.** A final panel:
   ```
   ✓ Machine: healthy (AMD Ryzen 7, 16 GB, 460 GB free)
   ✓ Desktop: KDE Plasma, dark theme
   ✓ Courses: MATH-1010, ENGL-1100, COLL-1000 → ~/College/Autumn-2026/
   ✓ Apps: LibreOffice, Obsidian, Firefox, Terminal
   ✓ AI: Connected (DeepSeek) · Budget: $5.00/month
   ✓ Autonomy: Ask me first
   
   Say "Hey Prime" or press Super+R any time.
   ```

5. **Closes the interview UI.** The desktop appears. The interview is over.

### The gap that is still open: backups

Everything above sets up a nice machine. None of it protects a term paper. For a
student, `~/College/` is the only thing on the disk that cannot be reinstalled
from a recipe, and an atomic base will happily survive a bad update while the home
directory quietly dies with the drive.

This needs to land before the first ISO ships to anyone else, and it is a
supervisor duty rather than a beat: after the interview, Prime offers a backup
destination (external drive when one is plugged in, or a folder the user already
syncs), keeps a scheduled copy of `~/College/` and `~/.config/prime/`, and reports
in plain language when a backup hasn't happened in a while. It should never be a
hard sell, and never a paid cloud: a silent local copy plus one honest reminder
beats a subscription.

**Not cheap on the shipped product:** this was written when the base was Fedora's
Aurora image, which ships `restic`, `rclone` and `DejaDup` already. The layer that
actually ships (CachyOS + `install.sh`) does not install any of the three — none
are in `os/arch/packages.txt` — so this beat needs a packaging step, not just
configuration and wording. Once packaged, Prime should drive `restic` (snapshot +
prune policy) with `rclone` as the optional off-machine target, and leave DejaDup
alone for users who prefer a GUI.

---

## What happens when someone says "actually, change that"

Every beat's output is a file the user (or Prime) can edit later:

| "Change my…" | Prime edits | Mechanism |
|---|---|---|
| name, pronouns | `identity.yaml` | instant, no restart |
| courses | `identity.yaml` + `~/College/` dirs + reminders | scaffolding is additive; old dirs are kept |
| theme | `identity.yaml` + KDE/Hyprland theme files | instant toggle, same as the interview |
| autonomy level | `capability-ladder.yaml` | takes effect on next Prime action |
| API provider | `provider.yaml` + `secrets/api-key` | reconnects on save |
| voice on/off | `identity.yaml` | instant |
| quiet hours | `identity.yaml` | instant |
| anything in freeform | `identity.yaml` freeform section | appended or rewritten by conversation |

The interview is not a one-time event. It's the initial population of a set of
user-owned, human-readable config files that Prime consults on every turn and
that the user can edit with a text editor if they want to.

---

## Beats 7–13: the deep surface

Beats 1–6 make a working machine. Beats 7–13 make it *their* machine, and they are
the reason the interview is the product rather than a form. Every one of these is a
real choice a person can have an opinion about, so Prime asks — but it never asks
blind (see the asking policy below).

### Beat 7 — How the desktop behaves

Prime says: *"Last big one — how do you want the desktop itself to work?"*

| Choice | What it means | Suggested when |
|---|---|---|
| **Prime** (Hyprland) | keyboard-driven tiling, workspaces, hotkeys, voice-first | the user codes, or asks for "fast", or picks it deliberately |
| **Familiar** (KDE, Windows-like) | taskbar, start menu, minimise buttons — what most people already know | the user is not technical (default) |
| **Ubuntu-like** | dock on the left, top bar, app-grid launcher | the user has used Ubuntu or a school Linux box |
| **Minimal** | one panel, no dock, no desktop icons | the user asks for "nothing in my way" |

The choice renders **live**: the panel switches while they are still looking at it,
on a preview desktop, before it is applied for real. Nobody has to imagine what
"tiling" means — they see two windows snap into place.

Switching later is one command and loses nothing; this is a preference, not an
identity.

### Beat 8 — Look: theme, colour, wallpaper, type

- **Theme family** — suggested from the monitor's colour profile and the lighting in
  the room if a webcam exists, otherwise dark (default).
- **Accent colour** — 8 swatches plus "pick anything" (colour wheel).
- **Wallpaper** — generated options, a folder of choices, or "use my photo".
- **Fonts and text size** — previewed live in a sample paragraph, not described.
- **Density** — compact vs comfortable rows, spacing of the interface.
- **Logo/motd** — which Prime mark shows in the terminal (`logo-block.txt`, the
  P.R.I.M.E lettering, or none). Themed so it is not a sticker on top of a wardrobe.

### Beat 9 — Keyboard and hotkeys

Prime reads the layout from the system, then shows a **binding sheet** and asks
what to change. The suggested set is the Prime preset, which is the set already
proven on the author's machine:

| Key | Action |
|---|---|
| Super+R (hold) | push-to-talk — the assistant listens while held, sends on release |
| Super+R (tap) | typing box — same bar, keyboard instead of voice |
| Print | snip a region → annotate sheet |
| Shift+Print | full screen | 
| Super+Print | focused window |
| Alt+Print | the monitor under the pointer |
| Super+Alt+A | snip region → "what is this?" |
| Super+Return | terminal | 
| Super+Q | close window | 
| Super+1..9 | workspace |

Honest rule: hotkeys that could collide with an application or an accessibility
feature are listed with their collision, not silently taken.

### Beat 10 — Terminal and tools

Shell (fish/zsh/bash, suggested from what they already type), prompt theme, editor,
file manager, and the package strategy: **flatpak first, `brew` for CLI tools,
containers for dev, system packages last** — because that is the order that cannot
break the machine. The user is told the difference in one sentence:

> *"Apps install instantly. System-level things need a rebuild and a reboot, and I
> can roll those back. That is why I do it in that order."*

### Beat 11 — Voice

Off by default: nobody should be surprised by a machine that talks.

- **Push-to-talk key** (default Super+R, hold to talk, release to send).
- **Voice** — a small menu of installed voices, each previewed in one sentence so
  they can hear it rather than read a name.
- **Style** — pace, warmth, how much it says. The default is *"one or two sentences
  when something finishes or needs a decision; full detail in the transcript"* —
  a voice that reads an essay aloud is a voice people switch off.
- **Ducking** — lower other audio while Prime speaks (never mute it), so it works
  over music.
- **Quiet hours** — when Prime will not speak, only write.
- **Spoken-language lock** — the voice speaks one language, chosen here, and never
  guesses per token. (Hard-won: a multilingual voice reading maths symbols aloud in
  a random language is a bug people experience as "the assistant is broken".)

### Beat 12 — How the assistant behaves

| Capability | Asked as | Default |
|---|---|---|
| **Snip & ask** | "want screen capture on a hotkey?" | on |
| **Tutor mode** | "should I teach or just answer?" | teach for coursework, answer elsewhere |
| **Whiteboard** | "want a board app I can draw on with you?" | on for students |
| **Study tracker** | "want me to keep your term organised?" | on if courses were entered |
| **Web + research** | "may I look things up for you?" | on |
| **Self-improvement** | "may I review my own mistakes and change how I work?" | on, with a weekly summary of what it changed |
| **Read scope** | "which folders may I look at without asking?" | home only; everything else asks each time |
| **Spending** | "what's the most I should ever spend in a month?" | a hard number, shown back |

### Beat 13 — Memory and the record

This is what makes it feel like the same assistant in month six:

- **Everything is documented.** Every conversation, every command Prime runs,
  every change it makes — appended to a local, human-readable log
  (`~/.config/prime/audit.jsonl` for actions, the session archive for talk). Not
  telemetry: it never leaves the machine, and the user can read or delete any of it.
- **Memory has two speeds** — a small curated set of facts that is always in mind,
  and a searchable archive of everything else. Prime is told, in words, the
  difference: *"I always remember a few things about you; I can look up the rest."*
- **Patterns become defaults.** If they always decline the same suggestion, Prime
  stops making it. If they always change one setting back, Prime changes its
  suggestion. This is recorded as a preference, not inferred silently.
- **Patterns get reviewed out loud** — a weekly digest: what Prime learned, what it
  changed about itself, what it wants to ask next. One screen, dismissible, and the
  user can strike anything from it.
- **Forgetting is a feature.** "Forget that" and "forget everything after a date"
  are real commands, and they work.

---

## The asking policy

The author's framing: *ask every customizable option Prime feels the user would want to
know about, but make suggestions and learn off the answer patterns.* Made concrete:

1. **Ask about anything a person could reasonably have an opinion about.** Opinion
   is the test, not complexity.
2. **Never ask what can be observed.** Screen size, GPU, keyboard layout, locale,
   printer presence: detect, then *state what was detected* — confirm, don't quiz.
3. **Every question arrives with a suggestion and a reason.** *"Dark theme — it
   matches your monitor and it's 11pm."* A question without a recommendation wastes
   the user's attention.
4. **One question, one decision.** No compound questions, no menus inside menus.
5. **Skip is always available and always free.** Every beat has a working default,
   and "later" is a valid answer that is honoured by not asking again that session.
6. **Answers become data, not instructions.** Each answer is written to a file, and
   the *deviations* from Prime's suggestions are what get remembered: accepting a
   suggestion is a weak signal, overriding one is a strong signal.
7. **Learn the pattern, then stop asking.** After a few consistent answers, Prime
   proposes the new default instead of asking again — and says so: *"I've noticed
   you always want the terminal maximised, so I've started doing that."*
8. **Never ask twice about the same thing.** If it was answered, it is a preference
   from then on, and changing it is a conversational edit rather than a wizard.
9. **Depth on request, not by default.** The full list of options is available on
   demand ("show me everything") for the user who wants to go deep — that is a
   different person from the one who wants to be done in five minutes, and the
   interview must serve both without making either sit through the other.
10. **The interview never ends.** Beats are re-runnable one at a time, forever,
    by voice: *"Prime, I want the Prime session instead"* re-runs Beat 7.

---

## The power preset

For the author's own machine, the interview collapses to one answer: every beat
described above already exists and works — push-to-talk on Super+R, snip on Print
and friends, a whiteboard service, a study dashboard, the activity timeline logging
every move, an academic tutor persona, and an archive of every past conversation
that can be searched. In the distro this is packaged as **"set it up like mine"** —
one choice on Beat 7 that answers Beats 7–12 at once, and every individual beat
stays editable afterwards.

That preset is also the honest demo: it is a working reference implementation of
the whole idea, not a design document.

---

## Implementation plan

### Phase 1 — Script-only interview (no model required)

The interview is a **Hermes Desktop route** (`ROUTES_AREA` + a sidebar nav row),
backed entirely by shell scripts and YAML:

| Piece | File | State |
|---|---|---|
| Hardware probe | `files/system/usr/libexec/prime/hw-probe.sh` | written, runs in ~0.2s, degrades cleanly with missing tools |
| Identity schema | `docs/schemas/identity.schema.json` | written, validated against the example below |
| Seed template | `templates/identity.example.yaml` | written, validates |
| Permission model | `templates/capability-ladder.yaml` | written |
| Beats 1–6 writers | `files/system/usr/libexec/prime/beat-*.sh` | not written yet |
| The desktop route | `desktop-plugins/prime-setup/plugin.js` | not written yet |

The route:
- Runs the hardware probe script
- Presents the six beats as a scrollable single-page panel
- Writes the output files
- Triggers Flatpak installs and Distrobox container creation
- Does NOT require an AI model — this is pure UI + scripting

This is buildable now, testable in a VM, and ships with the first ISO.

### Phase 2 — Agent-narrated interview

Once the agent runtime (`prime-agent.service`) exists:
- Prime narrates the interview (voice optional) — reads the hardware results
  aloud, comments on the courses, suggests apps based on answers
- The structured output is the same; the agent just makes the experience warmer
- Falls back cleanly to Phase 1 if no API key is available yet (since the key
  question is Beat 5, the agent can narrate Beats 1–4 using whatever model
  is available, or run the whole thing as the scripted version)

### Phase 3 — Continuous interview

The interview never formally ends. "Prime, I just enrolled in a spring course"
triggers the courses beat again. "Prime, I want to try the tiling session"
triggers the session toggle. The six beats become six sections of a persistent
settings surface that Prime can also drive conversationally.

---

## Files this document specifies

```
~/.config/prime/
  identity.yaml              # structured seed: name, courses, projects, prefs
  hardware.json              # hardware probe results (auto-generated)
  capability-ladder.yaml     # permission levels per capability
  provider.yaml              # AI provider config
  secrets/
    api-key                  # 0600, the user's API key
  spend-cap.yaml             # monthly model budget
  reminders.yaml             # class schedule → reminders
  memories/
    USER.md                  # the "soul" file — assembled from identity.yaml
    MEMORY.md                # episodic memory (grows over time)

~/College/
  <term>/
    <course-code>/
      notes/
      assignments/
      essays/                # (if writing-heavy course)

~/College/dashboard/
  studyhub-data.json         # StudyHub initialization data
```

```
/usr/libexec/prime/
  hw-probe.sh                # hardware detection (deterministic, no model)
  firstboot.sh               # existing: skeletal setup, marker file
  interview-ui               # the GTK4/Electron interview application
```
