# Prime Linux — project state

**Read this before generating anything about this project.** More than one agent
works on this repo (Hermes, Antigravity, Claude Code), and they drift. This file is
the shared source of truth for *state*; `docs/` is the source of truth for *design*.

Last verified: 2026-09-21.

> **This whole file is about the parked Fedora/bootc image track and is stale as
> of 2026-10-02** — over 100 commits and the 2026-09-26 pivot to shipping Prime as
> a layer on CachyOS (`install.sh` + `layer/`) happened after the "last verified"
> date below. For the state of the product that actually ships today, read, in
> order: [`PRIME-LAYER.md`](PRIME-LAYER.md) (what it is and how it's built),
> [`SHIP-GATES.md`](SHIP-GATES.md) (the acceptance bar and what's verified against
> it), and [`REDTEAM-2026-10.md`](REDTEAM-2026-10.md) (the two most recent
> red-team passes against `main`, with what's fixed and what's still open). The
> rest of this file is kept as a historical record of the image track's
> last-known state, not a claim about current reality — do not treat any fact
> below as current without re-checking it.

---

## What this is, in one paragraph

A custom Linux image for students who cannot maintain a Linux machine themselves:
atomic Fedora base, a resident agent (Prime) as OS supervisor, and a first-boot
conversation that personalizes the install. Design of record:
[`ARCHITECTURE.md`](ARCHITECTURE.md). Interview spec: [`INTERVIEW.md`](INTERVIEW.md).
Pitch (for red-teaming): [`PITCH.md`](PITCH.md).

## Current state — verified, not remembered

| Thing | State |
|---|---|
| Base image | `ghcr.io/ublue-os/aurora:latest` — KDE, Fedora **44**, **3.46 GiB**, 256 layers |
| Chosen over | `ghcr.io/ublue-os/bazzite` (4.69 GiB, gaming stack). Reverted to Aurora 2026-09-21 — rationale in the comment block of `recipes/recipe.yml` |
| NVIDIA caveat | Aurora publishes **no** NVIDIA image. Bazzite and Bluefin do (`bazzite-nvidia`, `bluefin-nvidia`) |
| Image publishing | `ghcr.io/<owner>/prime-linux` via `.github/workflows/build.yml` (daily 06:00 UTC) — **green and signed** (run 35641849466, tags `latest`/`44`/`20260921`) |
| Installable media | `.github/workflows/build-disk.yml` (qcow2 + anaconda-iso via bootc-image-builder) — **BROKEN, blocked on a mount failure inside the builder.** Everything ruled out so far, the exact failing call, and the one experiment left: [`DISK-BUILD-DEBUG.md`](DISK-BUILD-DEBUG.md). No qcow2/ISO artifact exists yet, so the VM boot is not possible |
| Hardware probe | `files/system/usr/libexec/prime/hw-probe.sh` — written, tested live (~0.2s), degrades cleanly when tools fail |
| Identity seed | `docs/schemas/identity.schema.json` + `templates/identity.example.yaml` — validates, negative tests pass |
| Permission model | `templates/capability-ladder.yaml` — `destructive.*` and `secrets.*` pinned at approve-each |
| Interview UI decision | Hermes Desktop route (`ROUTES_AREA`); logic in shell + YAML; **no GTK/Electron fork** |
| Interview beats 1–6 writers | **not written** |
| Desktop route plugin | **not written** |
| Backups | Design only. Aurora already ships `restic`, `rclone`, `DejaDup` |
| Rebranding | `files/system/usr/lib/os-release` — `ID=fedora` **on purpose** (the disk builder matches `ID`+`VERSION_ID` against its distro definitions), identity in `NAME`/`PRETTY_NAME`/`VARIANT`/`VARIANT_ID=primelinux`/`IMAGE_ID`. Guarded by `tools/check-os-release.sh` |
| **Supervisor prototype** | `backends/arch/` — `prime` CLI + sandbox and btrfs backends. Lifecycle test: **26/26 passing** (`./backends/arch/test-lifecycle.sh`) |
| Supervisor on a real machine | **not run.** The btrfs backend refuses unless `PRIME_ALLOW_REAL_SYSTEM_CHANGES=yes`; live restore is deliberately not wired up until it has been rehearsed on a throwaway VM |

## Rules

1. **`recipes/recipe.yml` is the OS.** Changing the base image means updating its
   comment block, `docs/ARCHITECTURE.md` §5, and `README.md` **in the same commit**.
   Half-updated base notes are how the last drift happened.
2. **Never ship a secret.** No API keys, tokens or passwords in the image. The user
   supplies their own at first boot, stored `0600` under their home.
3. **Never ship personal data.** One person's config baked into the image turns the
   product into a backup of someone's laptop. Personalization happens on-device.
4. **GHCR paths are lowercase.** `ghcr.io/<Owner>/...` with capitals fails; it must be
   `ghcr.io/<owner>/...`, all lowercase. Any doc or command with an uppercase path is wrong.
5. **Don't guess upstream facts.** Base tags, image sizes, layer counts and driver
   support are checkable — query the registry first, then write the number down.
   Figures here were verified on the date above.
6. **Keep the layer thin.** Prefer flatpak, distrobox, `ujust` and user-space config
   over system packages. A new `dnf` package needs a reason in the commit.
7. **Test what you claim.** `hw-probe.sh` must stay correct with missing/failing
   tools; schema changes need a negative test; a workflow is not working until a
   real run has gone green.
8. **Rebrand properly.** No Fedora or Universal Blue trademarks in shipped
   branding — reference them only as upstream. Keep upstream licenses intact.
9. **The agent acts on someone else's machine.** Any new capability starts at
   `suggest` in the ladder and must write an audit-log entry.

## How to build and test

Nothing here requires local tooling, by design:

```bash
# 1. publish the image (once; needs a GitHub repo under the owner's account)
gh repo create prime-linux --public --source=. --push

# 2. image builds on push; disk/ISO builds are manual
gh workflow run build-disk.yml -f platform=amd64

# 3. download the artifact, boot the qcow2 in a VM
gh run download --name qcow2
qemu-system-x86_64 -enable-kvm -m 4G -drive file=*.qcow2,if=virtio
```

VM testing on the current dev machine (CachyOS) needs `qemu-desktop`, which is not
installed yet. `podman` + the bluebuild CLI are only needed for a *local*
`bluebuild generate-iso`; the CI path above avoids both.

## The unattended update cycle (built, tested)

`backends/arch/prime-autoupdate` + `docs/UPDATES.md`. Every 3 days (and 15 min after
any boot where the timer came due while the machine was off): check → stage the new
image → verify → restart **only** when the machine has been idle 10 min (30 at
night) and nothing long-running is going (builds, encodes, containers, slicers,
printers — `/etc/prime/busy.conf`) and it is plugged in. One notification with
"Later" = 12h of silence. The first boot into the new version is verified (failed
units, screen, session, network, audio) and Prime rolls itself back if it is broken,
then stops retrying after 2 bad boots so it cannot loop.

- Policy is proven in the sandbox: `backends/arch/test-autoupdate.sh`, **29 checks
  across 9 scenarios** (asleep, in use, long job running, "later", suggest-only,
  broken boot, loop guard, audit trail). CI runs it on every push.
- The `bootc` adapter for the shipped image is written but **not yet proven** — it
  needs an image booted in a VM. It refuses to run at all on a non-bootc machine, and
  every mutating verb also needs `PRIME_ALLOW_REAL_SYSTEM_CHANGES=yes`, which only
  the installed systemd units set (so the author's CachyOS is untouched by construction).
- Shipped as `prime-update.timer` / `.service` / `prime-boot-verify.service`, enabled
  by the recipe. `backends/arch/*` is the source of truth and is copied into the file
  layer by `tools/sync-supervisor.sh`; CI fails if the copies drift.

## Two rules about `usr/lib/os-release` (learned the hard way)

See also [`DISK-BUILD-DEBUG.md`](DISK-BUILD-DEBUG.md) for the mount failure that
currently blocks installable media.

The disk build parses this file with a strict reader and fails in two separate ways:

1. **No comments.** Every line must be `KEY=VALUE`. A `#` line makes it fail with
   `readOSRelease: invalid input` — and only the *disk* build notices, so the image
   builds, signs and publishes happily with an unparseable os-release.
2. **`ID` must stay `fedora`.** The builder matches `ID`+`VERSION_ID` against its own
   distro definitions; renaming it gives `could not find def file for distro
   primelinux-44`. Keeping `ID=fedora` is also just true — the system *is* Fedora
   underneath. Prime's identity lives in `NAME`, `PRETTY_NAME`, `VARIANT`,
   `VARIANT_ID`, `IMAGE_ID`, and `PLATFORM_ID` must be present.

## Open questions

- Six beat writers first, or the desktop route plugin? (Writers unblock everything
  else and are testable from a shell.)
- Where does the memory seed live — `~/.config/prime/memories/USER.md` (spec) or the
  agent's own `~/.hermes/memories/USER.md`? Currently specified as the former, with
  the agent reading it.
- Does the base ship first-run tooling that would race with our interview? Check
  Aurora's "mutations that don't work" guidance before overriding anything upstream
  owns.
- Default backup destination for a student: external drive, or a folder they already
  sync.
