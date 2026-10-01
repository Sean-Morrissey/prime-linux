# Prime Linux — red-team pass, October 2026

**Date:** 2026-10-01 · **Issue:** #4 · **Base:** `integrate/prime-layer` after PR #5
**Scope:** what a friend installs on a fresh CachyOS machine: `boot.sh`, `install.sh`,
`layer/` (desktop, commands, system pieces, add-ons), `prime-uninstall`, and the tests
that are meant to prove it. The bootc image track (`recipes/`, `os/`, `backends/`) was
covered by [RED-TEAM-REVIEW.md](RED-TEAM-REVIEW.md) and is only touched here where it
leaks into the desktop layer.

Three lenses, as the issue asked: **"Steve Jobs"** (product and first-run experience),
**"Bill Gates"** (platform, reliability, hardware variance), **"Linus Torvalds"** (code and
security). Severity: **P0** security hole, data loss or broken install · **P1** wrong for
most people who aren't the author, or a trap with no way out · **P2** real but narrow ·
**P3** polish.

Rules of evidence: every finding names a file and a concrete failure. "Fixed" means a
commit on this branch **and** a test that fails without it.

---

## Summary

| ID | Sev | Lens | Finding | Status |
|---|---|---|---|---|
| L1 | **P0** | Linus | SSH on + open to every network + passwords was only a "suggestion"; nothing at install or first login said so | **Fixed** + `tests/check-ssh.sh` |
| L2 | **P1** | Linus | sshd settings read wrongly: any `PasswordAuthentication no` anywhere counted, though sshd takes the *first* value (drop-ins first) | **Fixed** + test |
| L3 | **P1** | Linus | ufw app rules (`OpenSSH`) and commented rules were invisible to the report | **Fixed** + test |
| G1 | **P1** | Gates | Graphics right-click read `/sys/class/drm/card1` and `hwmon1` (the author's numbering) and asked about "an RX 9060 XT" | **Fixed** + `tests/check-portable.sh` |
| J1 | **P1** | Jobs | The P.R.I.M.E terminal greeting only appeared because the author's shell ran fastfetch; bash/zsh users never saw it | **Fixed** + `tests/check-greeting.sh` |
| G2 | **P1** | Gates | "Update everything" on a private-repo install without a GitHub login waited for a username inside a window that can't take one | **Fixed** + `tests/check-update-private.sh` |
| G3 | **P1** | Gates | None of the installer tests ran in CI: `tests/check-*.sh`, the container install and the VM test were run by hand only | **Fixed**: `.github/workflows/desktop-layer.yml` |
| G4 | **P1** | Gates | `tests/vm/run.sh all` stopped after a first ISO download (pipefail on an empty `grep -v`); OVMF and ImageMagick paths only matched Arch | **Fixed** |
| J2 | **P1** | Jobs | The VM test installed with its own commands, not the README's; it never opened the Start menu, Spotlight, Prime menu or greeting | **Fixed**: `tests/vm/desktop-checks.sh` |
| J4 | **P1** | Jobs | No "Prime" entry on the login screen until the first update, so the first-login health check flagged a problem on every fresh install | **Fixed** + container install/uninstall checks |
| J5 | P2 | Jobs | `prime-uninstall`, `prime-update`… gave "command not found" in a Prime terminal on bash (`~/.local/bin` not on PATH) | **Fixed** + `tests/check-greeting.sh` |
| G5 | P2 | Gates | `integrate/prime-layer`'s `install.sh` lacks main's three installer fixes (GPU by vendor id, `hardware.conf` kept, backup pointer) | Fixed in the main merge (step 4), not here |
| G6 | P2 | Gates | Add-on packs pick GPU drivers by name (`amd\|ati \|radeon`, `intel`), not PCI vendor id | Deferred: no real device string found that it gets wrong |
| L4 | P2 | Linus | `boot.sh` is `curl \| bash` from a moving branch, no signature or pin | Deferred: HTTPS from GitHub only; pinning to a tag needs releases (docs/RELEASE.md) |
| L5 | P3 | Linus | `boot.sh` re-run does `git checkout --force`, discarding local edits in `~/.local/share/prime-linux` | Deferred: by design (that copy is Prime's, not the user's); documented in README |
| J3 | P3 | Jobs | `templates/identity.example.yaml` uses the author's first name | Deferred: bootc-track template, never installed by `install.sh` |
| L6 | P3 | Linus | `prime-security:255` loops over a single quoted path (shellcheck SC2066) | Deferred: harmless, one file today |

Nothing found that `install.sh` does to **turn SSH on**: it isn't in the package list,
and the only code that enables `sshd` is `prime-security ssh on`, which a person runs
on purpose. `tests/check-ssh.sh` now fails if that ever changes.

---

## "Linus Torvalds" — code and security

### L1 · P0 · SSH open to the world, with passwords, and Prime shrugged
- **Where:** `layer/bin/prime-security` `ssh_status()` (before this branch).
- **Scenario:** the owner's live machine. `sshd` enabled, a ufw rule `22 ALLOW Anywhere`,
  stock Arch `sshd_config` (passwords on). The report said *warn* at most, and when ufw
  was off it said only "Remote login (SSH) is on". `prime-doctor --login` only notifies
  *bad* rows, so first login was silent. `prime-security apply` (run by the installer)
  printed "left as it is".
- **Fix:** `ssh_everyone()` treats "no firewall" as open; on + open + passwords is a
  **bad** row, so the first-login health check notifies. `apply` removes ufw rules that
  let anyone reach port 22 (numeric and the `OpenSSH` profile) and adds home-network rules
  instead, so nobody installing over SSH from home is cut off. It prints a warning when
  passwords are on. It never switches SSH off by itself: that could strand someone who
  administers the machine remotely; the fix is one command, `sudo prime-security ssh off`.
- **Test:** `tests/check-ssh.sh` (19 checks), including the owner's exact state.

### L2 · P1 · sshd's first-match rule ignored
- **Where:** `ssh_status()` grepped every config file for `PasswordAuthentication no`.
- **Scenario:** a drop-in says `yes`, the main file says `no` further down: sshd uses
  `yes`; Prime said "keys only". `KbdInteractiveAuthentication yes` (PAM password prompt)
  was ignored entirely.
- **Fix:** `ssh_passwords()` walks `sshd_config` in order, following `Include`, stopping at
  the first `Match`, first value wins, default `yes`.

### L3 · P1 · ufw rules the parser couldn't see
- **Where:** `ufw_rules()` required field 10 to be `in`.
- **Scenario:** `sudo ufw allow OpenSSH` writes `… 0.0.0.0/0 OpenSSH - in`; a commented
  rule writes `… in comment=…`. The first was invisible, so port 22 open to everyone via
  the app profile was reported as fine.
- **Fix:** look for the `in`/`in_<iface>` direction in any field after the addresses.

### Checked, nothing to fix
- Root never runs code from a home folder: the pacman hook and nightly updater are
  root-owned copies (`install-system.sh`), user work goes through `runuser` with a clean
  environment and `setsid` (TIOCSTI). Verified in `backends/arch/test-system-update.sh`.
- Fallback runtime dirs in `/tmp` check ownership and mode before use (`prime-menu`,
  `prime-context`).
- The AI key goes to curl on stdin, never argv (`prime-ai-setup:108`); the assistant
  changes things only through the `prime-settings` toolbox, checked against
  `~/.config/prime/capabilities.yaml`, never a shell (`prime-ask` docstring, tests in
  `layer/addons/ai/tests`). The add-on is off by default.
- `shellcheck -S error` over every shipped shell script: one finding (L6).

---

## "Bill Gates" — platform and reliability

### G1 · P1 · The author's GPU, hardcoded
- **Where:** `layer/default/elements.json` `bar.gpu`.
- **Scenario:** a friend with an Intel laptop or an NVIDIA card, or an AMD card that
  enumerates as `card0`, right-clicks Graphics: the state line is blank, and "Ask Prime"
  asks whether that's healthy "for an RX 9060 XT".
- **Fix:** reuse `prime-gpu-monitor`, which finds the card itself (AMD sysfs, NVIDIA
  `nvidia-smi`, Intel temperature). The question says "this graphics card".
- **Test:** `tests/check-portable.sh` scans everything `install.sh` ships for the
  author's home path, name, GPU model, fixed `card`/`hwmon` numbers, named screens, named
  sound devices and a committed personal add-on (`my-desktop` is made by `prime-import`
  on your own PC and is never in the repo).

### G2 · P1 · Updates on a private-repo install hang
- **Where:** `layer/bin/prime-update` step 1, `git pull --ff-only`.
- **Scenario:** the friend installed with `gh repo clone`, and git has no stored GitHub
  credentials (they answered "No" to "Authenticate Git with your GitHub credentials?").
  "Update everything" runs in a Prime window; git asks for a username on a terminal that
  doesn't exist and waits.
- **Fix:** `GIT_TERMINAL_PROMPT=0`, no askpass, a 120 s cap; an authentication failure says
  "GitHub didn't let this computer in … run `gh auth login`". The rest of the update
  carries on.

### G3 · P1 · The installer was never tested automatically
- **Where:** `.github/workflows/` had only the bootc image build.
- **Fix:** `desktop-layer.yml`: a fast job (syntax, static suite with GTK self-tests under
  xvfb, menus, greeting, import, personal add-ons, SSH, updater/security, portability,
  private-repo update), a clean container install (`tests/install-in-container.sh`), and
  the real-boot VM test on every pull request.
- `backends/arch/test-system-update.sh` §18 depended on the host's systemd; it now has
  its own fake.

### G4 · P1 · The VM test couldn't complete `all`
- **Where:** `tests/vm/run.sh` `cmd_fetch` ended with `ls … | grep -v "$name" | xargs rm`,
  which returns 1 under `pipefail` when there's no older ISO, so `fetch && base && prime`
  stopped after a first download. OVMF was looked for only under Arch/Fedora names and
  the screenshot check called `magick` (ImageMagick 7 only).
- **Fix:** all three; it now runs on GitHub's Ubuntu runners with KVM.

### G5 · P2 · Two installers
`main` carries three installer fixes from PR #6 (GPU by PCI vendor id, `hardware.conf`
kept when unchanged and backed up when not, backup pointer on re-runs) on an older
`install.sh`; `integrate/prime-layer` rewrote `install.sh` (resume, manifest). They are
reconciled in the `integrate/prime-layer` → `main` merge, which ports the GPU and
`hardware.conf` fixes onto the newer installer; the backup pointer is already covered by
its manifest (uninstall restores from the oldest backup that holds each file).

