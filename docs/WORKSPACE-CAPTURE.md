# Capturing the workspace as Prime OS

Owner direction, 2026-09-27, verbatim: *"prime os is this workspace i have going here.
cachyos, hyprland, prime aka hermes etc, just take all of what i have, package it as
prime os, remake hermes as prime etc, if its working here it should be repeatable no?"*

Yes — with one correction that decides the whole design: **a working machine is
repeatable as a recipe plus a personalization step, never as a copy of the disk.** A
clone of Sean's rig would carry his API keys, his schoolwork, his memory/ledger and his
GPU/monitor/printer assumptions into someone else's house. Same reasoning already in
`PROJECT-STATE.md` rules 2 and 3 ("never ship a secret", "never ship personal data").

So the capture has three layers, and every file in the workspace lands in exactly one.

---

## Layer 1 — ships as-is (the product; no personal data)

Measured on the live machine 2026-09-27.

| Piece | Path | Size / count |
|---|---|---|
| Machine supervisor | `/usr/local/bin/prime-pc` + `/etc/prime-pc/prime-pc.conf` | 20 KB + knobs |
| Snapshot config | `/etc/snapper/configs/root` | 1 file |
| Compositor | `~/.config/hypr/hyprland.conf`, `hypridle.conf`, `hyprlock.conf`, `hyprpaper.conf` | 4 files |
| Workspace scripts (hypr) | `~/.config/hypr/scripts/*` | incl. `prime-snip.sh`, `prime-rgb.sh` |
| Bar (top + sidebar) | `~/.config/waybar/{config*,style*}` + `scripts/` | 30 config/script files, 664 KB |
| Launcher / menus | `~/.config/rofi/prime-{bar,menu,spotlight}.rasi` | 3 files |
| Desktop actions | `~/.config/prime/*.sh` (context, desktop-menu, nemo-ask, new-file) | 4 files |
| User services | `~/.config/systemd/user/prime-{speak,whiteboard,voice-unmute,pc-notify}.*` | 5 units |
| Agent tooling | `~/.hermes/scripts/{prime-*,ledger-*,cal.py,doctor-ish}` | 37 files |
| Agent config surface | `~/.hermes/config.yaml` **with secrets stripped**, `skins/`, `plugins/`, `agent-hooks/` | 1 plugin, 1 hook |
| Skills (the agent's procedural memory) | `~/.hermes/skills/**/SKILL.md` | 127 skills |
| Brand art | `~/.config/hypr/wallpapers/prime_os_red.png`, `prime_business.jpg`, skin art | 1.5 MB |
| **Prime-named files total** | workspace-wide grep `prime*` | **52 files** |

Roughly: **under 2 MB of text config and scripts, plus art — that is the entire Prime
layer.** Everything else on the machine is either the base OS or Sean's data.

## Layer 2 — must be generated at first boot, never baked in

These are the exact things a naive copy gets wrong, with the count on this machine:

| Assumption baked into the live config | Measured | The fix |
|---|---|---|
| Monitor layout | **20** monitor refs in `hyprland.conf` (`HDMI-A-2` @0,0 primary, `HDMI-A-1` @1920,0) | `hw-probe.sh` already detects displays; the layout generator must emit the file |
| GPU / compute flags | **7** files carry `HSA_OVERRIDE_GFX_VERSION` / ROCm vars (Navi 44 specific) | detect GPU, pick flags, or omit |
| Absolute home path | **22** files hardcode `/home/sean` in the UI layer | rewrite to `$HOME` / template vars before shipping |
| Audio sink | **2** files name `alsa_output.pci-…analog-stereo` | discover the sink, write it |
| Printer / slicer | printer IP + `elegoo-web` Docker container (not in the bar layer) | ask in the interview, skip if absent |
| Courses, timezone, name, school portal | `~/College/**` | **the first-login interview already does this** — `backend-*` + `prime-setup` + the GTK wizard `prime-welcome` |

The good news: layer 2 is not new work. The interview/wizard mechanism exists
(`interview.json` + `backends/arch/prime-setup` + `prime-welcome`, 9 steps, GUI audit
passing) and is base-independent by design — it was written for exactly this.

## Layer 3 — never ships (Sean's data and secrets)

| Thing | Size | Why |
|---|---|---|
| `~/.hermes/` whole tree | **96 GB** | sessions, caches, models, builds |
| `~/.hermes/config.yaml` | 12 lines carry keys/tokens | secrets |
| `~/.hermes/auth.json`, `google_token.json`, `google_client_secret.json` | 2.4 KB + 2 files | credentials |
| `~/.hermes/{sessions,memories,ledger.md,state.db,notes,kanban*}` | — | his conversations, grades, to-dos |
| `~/College/**`, Obsidian vault, `~/AI-Transcripts-Archive` | — | schoolwork |
| `~/.config/{google-chrome,discord,Claude,Cursor,mozilla,…}` | 5.7 GB | logged-in profiles |
| `~/.config/hypr/wallpapers/` | 2.4 GB | third-party art, licensing |

## What actually has to be built (the short list)

1. **A payload package** — a `prime-layer` package containing layer 1, with layer 2
   templated (`$HOME`, monitor/GPU/sink placeholders) and nothing from layer 3.
2. **An archiso profile on the CachyOS base** — `archiso` + `cachyos-calamares`, which
   `PROJECT-STATE.md` (2026-09-26 owner decision) already names as the supported route.
   **Nothing exists for this yet** — `grep -rl archiso` across every worktree returns
   only the state doc.
3. **A first-boot personalization pass** that fills layer 2 and writes layer 1 into
   `$HOME` — largely the existing interview, extended with the hardware/layout steps.
4. **Rebrand** — every surface says Prime, including the agent's own UI (skin + name).
   Two hard constraints: upstream licences and trademarks stay intact (repo rule 8), and
   the agent must never be shipped with anyone's key.
5. **The proof is a fresh install on hardware that is not his.** His CachyOS box is the
   reference, never the test target — the same rule the supervisor enforces.

## Status against `SHIP-GATES.md`

The base switch makes the media half of the gate list the *old* track's evidence: the
2026-09-25 qcow2 booted to a KDE desktop and the ISO was built, but both are Fedora/Aurora
artifacts on unmerged branches. On the CachyOS base, D1 (installable artifact) is back to
**not started**, and A1–A6, C1–C6, E1 keep their existing status. Nothing in this document
changes a gate.

## How these numbers were produced

`pacman -Qe/-Qm/-Q`, `du -sh ~/.config ~/.hermes`, `find … -name 'prime*'`, `grep -rl` for
`/home/sean`, `monitor=`, `HSA_OVERRIDE`, `alsa_output`, and a count-only scan of
`config.yaml` for key lines (values never read into any log). Re-measure before quoting.
