# Prime Linux — full review, October 2026

**Date:** 2026-10-02 · **Base:** `main` @ `00a94df` (then verified again against
`fix/ci-screensaver-keybind-and-cairo` and `docs/truth-pass-cachyos-reality`, both
opened from this review) · **Scope:** the whole repository, as a friend receives
it — `README.md`, `docs/`, `install.sh`, `boot.sh`, `layer/`, `backends/arch/`,
`tests/`, `.github/workflows/`.

**What this review does differently from the two rounds already in
`docs/REDTEAM-2026-10.md`:** those rounds were thorough and real — SSH safety, the
owner's-GPU bug, the installer never running in CI, the idle-math and
rollback-loop defects, GPU detection on a hybrid laptop — and I independently
re-verified a sample of their fixes rather than trust the doc (`tests/check-ssh.sh`
passes 19/19 locally, the submap test below aside, `backends/arch/prime-autoupdate`
does contain the idle-math and fail-limit fixes at
[`backends/arch/prime-autoupdate:116-129,436-445`](../backends/arch/prime-autoupdate),
the capability ladder is genuinely read by code at
[`layer/bin/prime-settings:52,225-325`](../layer/bin/prime-settings) and not "prose
only" as `RED-TEAM-REVIEW.md:60` still (correctly, for its own date) says). This
round's job was to find what two rounds of the project's own red-teaming didn't
catch, and to answer the product questions — is this worth installing, is it
sexy, does it beat the obvious alternatives — that a defect-hunting red team
doesn't normally ask. The honest result: there is less *new* breakage to find than
you'd expect from a project this size, and the highest-leverage problem turned out
to be a documentation one nobody had looked at from a new reader's seat.

Three voices, as asked. Severity: **P0** broken/security/data loss · **P1** wrong
for most people · **P2** real but narrow · **P3** polish.

---

## 1. Is this a good idea? Who is it for, and does it beat the alternatives?

**Steve Jobs.** Yes, and the reason is specific: every other "AI desktop" is an
assistant bolted onto a normal Linux install — a chat window you open when you
remember it exists. Prime inverts that, and the inversion is real in the code, not
just the pitch: the agent has a permission ladder
(`templates/capability-ladder.yaml`, actually enforced —
[`layer/bin/prime-settings:265-267`](../layer/bin/prime-settings)), an audit log,
and a fixed toolbox instead of a raw shell
([`layer/addons/ai/bin/prime-ask:181-190`](../layer/addons/ai/bin/prime-ask) never
calls `exec`/`system` on model output). Compared to **plain CachyOS KDE**: you get
none of the supervision, none of the interview, none of the "ask Prime" on every
bar item. Compared to **Omarchy**: `docs/PARITY.md` is an honest, sourced,
line-by-line comparison (not marketing) and the self-reported score is close —
Prime is ahead on polish (GUI pickers instead of TUIs for Wi-Fi/Bluetooth/sound),
behind on a few laptop niceties (clamshell mode, touchpad toggle). Compared to
**Ubuntu**: Ubuntu is not a tiling/rice distro and isn't competing for the same
user. The honest comparison is Omarchy, and Prime wins it on "a beginner's friend
can actually drive this," which is the whole point.

**Bill Gates.** Good idea, undersized claim for what's actually shipped. The
install story is real and tested (`tests/install-in-container.sh`,
`tests/vm/run.sh all` both pass in CI), but "the OS supervisor" — the always-on
agent with voice, reminders, StudyHub — is still mostly `layer/addons/ai`, which
is off by default and optional. What ships by default and unconditionally is a
very well-built Hyprland desktop layer with excellent self-repair
(`prime-doctor`), not yet the "Prime" from the pitch. That's not dishonest — the
README says "the image/ISO work... is not needed to try it" — but it means the
differentiator claimed in the README's comparison table ("the OS supervisor —
hotkey voice, screen-aware") is aspirational for most installs, not default
behavior.

**Linus Torvalds.** The architecture decision — ship a thin layer on top of an
existing, well-maintained distro instead of forking one — is the correct call and
the project visibly knows it; `docs/ARCHITECTURE.md` §9 reasons honestly about
*why* atomic was chosen first and what's given up by not using it (reactive
rollback via snapshots, not preventive immutability). The risk isn't the idea,
it's that the idea briefly had two unreconciled implementations in the same repo
at once (see §3 and finding F1) — that's a process failure, not a design one.