---

## "Steve Jobs" — product and first run

### J1 · P1 · The greeting only worked on the author's PC
- **Where:** nothing in Prime ran `fastfetch`. CachyOS's fish config does, so the owner
  saw P.R.I.M.E; a CachyOS CLI install with bash, or anyone on zsh, saw a bare prompt.
- **Fix:** kitty starts `layer/bin/prime-terminal-shell` (written into the theme's
  `kitty.conf`, so a `shell` line of your own still wins). It shows the greeting unless
  your shell config already runs fastfetch/neofetch, then hands over to your shell with
  `kitten run-shell` so kitty's shell integration still works. `PRIME_NO_GREETING=1`
  turns it off.

### J2 · P1 · "Tested" didn't mean "tested the way a friend does it"
- **Where:** `tests/vm/run.sh` cloned to `~/prime-src` and ran `install.sh --yes`, then
  checked processes; nothing opened the things a person clicks first.
- **Fix:** the VM test clones to `~/prime-linux` and runs `bash prime-linux/install.sh`,
  the README's private-repo steps (only `gh repo clone` is swapped for a bundle; the VM
  has no GitHub login). In the live session `tests/vm/desktop-checks.sh` opens the Start
  menu from the P logo's command, Spotlight, the Prime menu, the greeting and a kitty
  window, checks each is on screen, and screenshots them.

