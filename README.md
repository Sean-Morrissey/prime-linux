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
   sudo pacman -Syu --needed --noconfirm github-cli git
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
  **Super+Space** search · **Super+I** Settings · **Super+/** every
  shortcut. (*Super* is the Windows key.)
- If anything stops half-way, run the install command again (A: step 5, B: the
  one line): it carries on where it stopped. The log is in `~/.local/state/prime/logs/`.
- **Updates:** Settings → Updates → **Update everything**.
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

How the layer that ships today is put together: [`docs/PRIME-LAYER.md`](docs/PRIME-LAYER.md).
The original design document (an atomic-image track, parked — see the note at its
top): [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

---

## What makes it different

Every other distro treats AI as an app you install and launch. Every other distro
gives you a desktop and wishes you luck. Prime Linux is built the other way around:

| | Ordinary distro | Prime Linux |
|---|---|---|
| AI assistant | an app in the launcher | can be the OS supervisor — hotkey voice, screen-aware, remembers you across reboots (your choice, step 5 of first run — your own key, nothing sent until you connect one) |
| First run | a stack of forms | a conversation: tell Prime about yourself and it configures the machine |
| A broken update | you fix it, or reinstall | a snapshot is taken first; pick the previous one in the boot menu and you're back |
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

Prime Linux is **a layer on top of a stock CachyOS install**, added by `install.sh`
(one command, see above) — not a separate OS image you flash. You keep CachyOS's
own installer, kernel, drivers and rolling updates; this repo adds the Hyprland
"Prime" session, the resident agent, the desktop tooling and the supervisor on top
of your existing account.

```
GitHub repo (this)           install.sh / boot.sh            Your account
  layer/bin/*            ->   clones to ~/.local/share/   ->  ~/.config/hypr, waybar,
  layer/default/*             prime-linux, then seeds          kitty, systemd units,
  os/arch/packages.txt        + links into your account        a Prime session at login
```

There is no separate build step: `prime-update` is just `git pull` plus re-running
the relevant installer steps. Why this is still safe for a beginner, without an
atomic image:

- **Nothing of yours is touched without a backup.** Anything `install.sh` would
  replace is copied to `~/.config-backups/` first; `prime-uninstall` reverses the
  whole thing.
- **System updates snapshot first.** CachyOS's default btrfs + snapper +
  limine-snapper-sync means every pacman transaction gets a boot-menu entry; a bad
  update is "pick the older entry," not "chroot and pray."
- **Your layer is thin.** CachyOS carries the kernel, drivers, firmware and the
  rolling package stream; this repo only carries what makes it *Prime* — a few
  dozen scripts and config files under `layer/`.

An atomic-image version of this same idea (an immutable Fedora base, an update as
a whole new bootable image) was the original design and is parked, not deleted —
see the note at the top of [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) and §9
there ("Base-agnostic supervision") for how the two could coexist later.

---

## Layout

```
install.sh  boot.sh              # the installer (see "Install" above)
layer/
  bin/                           # every prime-* command (bar widgets, menus, theme, doctor, update…)
  default/                       # Prime's defaults: hypr/, waybar/, rofi/, swaync/, kitty/, menu.json
  seed/                          # files copied into ~/.config ONCE (the user's own from then on)
  addons/<gaming|coding|creator|student|ai>/   # optional packs, enabled with prime-addon
  migrations/<unix-time>.sh      # safe-to-run-twice fixes for existing installs
os/arch/packages.txt             # official-repo packages only — no AUR needed
backends/arch/                  # the update/rollback supervisor (prime-autoupdate) — source of truth,
                                 #   synced into files/system/ for the parked image track
docs/                            # PRIME-LAYER (what ships today), USER-GUIDE, RELEASE, ARCHITECTURE (parked design)
tests/                           # tests/check-*.sh, tests/install-in-container.sh, tests/vm/
```

---

## Roadmap

1. **Packs** — `gaming`, `coding`, `creator`, `student` on the add-on system (the
   `ai` add-on already ships). Each pack is `addon.conf` + menu rows + binds.
2. **Nightly updates for everyone** — `prime-autoupdate`'s check → snapshot → apply
   → health → rollback cycle, on by default from the installer.
3. **Conversational customisation** — the AI add-on gets a fixed toolbox (theme,
   addon, bind, setting, update, doctor, restore) instead of a shell, gated by
   `templates/capability-ladder.yaml` and logged.
4. **Security defaults** — firewall on by default, automatic security updates,
   signed releases of the layer (see [docs/RELEASE.md](docs/RELEASE.md)).
5. **First-run interview** ([docs/INTERVIEW.md](docs/INTERVIEW.md)) as the front
   door: picks packs, theme, autonomy level and update policy.

Full detail and current status: [docs/PRIME-LAYER.md](docs/PRIME-LAYER.md).

---

## Rules we hold to

- **Never ship secrets.** No API keys anywhere in the layer, ever. First boot asks
  the user; keys live in their home directory only, `0600`.
- **The agent runs with guardrails on someone else's machine.** Approval prompts on
  destructive commands, cost caps on model calls, and a "student" profile that is
  more restrictive than the owner's. Design this before shipping it to a friend.
- **Never overwrite a user's own files.** Defaults live in `layer/default/`; the
  user's own config always loads last and always wins — see
  [docs/PRIME-LAYER.md](docs/PRIME-LAYER.md)'s layer table.

---

## Not in scope

Writing a distro from source (bootloader, kernel, installer, package archive) —
that is a multi-year project with a volunteer team. Prime Linux is a layer on top
of CachyOS, not a fork of it: your own account, CachyOS's own update stream, and
this repo's `layer/` on top.
