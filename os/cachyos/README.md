# os/cachyos — the Prime OS payload for the CachyOS base

This is the working end of the 2026-09-26 owner decision: **Prime OS = CachyOS + the Prime
layer**, where "the Prime layer" is whatever is actually running on the author's desktop. Design
and inventory: [`docs/WORKSPACE-CAPTURE.md`](../../docs/WORKSPACE-CAPTURE.md). Boot layout
requirement (dual-boot with Windows + a snapshot menu): [`docs/DUALBOOT.md`](../../docs/DUALBOOT.md).

```
os/cachyos/
  payload/
    system/        → files that belong at / on the target machine (/usr/local/bin, /etc)
    skel/          → files that belong in the new user's $HOME: the Prime layer's seed
                     (hyprland.conf, kitty.conf), the agent (.hermes) and its services.
                     The captured pre-layer desktop (hypr scripts, waybar, rofi) was
                     removed 2026-10-01 — the layer replaces it.
    TOKENS.json    → the token namespace this payload uses (and what it left alone)
  capture-report.json   (written next to payload/ — hashes, tokens, detected source hardware)
  payload-review/       (NOT shipped: skills, ledger, SOUL.md — curated by hand later)
```

## The two tools

```bash
# 1. capture this machine's layer, templated and secret-free (fails if a leak survives)
tools/capture-workspace.py --out os/cachyos/payload --review

# 2. on the target machine: fill the tokens, detect its own hardware, write the files
tools/expand-payload.py --home /home/alex --root / --user alex \
    --email alex@example.edu --study-dir /home/alex/College

# dry run / inspect the token table
tools/expand-payload.py --home /home/alex --root / --dry-run
tools/expand-payload.py --home /home/alex --list-tokens
```

Both exit non-zero rather than shipping something wrong:

| Exit | capture-workspace.py | expand-payload.py |
|---|---|---|
| 0 | payload is clean: no leak, every file with a parser still parses | every token resolved, files written |
| 1 | nothing captured / usage error | payload or usage problem |
| 2 | a leak or a broken file survived — **not shippable** | a token could not be resolved — **nothing was written** |

## What the tokens mean

| Token | Filled from | Notes |
|---|---|---|
| `@HOME@`, `@USER@` | the target account | replaces the author's home folder and name |
| `@MONITORS@`, `@MONITOR_<n>@` | `hyprctl monitors -j` (or `wlr-randr`) | one `monitor=` line per display, primary at 0x0 |
| `@AUDIO_SINK@` | `pactl list short sinks` | first real sink, not a monitor |
| `@GPU_ENV@` | `lspci` (AMD only) | ROCm gfx override; blank on non-AMD |
| `@STUDY_DIR@`, `@STUDY_PLATFORM@` | interview / CLI | study folder and the window-title match for the school portal |
| `@WALLPAPER@` | CLI | his wallpaper collection does not ship (third-party art) |
| `@LAN_IP@` | CLI | printer address, empty by default |

`@DEFAULT_AUDIO_SINK@` is **not** ours — it is `wpctl`'s own identifier. The capture records
it under `foreign` in `TOKENS.json` and the expander leaves it untouched. Any other `@…@`
in the layer is reported the same way rather than substituted.

## What this is not yet

- **No installer.** There is no archiso profile, no Calamares config, no disk layout. This
  directory produces the *layer*; the OS is still to be assembled around it.
- **81 files need a human pass** (`needs_manual_pass` in the capture report). A token landing
  inside executable logic is a port, not a rename — `prime-pc`'s `PRIME_USER_HOME`,
  `runuser -u @USER@`, the layout generator's monitor handling.
- **First-boot wiring is written, not yet proven.** `prime-target-setup` (archiso) expands
  `skel/` for each account the installer made and installs the **Prime** login session and
  `prime-first-login`; at first login that puts the Prime layer in place with `install.sh`.
  It needs the repository staged at `/usr/share/prime-linux` in the image (not done by
  `apply-buildset.sh` yet), and the ISO install path is blocked upstream (Calamares vs
  boost-python 1.92), so it has not run on a real install.
- **`skel/` has never been exercised on a fresh account.** It was verified by expansion into a
  temp home and by parsers, not by a login. A boot is the only proof.