### J4 · P1 · The first login opened with a "something needs you" notification
- **Where:** `install.sh` never installed `layer/system/wayland-sessions/prime.desktop`;
  only `prime-update` did. `prime-doctor --login` checks for it and reports *bad*.
- **Scenario:** every fresh install. The friend picks "Hyprland" (the only Prime-ish
  entry), logs in, and is told the login screen doesn't offer Prime yet.
- **Fix:** step 6 installs the session (recorded in the manifest; `prime-uninstall`
  removes it), the closing message says to pick **Prime**, and the VM test logs into
  that session through SDDM.

### J5 · P2 · Prime's commands weren't on PATH in its own terminal
- **Where:** commands are linked into `~/.local/bin`; Arch's bash login doesn't add it.
- **Fix:** `prime-terminal-shell` adds it before starting your shell.

### Checked, no change
- The install flow is one command, asks for the password once, resumes after an
  interruption, and `--dry-run` writes nothing (the VM test checks the last one).
- First login runs the health check and the welcome once.

---

## What the owner should do on the live machine

The live PC still has SSH open to every network with passwords. After pulling:

```
git -C ~/.local/share/prime-linux pull
sudo ~/.local/share/prime-linux/layer/bin/prime-security ssh off     # if you don't log in from another computer
# or, to keep it for your home network only:
sudo ~/.local/share/prime-linux/layer/bin/prime-security ssh on
prime-security                                                         # the report should no longer show ✗ for SSH
```

## Test results

From GitHub Actions on this branch (this sandbox can't reach the Arch mirrors):

| Suite | Result |
|---|---|
| Desktop layer tests (syntax, static suite with GTK self-tests, menus, greeting, import, add-ons, SSH, updater/security, portability, private-repo update) | pass |
| Clean install in a fresh Arch container, then `prime-uninstall` | pass, every check |
| Real boot: newest CachyOS ISO → minimal install → README commands → reboot into the Prime session → bar, Start menu, Spotlight, Prime menu, greeting, kitty, title bars, health check → `prime-uninstall` | pass |
| Supervisor policy tests and the image build (`bluebuild`) | pass |

The VM runs without a GPU (GitHub's runners have none), so it renders in software and
hyprpaper, which needs a GPU render node, can't start there; that one check is
reported as not checked. Real PCs and VMs with virgl have a render node.
