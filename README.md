# Prime Linux

A student-first, atomic Linux desktop that ships with a resident AI agent.

Status: **skeleton** — recipe, build pipeline, and first-boot scaffold are in place.
First milestone is a bootable ISO built from this repo.

---

## The idea

**Prime is not an app inside this distro. Prime is the supervisor of this distro.**

You install it, you talk to Prime, you tell it who you are, what you're studying,
what you're building, how you like your machine — and Prime does the setup: your
dotfiles, your term scaffolding, your apps, your reminders. It stays on. It watches
updates, it notices when something broke, it rolls it back, and it explains itself
in plain language. The terminal is still right there when a human wants to type.

Full design: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

---

## What makes it different

Every other distro treats AI as an app you install and launch. Every other distro
gives you a desktop and wishes you luck. Prime Linux is built the other way around:

| | Ordinary distro | Prime Linux |
|---|---|---|
| AI assistant | an app in the launcher | the OS supervisor — hotkey voice, screen-aware, remembers you across reboots |
| First run | a stack of forms | a conversation: tell Prime about yourself and it configures the machine |
| A broken update | you fix it, or reinstall | update is one image; pick the previous one at boot and you're back |
| Self-diagnosis | none | Prime runs the health check, reports in plain language, rolls back |
| School | generic | semester scaffolding, study dashboard, math practice, whiteboard, notes/citations/PDF stack |
| Desktop | one size fits all | two sessions at login: "Desktop" (KDE) for normal people, "Prime" (Hyprland) for power mode |

The one-line pitch: **the first desktop that knows you, sets itself up for you, and
fixes itself when updates go wrong.**

The differentiator is *not* the desktop theme. People make tiling-WM rices every
day. The differentiator is an agent that has hands on the machine — and a
machine that can always be rolled back.

---

## How it works

Prime Linux is a **custom image built on an atomic Fedora base** (Bazzite / KDE via
Universal Blue) using [BlueBuild](https://blue-build.org). You do not fork a
distro from scratch — you declare a recipe, CI builds it, and the recipe plus the
base's package stream *is* your distro.

```
GitHub repo (this)          GitHub Actions             You / your buddy
  recipes/recipe.yml   ->   blue-build/github-action -> ghcr.io/<user>/prime-linux
  files/system/**                                        |
                                                         +-> `bluebuild generate-iso`  -> bootable USB
                                                         +-> daily upstream rebuild   -> automatic updates
```

Why atomic is the whole point for a beginner:

- **Updates are all-or-nothing.** Either the new image boots, or you pick the old
  one in the boot menu. No half-upgraded system, no broken login manager.
- **The OS is read-only where it matters.** A newbie can't `rm -rf` their way into
  a reinstall.
- **Your layer is thin.** Fedora and Universal Blue carry drivers, firmware,
  codecs, kernel. This repo only carries what makes it *Prime*.

---

## Layout

```
recipes/recipe.yml          # the whole OS definition: base, packages, apps, units
.github/workflows/build.yml # CI: builds the image daily -> ghcr.io
docs/                       # ARCHITECTURE (design of record), INTERVIEW, PITCH
docs/schemas/               # JSON Schema for the user-owned config files
templates/                  # identity seed + capability ladder, ready to validate against
files/system/               # everything here is copied over /
  usr/lib/os-release        #   rebranding
  usr/libexec/prime/hw-probe.sh          # hardware probe, no model call, ~0.2s
  usr/libexec/prime/firstboot.sh
  usr/lib/systemd/system/prime-firstboot.service
files/scripts/              # build-time scripts (optional)
modules/                    # custom BlueBuild modules (optional)
```

---

## Build it

```bash
# one-time: create a GitHub repo from this directory, let Actions build it
gh repo create prime-linux --public --source=. --push

# locally, once you have an image published:
sudo bluebuild generate-iso --iso-name prime-linux.iso \
  image ghcr.io/<your-user>/prime-linux
```

Signing: generate a cosign keypair (`cosign generate-key-pair`), add the private key
as the `SIGNING_SECRET` repo secret, commit the public key as `cosign.pub`.

---

## Roadmap

1. **Bootable base** — Bazzite base, rebranded, stock install works from ISO. ← *we are here*
2. **Two sessions** — "Desktop" (KDE, default) and "Prime" (Hyprland) at login.
3. **The interview** — first-boot conversation that personalizes the install
   (identity, courses, projects, apps, dotfiles, memory seed).
4. **Supervision** — update watcher, post-update health check, guided rollback,
   plain-language reports, activity audit log.
5. **Student layer** — StudyHub, term scaffolding, whiteboard, math practice.
6. **Always-on** — voice service, reminders, spend cap, permission ladder UI.
7. **Polish** — logo, wallpaper, Plymouth splash, installer branding, `prime` CLI.

---

## Rules we hold to

- **Never ship secrets.** No API keys in the image, ever. First boot asks the user;
  keys live in their home directory only.
- **The agent runs with guardrails on someone else's machine.** Approval prompts on
  destructive commands, cost caps on model calls, and a "student" profile that is
  more restrictive than the owner's. Design this before shipping it to a friend.
- **Rebrand properly.** A modified Fedora must not carry Fedora trademarks; this
  image is `ID=primelinux`, `ID_LIKE=fedora`. Keep upstream licenses intact.

---

## Not in scope

Writing a distro from source (bootloader, kernel, installer, package archive) —
that is a multi-year project with a volunteer team. Prime Linux is a *derivative
image*, which is how Bluefin, Bazzite, and Aurora are all shipped, and it gets the
same result: your own OS, your own ISO, your own update channel.
