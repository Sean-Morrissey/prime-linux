# Releasing Prime Linux

Prime Linux (the install-script layer) is released from git. A user's copy
lives at `~/.local/share/prime-linux` and `prime-update` moves it forward, so
"a release" is a commit that every user's `git pull` lands on.

## Versions

`YEAR.MONTH.N` — e.g. `2026.10.0`, `2026.10.1`. Calendar versions because the
base (CachyOS) is rolling; the number says how fresh it is, not how compatible.
A tag is `v2026.10.0`, annotated, with the changelog section as its message.
`prime-about` shows `git describe --tags`, so users see `v2026.10.0` (or
`v2026.10.0-3-gabc123` between releases).

## Channels

| Channel | Branch | Who | How it moves |
|---|---|---|---|
| **stable** | `stable` | everyone (default once public) | fast-forwarded to a release tag, never to anything untagged |
| **edge** | `main` | testers, the team | every merged PR |
| **dev** | any feature branch | developers | anything |

`boot.sh` installs `PRIME_REF` (default `main` until the first stable release,
then `stable`). Switching channel on an installed machine:
`git -C ~/.local/share/prime-linux switch stable` — `prime-update` follows the
checked-out branch. (A `prime-channel` menu row is a small follow-up for the
Updates owner.)

### Staged rollout, once `stable` has real users

`stable` fast-forwarding to a tag is instant and total: every machine on that
channel gets the new tag the next time `prime-update` runs, with no gradient
between "nobody has it" and "everybody has it." That's fine for a handful of
people the owner knows personally; it stops being fine once "ask Sean on
Discord" isn't how most users would find out something's wrong. Before that
point, a cheap staged rollout — no new infrastructure, just discipline:

1. Tag the release as normal, but don't fast-forward `stable` yet. Let the
   owner's own machine and `edge` users run the tag for a few days first (this
   is exactly what `edge` already is).
2. Fast-forward `stable` only after that soak period is clean — no new
   `prime-doctor` failures, no rollback events logged from anyone running the
   tag.
3. If the user base outgrows "the owner would notice," the next cheap step is
   a percentage-of-machines gate in `prime-update` itself (hash the machine ID,
   fast-forward to the new tag only once that hash falls under a published
   rollout percentage that climbs over a few days) — not needed yet, worth
   having the shape in mind before it is.

## What "releasable" means — the gate

All of these, on the commit being tagged:

1. `tests/install-in-container.sh` — ALL PASSED (install + uninstall on a clean Arch container).
2. `tests/vm/run.sh all` — real CachyOS ISO (newest, checksum-verified) → minimal
   install → `install.sh` over SSH → reboot into Hyprland → session checks pass →
   screenshot reviewed by a human → `prime-uninstall` leaves no Prime files.
3. Every package in `os/arch/packages.txt` exists in the official repos
   (`pacman -Si`, also checked by the container build).
4. Migrations: a machine on the **previous tag** updated with `prime-update`
   ends up identical to a fresh install (`prime-migrate --pending` prints none,
   `Hyprland --verify-config` clean). Run it in the VM: install the old tag,
   then `git pull` + `prime-update --prime`.
5. `docs/USER-GUIDE.md` matches the shortcuts (Super+/ list) and menu.
6. No personal data: `tests/check-install.sh`'s "no trace of the author's machine".

## Cutting a release

```bash
git switch main && git pull
# 1. tests (above)
# 2. changelog: add a section at the top of CHANGELOG.md
#    ## v2026.10.0 — 2026-10-15
#    ### New   ### Fixed   ### Changed (what users notice; one line each)
#    ### Upgrading — anything a migration does, in plain words
git tag -a v2026.10.0 -F <(sed -n '/^## v2026.10.0/,/^## v/p' CHANGELOG.md | sed '$d')
git switch stable && git merge --ff-only v2026.10.0
git push origin main stable v2026.10.0
```

Hotfix: branch from the tag, fix, tag `v2026.10.1`, fast-forward `stable`, merge
back into `main`.

## Changing the layout of users' files — migrations

Anything that changes a file **the user owns** (seeded files, `~/.config/...`)
needs a migration, because seeds are only copied once:

```bash
cat > layer/migrations/$(date +%s).sh <<'EOF'
#!/usr/bin/env bash
# one line saying what this changes (shown during prime-update)
...  # must be safe to run twice; runs as the user, never root
EOF
```

`prime-migrate` runs pending ones in order after `prime-update` pulls; done ones
are listed in `~/.config/prime/migrations`. A new install marks all of them done.
Test it the way gate 4 says. Files in `layer/default/` don't need migrations —
they're replaced on update.

## The private-repo period

Until the repository is public, `curl …/boot.sh` can't fetch anything. Testers use

```bash
gh repo clone sean-morrissey/prime-linux /tmp/prime && bash /tmp/prime/install.sh
```

`install.sh` copies itself into `~/.local/share/prime-linux` with `origin` set
to the GitHub URL, so `prime-update` works for anyone whose git can read the repo
(gh's credential helper). Going public needs nothing else: the boot.sh line in
the README and USER-GUIDE starts working as written. A short URL
(e.g. a domain that redirects to the raw `boot.sh`) can come later; it must
redirect to the tagged `stable` copy, never serve its own copy.

## Signing (later)

Tags are signed (`git tag -s`) once a release key exists; `prime-update` will
verify the tag signature before fast-forwarding `stable` (Updates & Security owns
the check).
