# Prime and Hermes: who does what

*P.R.I.M.E — Please Relax, I'll Manage Everything.*

The model is Siri as it was first pitched: you don't talk to a search engine, a
speech recogniser and a set of apps. You talk to Siri, and Siri takes care of it.
On this computer, the one you talk to is **Prime**. Everything else is plumbing,
and plumbing has no name on screen.

## The four parts

```
 you ──▶  PRIME, the face          Spotlight (Super+Space) · Ask box (Super+Shift+Space)
          one name, one voice      Snip · notifications · Settings (Super+I) · Prime menu
              │
              ├─▶ 1. PRIME'S HANDS   no AI: prime-do (everyday requests in plain words)
              │                      prime-settings (the toolbox: checked, logged, undoable)
              │                      the Settings app, prime-theme, prime-toggle…
              │
              ├─▶ 2. THE BRAIN       optional (the AI pack): Hermes or any OpenAI-compatible
              │                      model. Only asked when the hands don't already know.
              │                      It can only act through the toolbox, never a shell.
              │
              └─▶ 3. PRIME CARE      no AI, runs by itself: nightly updates (with a snapshot
                                     first), the daily checkup, Check and fix (doctor),
                                     File History, the safety check, signed releases.
                                     It keeps Prime working on top of CachyOS.
```

| Part | Has a name on screen? | Needs AI? | Can change the system? |
|---|---|---|---|
| Prime (the face) | **Prime** — the only one | no | only through its hands |
| Prime's hands | no ("Prime did it") | no | yes: each change is checked, logged, undoable |
| The brain (Hermes, or another model) | **never** | yes | only by asking the hands, within the permission level in Settings → AI Assistant |
| Prime Care | no ("Prime updated your computer") | no | yes, as root, from root-owned copies only |

### Prime, the face

One name, one voice, everywhere. Short sentences in plain words. It says what it
did, not how. It never shows a model name, a provider, an error code or a
terminal on the everyday path (Settings → AI Assistant is the one place a model
is named, because that is where you choose it).

### Prime's hands (no AI)

`prime-do` holds the everyday requests — "wifi off", "louder", "mute", "do not
disturb", "bigger text", "accent blue", "mouse settings", "take a screenshot",
"something's wrong", "get a file back", "empty the trash", "update". Spotlight
shows them first, under **Do it**, and when every word was understood it is the
Top Hit: Enter does it. The Ask box tries them before the model, so these work
the same with or without the AI pack, offline, instantly, and the same way every
time. Anything that can't be undone with a click (restart, shut down) only ever
opens the power menu.

The toolbox (`prime-settings`) is the only way anything — the brain included —
changes Prime's settings: each change is checked against the permission level,
backed up, written to the log in plain words, and undoable.

### The brain (optional)

The AI pack connects a model: on this computer, on another one at home, or a
service. **Hermes**, the agent this project grew out of, is one such brain: its
memory and skills make it the best one to use when it is installed. Whatever the
brain is, it is reached only when the hands don't know the request, it answers
*as Prime*, it can act only through the toolbox, and its own name never appears.
Personalities (pirate, kawaii…) don't exist for Prime: one voice.

### Prime Care (no AI)

The part that runs by itself and keeps Prime working with the base system
(CachyOS): the nightly updater with a snapshot first and undo, the daily checkup
that only speaks up about something new, Check and fix, File History, the
safety check, signed releases and the weekly installer watch. None of it needs
the AI pack, and none of it runs anything from a home folder as root.

## How a request travels

1. **Spotlight / the Ask box** gets the words.
2. **prime-do** — a known request, every word understood? Do it, say one line. Done.
3. **Apps, settings, files** — Spotlight shows them; Enter opens.
4. **The brain** (with the AI pack) — the question goes to the model, which answers
   in Prime's window and may propose a change through the toolbox.
5. **No brain** — the last row searches the web.

## Screenshots: capture never asks

Print Screen or Super+Shift+S: drag, and the picture is saved and copied. That is
the whole screen capture — nothing to choose. Then, like a Mac's thumbnail, a
notification offers what you might do next: **Edit · Ask Prime · Show in folder ·
Delete**. Ignore it and it goes away. Super+Alt+A (AI pack) is the one-step
version: capture, then Prime looks at it. Settings → Displays → Screenshots
chooses what happens after: show the buttons (default), just save and copy, or
always ask Prime.

## Rules for anything new

1. If it has a name on screen, the name is Prime.
2. Do first, talk second: a known request is done, then said in one line.
3. Nothing everyday needs AI. The AI pack makes Prime smarter, never required.
4. One question at most, and only for things that can't be undone.
5. A change goes through the toolbox (or Prime Care for the system), so it is
   logged and undoable.
6. A feature isn't finished until Prime Care can keep it working after a CachyOS
   update: package listed, service enabled, checked by the doctor, tested in the
   container and the VM. The `prime-integrator` agent (`.claude/agents/`) does
   that integration pass.

## What's next

- **Voice**: hold a key and speak to Prime (the push-to-talk scripts in the
  Hermes payload), routed through the same path: prime-do first, then the brain.
- **Hermes as the brain by default** when it is installed: point the AI pack at
  Hermes's local endpoint, if it offers an OpenAI-compatible one (to verify),
  so memory and skills come with it — still answering as Prime.
- **More of the hands**: every Settings page's switches as prime-do requests.