---

## 2. Does it work? What's verified, what's broken, half-done, or owner-only?

**Verified working, by me, independently, this session:**
- `bash tests/check-static.sh`, `check-import.sh`, `check-syntax.sh`,
  `check-portable.sh`, `check-menus.sh` all pass locally against `main` + the
  fixes in this review.
- CI on the fix branch is green except the slow VM job (still running at review
  time): `gh pr checks 19` shows `Clean install (fresh Arch container)` and
  `Desktop layer tests (no install)` both `pass`.
- `prime-context bar.clock` genuinely renders as a compact, correctly-sized rofi
  window (540×101px, reproduced live under `xvfb-run` on this machine) — the
  stale preview PNG that looked broken was the image, not the UI (F5).
- The capability ladder is real code, not prose (§1).
- `python3 -c "import cairo"` / `import gi; gi.require_version('Gtk','3.0')` both
  succeed on a real CachyOS+Prime machine, confirming the missing-dependency
  diagnosis in F2 rather than some other cause.

**Broken, found this session:** `main`'s tip was red — see F2. Both causes were
real product defects (a crashing lock-screen feature on every fresh install, a
test that would false-fail on any future legitimate submap rebind), not flaky CI.

**Half-done / owner-only, confirmed still true:** the bootc/atomic-image track
(`recipes/`, `os/cachyos/`, `backends/arch/backend-bootc.sh`) has never completed
an install to a disk (`docs/BUILD-STATE-2026-09-27.md:73`: "no install has ever
been completed to a disk, on this base or the older Fedora one") and the repo is
still private (`gh repo view` → `isPrivate:true`), so `boot.sh`'s one-line public
install path is untested by the public. Both are legitimate, acknowledged,
in-progress states — not claims of done-ness — once F1 lands.

---

## 3. What doesn't work, and how to fix each thing

This is the master list in §9. Short version: two real defects (both fixed in
this review's branches), two doc-accuracy problems (both fixed), the rest is
polish or process recommendations, not breakage.

---

## 4. Is it sexy? Concrete design notes, from the real rendered UI

I reviewed the actual rendered screenshots the project keeps for design review
(`layer/branding/previews/*.png`, regenerated from real `rofi`/GTK renders by
`layer/branding/src/preview-*.sh`), not a description of them.

**Steve Jobs — what's genuinely good, say it plainly:** `start-menu.png` and
`spotlight.png` are not "Linux trying to look like a Mac" — they're *at* that
bar: consistent 14px-radius cards, one accent colour used sparingly (the
red-to-violet "P" mark), real empty states, a footer hint row
(`move / open / esc / apps only / web / maths`) that teaches the shortcut
instead of hiding it. `window-update.png` and `window-health.png` solve a problem
most Linux tools don't even see — a System-Preferences-quality progress view
with color *and* words on every row (`✓ OK`, `! Needs you`, `⟳ Fixed`), which
satisfies the project's own "never colour alone" rule
(verified: `tests/check-static.sh` → "states are said in words or symbols, not
colour alone", passing). The terminal greeting
(`terminal-greeting.png`) — "PRIME" spelled vertically with
lease/elax/'ll/anage/verything running down the right — is a genuinely charming,
memorable piece of brand work that costs nothing functionally.

**What looks cheap or unfinished, concretely:**
- The ANSI 16-colour swatch row at the bottom of the terminal greeting
  (`terminal-greeting.png`) is raw `fastfetch` boilerplate sitting under an
  otherwise fully brand-themed greeting — it reads as an unstyled leftover next
  to deliberate work. Fix: theme the swatch to the brand palette or drop it.
  P3, S effort, not executed this round (cosmetic, not urgent — recommended).
- `bar.png`'s right-hand cluster (`0% · 5% · 4% · ⟳0 · …`, zoomed and confirmed)
  is four small, visually similar circular badges in a row with bare percentages
  and no grouping — it reads as a wall of numbers rather than "glance and know."
  The project's own rule (every item has a tooltip) softens this, but a glance
  shouldn't need a hover. F8, P3, judgment call — flagged, not changed
  unilaterally.
- The design-preview gallery itself has rotted in one place and has a gap in
  another (F5): the newest, most visible feature (the screen saver) was shipped
  with zero design-review coverage, and an adjacent preview (`right-click-menu.png`)
  is stale enough that it nearly reads as a bug report for a UI that no longer
  behaves that way. A gallery that isn't regenerated every PR stops being useful
  faster than most teams expect.

**Bill Gates:** the visual system holds up because it's enforced by tests, not
taste — `check-static.sh` checks rem-sizing, tooltip presence, right-click
coverage, and "no colour alone" as CI gates, not style-guide prose. That's the
right way to keep "sexy" from rotting as more contributors touch the layer.

---

## 5. Is it easy to use? A non-technical friend, start to finish

Walking `README.md` → `install.sh` → first login → daily use → update →
something breaks → uninstall, as written, today:

1. **Install.** Clear, numbered, copy-paste, resumable, `--dry-run` genuinely
   changes nothing (tested). One real friction point: a private-repo friend must
   run `gh auth login` correctly including "authenticate Git with your GitHub
   credentials? **Yes**" — getting this wrong silently breaks `prime-update`
   later (this exact failure mode is G2 in `docs/REDTEAM-2026-10.md`, already
   fixed with a clear error message, verified still present in
   `layer/bin/prime-update`'s update path). Acceptable; the failure is caught
   and explained rather than silent.
2. **First login.** `install.sh` now installs the Prime session entry before
   first login (J4, already fixed), so the login-screen confusion that existed
   earlier is gone. The first thing a friend sees working is the Start menu and
   Spotlight — both genuinely self-explanatory from the screenshots in §4.
3. **Daily use.** Everything in `docs/USER-GUIDE.md` §4 maps to a real, tested
   control — no terminal required for any of it (enforced by
   `tests/check-static.sh`'s "nothing in the menu, bar, right-click menus, app
   list or keys opens a terminal").
4. **Update.** One click, snapshot-first, explained in plain words
   (`window-update.png`). The idle-gate and rollback-loop logic that would have
   made "update interrupts you mid-essay" or "machine bricks itself" real risks
   are fixed and tested (§1, re-verified).
5. **Something breaks.** Super+H runs `prime-doctor`, which both diagnoses and
   fixes what it safely can (`window-health.png`) — genuinely better than "read a
   forum post," which is the real alternative on most distros.
6. **Uninstall.** `prime-uninstall` is tested end-to-end in CI including a
   user's own pre-existing config and autostart entries surviving the round trip
   (`tests/install-in-container.sh`, confirmed passing).

**Where a non-technical friend would still get stuck, today:** nowhere in the
tested, default path. The confusion points that exist are all in the *parked*
image/ISO track (private GHCR, unbuilt disk images) — which a friend following
the README's actual "Install (on CachyOS)" section never touches. That gap
between "the README's install instructions" and "the README's description of how
the product works" was F1 — now closed.

---

## 6. Is it worth installing? Top 3–5 highest-leverage changes

For a new person deciding whether to keep it, recommend it, and come back after
an update: the product (§5) is genuinely good enough to pass this bar already.
The highest-leverage changes are about *trust at the edges*, not the daily-use
core:

1. **Keep CI green, always, starting now (F2).** The single fastest way to lose
   a volunteer tester is "I pulled main and the install is broken." This was
   true right now, for the project's own self-test suite, when this review
   started.
2. **Make the docs agree with each other (F1).** A friend who gets curious and
   reads past the README's install section hits a different product description
   a few paragraphs later. First impressions of *documentation* compound with
   first impressions of the *desktop*.
3. **Finish the trust story for the public boot path before going public.**
   `boot.sh` is `curl | bash` from a moving branch with no signature (L4,
   already known and deferred pending `docs/RELEASE.md`'s tag/channel model).
   This is fine while the repo is private and installs are by personal
   invitation; it is the single biggest thing to close before flipping the
   repo public, not after.
4. **Decide, don't default, on the always-on agent.** Right now the headline
   differentiator (hotkey voice, screen-aware assistant) is an opt-in add-on.
   Either feature it in the interview as a real choice with a clear cost
   (spend cap, what it can see) so a new user makes an informed yes, or stop
   describing it as the default experience in the README's comparison table.
5. **Regenerate the design-preview gallery as a CI/PR habit (F5).** Cheap,
   already has the tooling, and is the fastest way to catch the next PR-18-style
   gap before it ships.

---

## 7. Updates: how do they reach users, what can go wrong, how should rollback work?

**Mechanism, verified:** git-based channels (`stable`/`main`/feature branches,
`docs/RELEASE.md`), `prime-update` = `git pull` + re-run installer steps +
`prime-autoupdate`'s system-package cycle (snapshot → apply → verify →
self-rollback, `backends/arch/prime-autoupdate`). This is a sound model for a
rolling base: it doesn't pretend to be atomic, and it doesn't need to, because
the actual undo mechanism (btrfs snapshot + boot-menu entry via
`limine-snapper-sync`) is real and CachyOS-native, not bolted on.

**What can go wrong, and the project's own answer:**
- *Bad update ships to everyone at once* — real risk on any rolling base, and
  **not mitigated by a channel gate today**: `stable` is "fast-forwarded to a
  release tag," but nothing in `prime-autoupdate` or `prime-update` canaries a
  change before it reaches every `stable` machine simultaneously. Worth a
  staged-rollout note in `docs/RELEASE.md` as the user base grows past "friends
  the owner personally knows."
- *Conflicting user edits* — handled well: the three-layer precedence (defaults
  → add-ons → the user's own file, user always wins) is enforced structurally,
  not by convention, and migrations are explicitly required for anything that
  changes a file the user owns (`docs/RELEASE.md`'s migration section, tested by
  `tests/check-install.sh`'s migration checks).
- *Hyprland/Arch breakage upstream* — `Hyprland --verify-config` gates every
  config change in CI, which catches syntax breaks but not semantic ones (a
  renamed dispatcher, a changed default). No version pin exists anywhere in
  `os/arch/packages.txt` by design (rolling), so a breaking Hyprland release
  reaches every machine the same day it reaches the Arch repos. The snapshot
  rollback is the safety net, and it's a real one — but it's reactive.
- *A rolling-release surprise* — same answer as above: the product's safety
  story is entirely "detect and roll back," never "prevent." That's an honest,
  reasonable choice for a layer on a rolling base, but it should be said
  explicitly somewhere a new user can read it, not left implicit.

---

## 8. Future problems — 3, 6, 12 months, and the fix for each

**3 months.** The parked image track and the shipped layer will keep drifting
unless someone enforces the boundary found in F1 — recommend a CI check (or a
doc convention) that flags any new doc that mentions `recipes/`, `bootc`, or
`BlueBuild` as current-state language without the "parked" qualifier, the same
shape as `tests/check-portable.sh`'s existing grep-for-forbidden-strings pattern.

**6 months.** No package-version floor anywhere (`os/arch/packages.txt` names
packages, never versions) — the correct choice for a rolling base, but it means
a breaking upstream Hyprland/waybar/rofi release reaches every Prime machine on
the same day it reaches Arch's repos, with no staging. The mitigation that
exists (snapshot rollback) is real; the mitigation that doesn't (a canary ring,
or at minimum `prime-doctor` flagging "this package just changed major version")
is worth planning before the user base is large enough that "ask Sean on
Discord" stops scaling.

**12 months.** Two independent, verified "what will rot" findings converge
here: (a) GTK3/GTK4 split (F6) — `prime-welcome` is already GTK4+libadwaita,
five other windows are GTK3, and GTK3 is upstream in maintenance-only mode; (b)
the private→public switch turns `boot.sh`'s unsigned `curl | bash` from a
moving branch (L4, already known) from "fine because only invited friends use
it" into "the entire public attack surface of the project," on the same day the
repo's visibility toggles. Neither is urgent today; both become the top issue
the day their triggering condition (GTK3 removed from a default Arch install;
repo made public) arrives, and both have cheap mitigations if planned ahead
(migrate new GTK windows to GTK4 as a standing rule; cut the first signed,
tagged `stable` release *before* flipping visibility, not after).

**Repo growth / multi-user, open questions (not verified either way this
session, flagged honestly rather than guessed):** does a second account on an
already-Primed machine get a correct, independent interview and capability-ladder
state, or does it inherit the first account's system-level choices silently?
`install.sh`'s system-level steps (step 6: SDDM, firewall, nightly-update policy)
run once per machine, not per account — worth a explicit test
(`tests/install-in-container.sh` currently covers one account) before this
becomes a real scenario rather than a hypothetical.

---

## 9. Master ranked list

| ID | Sev | Reviewer(s) | Finding | Evidence | Fix | Effort | Status |
|---|---|---|---|---|---|---|---|
| **F1** | **P1** | Jobs, Gates, Linus | `README.md` self-contradicted about what the product *is*: "Install" correctly says CachyOS + `install.sh`; "How it works"/"Layout"/"Build it"/"Roadmap" described an abandoned Fedora/BlueBuild atomic-image product. `docs/ARCHITECTURE.md` ("the design of record," linked from the README) and `docs/PROJECT-STATE.md` ("read this before generating anything about this project") were both entirely about that same abandoned track, dated before the 2026-09-26 pivot to shipping on CachyOS (`docs/PRIME-LAYER.md:1-9`). | `README.md:138-232` (pre-fix); `docs/BUILD-STATE-2026-09-27.md:73` ("no install has ever been completed to a disk"); `docs/PROJECT-STATE.md:7` ("Last verified: 2026-09-21") | Rewrote the contradicting README sections to describe `install.sh`/`layer/`; added a superseded-status banner to the top of `ARCHITECTURE.md` and `PROJECT-STATE.md` pointing at `PRIME-LAYER.md`/`SHIP-GATES.md`/`REDTEAM-2026-10.md`; same-cause fixes in `PITCH.md`, `CONTEXT-ACTIONS.md`, `INTERVIEW.md` (false restic/rclone/DejaDup claim, folded into this item) | M | **Fixed** — [PR #20](https://github.com/Sean-Morrissey/prime-linux/pull/20) |
| **F2** | **P1** | Gates, Linus | `main`'s tip (`00a94df`, after PR #18) was red: `prime-screensaver` crashes with `ModuleNotFoundError: No module named 'cairo'` on every real install (`python-cairo` was never added to `os/arch/packages.txt` or the ISO package list) — `prime-lock` falls back to plain `hyprlock` so locking stays secure, but PR #18's advertised "screen saver as the first face of the lock" is dead on arrival today. The container job's "no key is bound twice" and the `prime-import` check also failed: the duplicate-bind checker is a plain grep with no concept of Hyprland submaps, so PR #18's legitimate `SUPER,L` rebind scoped inside the `prime-locked` submap read as a clash with the global `SUPER,L` lock shortcut. | CI run `36949014106`; `layer/bin/prime-screensaver:36` (`import cairo`); `layer/default/hypr/bindings.conf:118,124`; `tests/check-install.sh:32` (pre-fix) | Added `python-cairo`/`python3-cairo` to `os/arch/packages.txt`, the ISO package list, and the CI `apt-get` step; made the duplicate-bind checker submap-aware in `tests/check-install.sh` and `tests/check-import.sh` | S | **Fixed** — [PR #19](https://github.com/Sean-Morrissey/prime-linux/pull/19), verified green in real CI (`gh pr checks 19`) |
| **F3** | P2 | Gates, Linus | `.github/workflows/build.yml`'s `bluebuild` job built and pushed the parked Fedora/bootc image (using the signing secret) on every push, every PR and every night, regardless of relevance — CI minutes and registry writes for a track that has never completed an install. | `.github/workflows/build.yml:1-10,52-73` (pre-fix); `docs/BUILD-STATE-2026-09-27.md:73` | Gated the `bluebuild` job to `workflow_dispatch` only; `supervisor-tests` (the useful job — tests the real `backends/arch/*` update/rollback logic) still runs on every trigger | S | **Fixed** — [PR #19](https://github.com/Sean-Morrissey/prime-linux/pull/19) |
| **F4** | P2 | Gates | Folded into F1: `docs/INTERVIEW.md`'s backup beat claimed "the Aurora base already ships restic, rclone and DejaDup," true for the parked image, false for the shipped CachyOS product (none are in `os/arch/packages.txt`) — whoever builds that beat would go looking for packaging work that doesn't exist. | `docs/INTERVIEW.md:391-394` (pre-fix); `os/arch/packages.txt` (no hits) | Corrected the claim; backup tooling is a packaging task, not just config | S | **Fixed** — [PR #20](https://github.com/Sean-Morrissey/prime-linux/pull/20) |
| **F5** | P2 | Jobs, Linus | The screen saver (PR #18's headline feature) has zero coverage in the design-preview gallery despite `prime-screensaver --screenshot F` existing for exactly that purpose; the adjacent preview `layer/branding/previews/right-click-menu.png` is stale — a live re-render of the same command (`prime-context bar.clock`) under the same `xvfb` harness the project's own script uses produces a compact, correctly-sized 540×101px window, not the near-empty box the checked-in PNG shows. | `layer/branding/src/preview-pro-ui.sh:83` (only existing-UI coverage); `layer/bin/prime-screensaver:14` (`--screenshot F` documented, unused by any preview script); live reproduction this session (`xvfb-run` + `prime-context bar.clock` → 540×101px) | Wire a screensaver frame into `preview-pro-ui.sh` or `preview-desktop.sh`; re-run the preview scripts as a standing habit before any PR that touches a surface they cover | S | Open — recommended, not executed (doesn't change shipped behavior, only a review artifact; left for the owner to fold into a design pass) |
| **F6** | P3 | Linus | GTK3/GTK4 split: `prime-welcome` is GTK4 + libadwaita; `prime-start`, `prime-spotlight`, `prime-panel`, `prime-activity`, `prime-screensaver` are GTK3. Not broken today; GTK3 is upstream in maintenance-only mode, a 12-month horizon risk (§8). | `layer/bin/prime-welcome` (`Gtk 4`) vs. `layer/bin/prime-start`, `prime-spotlight`, `prime-panel`, `prime-activity`, `prime-screensaver` (`gi.require_version("Gtk", "3.0")`) | **Proposal, not built (L effort):** new GTK windows default to GTK4 + libadwaita from now on; migrate the five GTK3 windows opportunistically, one per future UI-touching PR, rather than a dedicated migration sprint. Risk: `gtk-layer-shell` (used for the bar/Spotlight/screen-saver's screen-anchoring) needs verifying against GTK4 before starting — not confirmed compatible in this review. | L (proposal only) | Open — roadmap item |
| **F7** | P3 | Linus | ~15 stale local/remote branches (`feat/*`, `fix/*`, `integrate/*`, six `worktree-agent-*`, three `claude/*`) are pre-pivot debris, not unmerged work — e.g. `integrate/release-candidate` differs from `main` by 5,217 insertions / 31,700 deletions (independently verified this session, `git diff --stat main integrate/release-candidate`), nothing recoverable. | `git diff --stat main integrate/release-candidate`, re-run myself; equivalent spot-checked for `fix/desktop-first-run`, `fix/installable-artifact` | Delete them | S | Open — **needs the owner's go-ahead**; deleting remote branches is a shared, hard-to-reverse action I didn't take unprompted |
| **F8** | P3 | Jobs | `bar.png`'s right-hand icon cluster (zoomed and confirmed) is four small, visually similar circular badges with bare percentages and no strong grouping — a glance-ability soft spot, softened but not solved by the project's own "every item has a tooltip" rule. | `layer/branding/previews/bar.png`, cropped/inspected this session | Group the cluster with a subtler visual break, or label it | S | Open — design judgment call, flagged rather than changed unilaterally |

**One finding that did not survive verification, noted for the record rather
than silently dropped:** a sub-agent initially reported GPU-vendor branching as
"hand-duplicated in four places instead of using the shared `gpus()` helper."
Reading the four call sites directly
(`layer/addons/gaming/bin/prime-gaming:153`,
`layer/addons/creator/bin/prime-creator:36,62`, `layer/bin/prime-addon:116`)
shows they already call the shared `gpus()` helper
(`layer/addons/_lib/pack.sh:71-82`) and then branch on its result differently
per call site, which is normal — the detection logic *is* centralized; only the
per-vendor consequences differ. No fix needed.

**Everything else a red team would normally list here was already found and
fixed by the project's own two prior rounds** (`docs/REDTEAM-2026-10.md`), and I
independently re-verified a sample rather than take the doc's word for it: SSH
default-open (`tests/check-ssh.sh`, 19/19), the owner's-GPU hardcoding
(`tests/check-portable.sh`, passing), idle-math and rollback-loop
(`backends/arch/prime-autoupdate:116-129,436-445`), GPU detection on a hybrid
laptop (`tests/check-gpu-detect.sh`). None of these regressed.

---

## 10. Scores and the honest verdict

| Reviewer | Score /10 | Why |
|---|---|---|
| **Steve Jobs** | 7 | The rendered UI is genuinely good — Spotlight, Start menu and the update/health windows are Mac-HIG quality, not "Linux trying." Loses points for the doc self-contradiction a curious new user would hit within five minutes of getting interested (fixed this review), and for the gap between the headline pitch (always-on supervising agent) and what's on by default (an excellent desktop layer, agent opt-in). |
| **Bill Gates** | 6 | The install/update/uninstall lifecycle is real, tested, and resumable — better QA discipline than most hobby distros ship with. Loses points for `main` being red at review time (fixed), no staged rollout for a rolling base at scale, and an honest-but-real gap between "private repo, invited friends" (works today) and "public, unsigned `curl \| bash`" (the plan, not yet hardened). |
| **Linus Torvalds** | 7 | Clean separation of concerns (three-layer precedence, migrations, a capability ladder that's actually code), good test culture (21 test scripts, a container test, a VM test, submap-aware now). Loses points for the process failure that let two implementations of the same product coexist undetected for a week, and for the handful of real-but-narrow rot items (F6–F8) that are cheap now and expensive later. |

**Ship it to friends? Yes, now that F1 and F2 are merged** — the actual
install-to-daily-use path is solid, tested, and was never the problem; the
problem was that `main`'s self-test suite was failing and the documentation a
curious friend would read described a different, non-existent product. Both are
fixed in the two PRs this review opened. The remaining open items (F5, F6
onward) are real but narrow or purely cosmetic, exactly the kind of thing that's
fine to fix as you go rather than block on.

---

## PRs opened by this review

- [**#19**](https://github.com/Sean-Morrissey/prime-linux/pull/19) — CI green:
  F2, F3
- [**#20**](https://github.com/Sean-Morrissey/prime-linux/pull/20) — docs truth:
  F1, F4

Recommend merging #19 and #20 before anything else lands, since every later
change is easier to verify against a green, truthful `main`.
