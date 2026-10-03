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
people the owner knows personally; it stops being fine once "ask the owner on
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

## The repository is public

`curl -fsSL …/boot.sh | bash` works as written in the README and the user guide —
no GitHub account, no sign-in, nothing to arrange with a tester first.

`install.sh` copies itself into `~/.local/share/prime-linux` with `origin` set to
the GitHub URL, so `prime-update` works from then on. A short URL (a domain that
redirects to the raw `boot.sh`) can come later; it must redirect to the tagged
`stable` copy, never serve its own copy.

If the repository is ever made private again, `curl` stops being able to read it
and testers need `gh repo clone sean-morrissey/prime-linux /tmp/prime &&
bash /tmp/prime/install.sh` instead (git reads it through gh's credential helper).

## Signing

Release tags are signed with GnuPG (`git tag -s`). GnuPG is already on every
Arch/CachyOS machine — pacman itself uses it — so checking needs nothing extra
(in particular, no SSH package: Prime never installs an SSH server).

- **What is checked.** On the `stable` channel `prime-update` fetches, then runs
  `layer/bin/prime-release-verify` before moving: the new version must be a
  commit carrying a `v*` tag signed by a key in
  `layer/system/release/release-keys.asc` — **the copy already on that
  computer**, read before the update is applied, loaded into a throwaway keyring
  that holds nothing else (a key in the person's own keyring can't vouch). An
  untagged commit pushed to `stable`, a tag signed by any other key, an update
  that ships its own key file, or a damaged key file are all refused, and the
  computer stays exactly as it was ("didn't install the new Prime Linux: it
  isn't signed by Prime's release key").
- **Where trust starts.** At install time (trust on first use): the key file a
  computer is installed with decides every later update, and a new key can only
  arrive inside an update the old key signed. Publish the key's fingerprint in
  the README and the release notes so a careful installer can compare.
- **Other channels.** `main`, `edge` and feature branches are for testers and
  follow the branch unsigned (`PRIME_REQUIRE_SIGNED=1` checks them too).
- **Before the first key.** `release-keys.asc` ships empty; until a key is added
  nothing can be checked, updates are allowed, and the verifier says so. **Make
  the key before the repository goes public**, so the first public installs
  already pin it.

Owner, once:

```bash
tools/release-sign.sh --new-key          # ed25519 signing key (passphrase!) → release-keys.asc
git add layer/system/release/release-keys.asc && git commit -m "release: Prime's release key" && git push
gpg --export-secret-keys --armor > prime-release-secret.asc   # → offline backup, then delete this file
```

Every release afterwards (replaces the plain `git tag` in "Cutting a release"):

```bash
tools/release-sign.sh v2026.10.0         # signs with the CHANGELOG notes, then checks it like computers will
git push origin v2026.10.0 && git switch stable && git merge --ff-only v2026.10.0 && git push origin stable
```

Rotating the key: add the new public key to `release-keys.asc` in a release
signed by the old one; drop the old key one release later.
`tests/check-release-signing.sh` holds all of this (forged, unsigned, untagged,
self-keyed and damaged-key updates are refused).
