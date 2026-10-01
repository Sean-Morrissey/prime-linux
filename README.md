# Prime Linux

A student-first, atomic Linux desktop that ships with a resident AI agent.

Status (2026-10-01): **Prime Linux installs onto CachyOS with a few copy-paste commands** (below).
The image/ISO work further down is the longer road and is not needed to try it.

## Install (on CachyOS)

You need a computer with **CachyOS** installed (any edition; KDE Plasma is a good
pick and stays on the login screen as a second choice) and an internet connection.
New to Linux? The **[user guide](docs/USER-GUIDE.md)** walks through installing
CachyOS too.

Open a terminal (press the Windows key, type `terminal`, press Enter), then follow
**A** or **B**, depending on whether the Prime Linux repository is private or public.
Copy each grey box, paste it into the terminal with **Ctrl+Shift+V**, and press Enter.
When it asks for your password, type it (nothing shows while you type) and press Enter.

### A. The repository is private (you were added as a collaborator)

1. Accept the invitation: open the email from GitHub ("…invited you to collaborate
   on Sean-Morrissey/prime-linux") and click **View invitation → Accept**. You need a
   free GitHub account for this.
2. Install GitHub's sign-in tool:

   ```bash
   sudo pacman -S --needed --noconfirm github-cli git
   ```

3. Sign in to GitHub from this computer:

   ```bash
   gh auth login
   ```

   Answer its questions with the arrow keys and Enter:
   **GitHub.com** → **HTTPS** → **Yes** (authenticate Git with your GitHub
   credentials) → **Login with a web browser**. It shows an 8-character code: press
   Enter, sign in to GitHub in the browser that opens, and type the code there.
4. Download Prime Linux:

   ```bash
   gh repo clone Sean-Morrissey/prime-linux ~/prime-linux
   ```

5. Install it:

   ```bash
   bash ~/prime-linux/install.sh
   ```

### B. The repository is public

One line does everything:

```bash
curl -fsSL https://raw.githubusercontent.com/sean-morrissey/prime-linux/main/boot.sh | bash
```

### Then, either way

- The installer shows numbered steps `[1/8] … [8/8]` and takes 5–15 minutes. It ends
  with **Prime Linux is installed**.
- **Log out** (or restart), choose **Prime** in the login screen's session menu, and
  log in. You get the top bar, the **P** logo (click it for the Start menu), and:
  **Super+Space** search · **Super+Alt+Space** the Prime menu · **Super+/** every
  shortcut. (*Super* is the Windows key.)
- If anything stops half-way, run the install command again (A: step 5, B: the
  one line): it carries on where it stopped. The log is in `~/.local/state/prime/logs/`.
- **Updates:** Prime menu → Update → **Update everything**.
- **Changed your mind?** In a terminal: `prime-uninstall` puts the computer back as it
  was (from KDE's Konsole: `~/.local/share/prime-linux/layer/bin/prime-uninstall`).
- The downloaded `~/prime-linux` folder (option A) can be deleted after installing;
  Prime keeps its own copy in `~/.local/share/prime-linux`.

### For the owner: giving Prime Linux to a friend

- **Private repo:** on GitHub open the repository → **Settings → Collaborators → Add
  people**, and enter your friend's GitHub username or email. On a personal account a
  collaborator can also push to the repo, so only invite people you trust with that.
  Send them this README's option **A**.
- **Public repo:** nothing to do; send them option **B**. Making the repository public is
  your call (Settings → General → Danger Zone → Change visibility); nothing in Prime
  does it for you.

The installer checks the computer first (internet, disk space, which desktop is
already there), shows numbered progress, logs to `~/.local/state/prime/logs/`,
picks up where it stopped if interrupted, and `bash install.sh --dry-run` shows
exactly what it would do. `prime-uninstall` puts everything back.

- New to Linux? **[docs/USER-GUIDE.md](docs/USER-GUIDE.md)** — install to everyday use.
- How the layer is built: [docs/PRIME-LAYER.md](docs/PRIME-LAYER.md) ·
  what it does vs Omarchy: [docs/PARITY.md](docs/PARITY.md) ·
  releases and channels: [docs/RELEASE.md](docs/RELEASE.md)
- Tests: `tests/install-in-container.sh` (clean Arch container, install +
  uninstall) and `tests/vm/run.sh all` (real CachyOS VM boot, screenshot).

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

Prime Linux is a **custom image built on an atomic Fedora base** (Aurora / KDE via
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

1. **Bootable base** — Aurora base, rebranded, stock install works from ISO. ← *we are here*
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
