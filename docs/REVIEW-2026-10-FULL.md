# Prime Linux — full review, October 2026

**Date:** 2026-10-02, revised same day after #19/#20/#21 merged and a further
pass closed F5 and F7 · **Base:** `main` @ `00a94df` initially, re-verified
against each PR's branch as it was built · **Scope:** the whole repository, as a
friend receives it — `README.md`, `docs/`, `install.sh`, `boot.sh`, `layer/`,
`backends/arch/`, `tests/`, `.github/workflows/`.

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

**Bill Gates.** Good idea, mostly delivered — I was too quick to call this
undersized on first pass and want to correct that on the record rather than
quietly soften it. The install story is real and tested
(`tests/install-in-container.sh`, `tests/vm/run.sh all` both pass in CI), and the
assistant *is* a genuine, well-designed step in the first-run wizard, not an
afterthought: `layer/bin/prime-welcome`'s step 5 ("Want an AI assistant? …
Optional.") offers a real provider picker — including a local/network option
specifically so "nothing leaves your home" — a password-masked key field that
says plainly where the key stays, and only enables `layer/addons/ai` if the
person actually connects one
([`layer/bin/prime-welcome:576-610`](../layer/bin/prime-welcome)). That's the
responsible way to ship an opt-in AI feature, not a weaker version of the pitch.
What's still true: the README's comparison table presents "the OS supervisor —
hotkey voice, screen-aware" as the default experience, and it's an opt-in one
chosen in step 5 — a smaller gap than I first described, worth a one-word fix
("can be" instead of "is") rather than a product gap.

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
  otherwise fully brand-themed greeting. Looked at actually dropping it
  (`layer/seed/fastfetch/config.jsonc`'s `"colors"` module) — didn't: the
  file's own comment ties the logo's 5-line top padding to the module list
  being "~19 lines" (`layer/seed/fastfetch/config.jsonc:11-12`), so removing
  the `break`+`colors` lines shifts that balance and risks a worse problem
  (the logo sitting too low against a now-shorter text column) to fix a minor
  one. Left alone rather than trade one cosmetic issue for another without
  being able to see the real terminal render to re-tune it. Still a fair P3 to
  revisit with eyes on it.
- The design-preview gallery itself had rotted in one place and had a gap in
  another (F5, fixed this round): the screen saver now has a frame
  (`layer/branding/previews/screensaver.png` — see it for yourself, it's
  genuinely one of the better pieces of brand work in the repo), and the whole
  gallery was regenerated so every PNG reflects current rendering rather than
  whatever it last happened to be when someone ran the scripts by hand.
- `bar.png`'s right-hand cluster read, on a zoomed static PNG, like a wall of
  bare percentages with no grouping — investigated further and dropped (§9):
  `layer/default/waybar/style.css`'s own stated rule is "spacing comes from
  padding, never from stray margins," and the cluster is already grouped
  logically in `config.jsonc` (`group/status`, `group/stats`). Adding a visual
  divider to satisfy a thumbnail impression would have meant overriding the
  file's own deliberate minimalism for an unconfirmed problem. Not changed.

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
   Prime Search — both genuinely self-explanatory from the screenshots in §4.
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
4. ~~Decide, don't default, on the always-on agent~~ — **already done well,
   correcting myself from an earlier pass of this review.** `prime-welcome`'s
   step 5 already presents it as a real, informed choice (provider picker, a
   local/network-only option, plain language about where the key stays) and
   only turns the add-on on if the person connects one. Fixed the one
   remaining trace of overclaiming — the README's comparison table now says
   "can be the OS supervisor," not "is."
5. **Keep the design-preview gallery regeneration habit going (F5 — fixed this
   round).** The screen saver now has a frame in the gallery, and the preview
   scripts no longer silently fail two-sevenths of their renders. Re-run
   `layer/branding/src/preview-*.sh` as part of any PR that touches a surface
   they cover — it's the fastest way to catch the next PR-18-style gap before
   it ships, and it just caught one.

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
- *Bad update ships to everyone at once* — real risk on any rolling base:
  `stable` fast-forwarding to a release tag is instant and total, with no
  canary step. Added a staged-rollout process to `docs/RELEASE.md` — soak a
  tag on `edge`/the owner's own machine before fast-forwarding `stable`, with
  the shape of a percentage-gated rollout sketched for when the user base
  outgrows "the owner would notice." A process fix, not a code one: nothing in
  `prime-autoupdate` needs to change until the second step is actually needed.
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
is worth planning before the user base is large enough that "ask the owner on
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
| **F5** | P2 | Jobs, Linus | The screen saver (PR #18's headline feature) had zero coverage in the design-preview gallery despite `prime-screensaver --screenshot F` existing for exactly that purpose; the adjacent preview `layer/branding/previews/right-click-menu.png` was stale enough to look like a bug report for a UI that no longer behaves that way. Regenerating the whole gallery to check the new frame surfaced a second, broader bug: `start-menu*.png`, `spotlight*.png` and the `window-*.png` set were silently failing under this environment's `xvfb-run` (`Gtk.init_check()` returning false with nothing but Xvfb's X11 to talk to) — a real gap in the harness itself, not just stale output. | `layer/branding/src/preview-pro-ui.sh:83` (pre-fix, only existing-UI coverage); `layer/bin/prime-screensaver:14,345-347` (`--screenshot`, a pure Cairo render, no display needed); live reproduction this session (`xvfb-run` + `prime-context bar.clock` → 540×101px, vs. the stale 100+px-of-empty-space PNG) | Wired a `prime-screensaver --screenshot` call into `preview-pro-ui.sh`; forced `GDK_BACKEND=x11` on both scripts' `xvfb-run` wrapper (a no-op anywhere it already worked — Xvfb only ever offers X11); regenerated the full gallery, all renders now succeed | S | **Fixed** — branch `polish/preview-gallery-and-release-process` |
| **F6** | P3 | Linus | GTK3/GTK4 split: `prime-welcome` is GTK4 + libadwaita; `prime-start`, `prime-spotlight`, `prime-panel`, `prime-activity`, `prime-screensaver` are GTK3. Not broken today; GTK3 is upstream in maintenance-only mode, a 12-month horizon risk (§8). | `layer/bin/prime-welcome` (`Gtk 4`) vs. `layer/bin/prime-start`, `prime-spotlight`, `prime-panel`, `prime-activity`, `prime-screensaver` (`gi.require_version("Gtk", "3.0")`) | **Proposal, not built (L effort, as instructed):** new GTK windows default to GTK4 + libadwaita from now on; migrate the five GTK3 windows opportunistically, one per future UI-touching PR. The risk I flagged first draft — "`gtk-layer-shell` needs verifying against GTK4, not confirmed compatible" — is resolved: `gtk4-layer-shell` (package `extra/gtk4-layer-shell 1.3.0-1`, typelib `Gtk4LayerShell-1.0`, `Depends On: gtk4 wayland`) is a real, separately-packaged, already-available Arch package, confirmed installed on this machine (`pacman -Si gtk4-layer-shell`). The migration is lower-risk than first assessed. | L | **Partly done** — `prime-panel` (every task window and the password prompt) and `prime-activity` are GTK 4 + libadwaita, in the same surfaces and accent as Settings; Start, Prime Search (layer-shell) and the screen saver remain GTK 3 |
| **F7** | P3 | Linus | ~15 stale local/remote branches (`feat/*`, `fix/*`, `integrate/*`, six `worktree-agent-*`, three `claude/*`) were pre-pivot debris, not unmerged work — e.g. `integrate/release-candidate` differed from `main` by 5,217 insertions / 31,700 deletions, nothing recoverable. | `git diff --shortstat main origin/<branch>` run for every candidate before deletion (13 remote branches: 8 trivially `--merged origin/main`, 5 confirmed superseded by diff stat + commit content — `claude/project-thread-7pdytd` turned out to be PR #8's source branch, already closed per `REDTEAM-2026-10.md`'s "#8" row); 4 more local-only | Deleted, after asking first. 13 remote branches removed (`origin` now has only `main`); 4 local-only branches in this worktree removed. Branches still checked out in other local worktrees (`prime-connect`, `prime-linux.capture/.cloud/.desktop/.diskfix/.install/.integrate/.integrate2`, six `.claude/worktrees/agent-*`) were left alone — removing those deletes whole project directories, a bigger action than "clean up branches," flagged separately rather than assumed | S | **Fixed** |

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

**A second finding dropped the same way, on my own re-check rather than a
sub-agent's:** I first read `bar.png`'s right-hand icon cluster (zoomed) as a
glance-ability problem — similar badges, bare percentages, no visual grouping.
`layer/default/waybar/style.css:1-10` states the file's own design rule
explicitly: *"spacing comes from padding, never from stray margins"* — a
deliberate calm-minimalist constraint the project holds to everywhere else in
the file. Adding a divider between `group/status` and `group/stats`
(`layer/default/waybar/config.jsonc:268-283`, both already-grouped logically)
would violate that stated rule to fix an impression from a zoomed static PNG,
not a confirmed defect at real bar height with real tooltips. Left alone.

**Everything else a red team would normally list here was already found and
fixed by the project's own two prior rounds** (`docs/REDTEAM-2026-10.md`), and I
independently re-verified a sample rather than take the doc's word for it: SSH
default-open (`tests/check-ssh.sh`, 19/19), the owner's-GPU hardcoding
(`tests/check-portable.sh`, passing), idle-math and rollback-loop
(`backends/arch/prime-autoupdate:116-129,436-445`), GPU detection on a hybrid
laptop (`tests/check-gpu-detect.sh`). None of these regressed.

---

## 10. Scores and the honest verdict

Updated after #19, #20 and #21 merged and a further pass closed out F5 and F7,
and corrected the one place I'd been unfairly harsh (the AI-onboarding read in
§1/§6). Shown as before → after so the revision is visible, not just asserted:

| Reviewer | Before | After | Why it moved |
|---|---|---|---|
| **Steve Jobs** | 7 | **8** | The doc self-contradiction is fixed, and on re-reading `prime-welcome`'s actual assistant step I'd understated a real strength (clear, optional, well-consented AI onboarding) rather than found a real flaw — correcting that moved the score, not just the mood. The screen saver — genuinely one of the better pieces of brand work in the repo — now has design-review coverage instead of being the one surface nobody checked before shipping. What's left (F6, the ANSI swatch I chose not to touch) is real polish, not a reason to hold back a point. |
| **Bill Gates** | 6 | **8** | `main` is green. The docs are honest. The design-preview tooling itself had a real bug (silently failing renders) that's now fixed, which matters more than any one stale PNG — it means the gallery can be trusted as a regression check going forward. Added explicit staged-rollout guidance to `docs/RELEASE.md` so "bad update reaches everyone at once" has a documented answer instead of an implicit gap. What's still open and keeps this from a 9: the public `curl \| bash` trust story (L4) is a real pre-launch item, not yet closed, and it's the one thing on this list that's a decision for the owner, not a PR. |
| **Linus Torvalds** | 7 | **8** | The process failure (two unreconciled implementations) is fixed, the repo's branch list now matches reality (13 stale remote branches gone, `origin` down to just `main`), and both findings that didn't survive my own re-verification (GPU-vendor dispatch, the bar-icon grouping) are recorded as dropped rather than quietly removed — the discipline this doc asks of a red team, applied to itself. The one honest point held back: F6 (GTK3/GTK4 split) is real, 12-month-horizon, and correctly stays a written-up proposal rather than an unrequested migration — de-risked this round (`gtk4-layer-shell` confirmed packaged and available), not executed. |

**Ship it to friends? Yes.** The actual install → daily-use → update →
uninstall path was always solid; the problems were `main`'s own test suite,
documentation that described a different product, a design-review gallery that
had quietly stopped working, and a repo full of pre-pivot branch debris. All
four are now fixed. What's left (F6) is a correctly-scoped-down roadmap item,
not a reason to wait.

---

## PRs from this review

- [**#19**](https://github.com/Sean-Morrissey/prime-linux/pull/19) — CI green:
  F2, F3 — **merged**
- [**#20**](https://github.com/Sean-Morrissey/prime-linux/pull/20) — docs truth:
  F1, F4 — **merged**
- [**#21**](https://github.com/Sean-Morrissey/prime-linux/pull/21) — this
  document — **merged**
- **#22** (branch `polish/preview-gallery-and-release-process`) — screen-saver
  preview coverage + preview-harness fix (F5), staged-rollout guidance in
  `docs/RELEASE.md`, the AI-onboarding correction, the GTK4-layer-shell
  de-risking research for F6, and this document's score update

---

## 11. Follow-up rounds (PRs #23–#31) and the design audit

After §10, the owner asked for the distro to be "complete, standalone and
managed by Prime, no AI required", and later for a ruthless design audit
("it all is kinda ugly — not seamless like Windows or a Mac"). What shipped:

| PR | What it closed |
|---|---|
| [#23](https://github.com/Sean-Morrissey/prime-linux/pull/23) | Signed releases: the stable channel only fast-forwards to a tag signed by a key the computer already trusts (L4, mechanism) |
| [#24](https://github.com/Sean-Morrissey/prime-linux/pull/24) | A second account on the same computer can't take over or remove the first one's desktop |
| [#25](https://github.com/Sean-Morrissey/prime-linux/pull/25) | Daily checkup (no AI): disk, failed services, version jumps — speaks up only about something new |
| [#26](https://github.com/Sean-Morrissey/prime-linux/pull/26) | Weekly CI check on whether CachyOS's installer works again (the ISO blocker) |
| [#27](https://github.com/Sean-Morrissey/prime-linux/pull/27) | File History: get a file back from an hour, a day or a week ago |
| [#28](https://github.com/Sean-Morrissey/prime-linux/pull/28) | Settings: one GTK4/libadwaita window for everything (now 23 pages), Super+I |
| [#29](https://github.com/Sean-Morrissey/prime-linux/pull/29) | Prime, one voice: everyday requests without AI (`prime-do`), screenshots that never ask first, the Prime/Hermes roles (`docs/PRIME-AND-HERMES.md`) |
| [#30](https://github.com/Sean-Morrissey/prime-linux/pull/30) | Design round 1: windows float like a Mac/Windows (Tidy = tiling, a setting), solid windows, calm default look, one highlight style, tearing + VRR for games |
| [#31](https://github.com/Sean-Morrissey/prime-linux/pull/31) | Design round 2: three front doors (Start, Prime Search, Settings), a Mac-style auto-hide dock, title bars that rebuild themselves after a Hyprland update, a guard against the owner's own agent leaking into a friend's install |

**Scores for the design audit** (the panel scored the shipped desktop, from
real renders and the VM boot, not the code):

| Reviewer | At the audit | Now | Why |
|---|---|---|---|
| **Steve Jobs** | 4 | **7** | The two things that made it feel unlike a Mac or Windows — tiling by default and see-through windows — are gone; one look, one highlight, three doors, a dock that stays out of the way. Held back: the pickers are still rofi (a different toolkit from Start/Settings), and nobody has yet looked at it on the owner's real screen. |
| **Linus Torvalds** | 7 | **8** | Tearing and VRR now actually work (the old `immediate` rule was inert), lighter blur, one bar process instead of two, a fragile plugin rebuild made self-healing and tested. The kernel is correctly left to CachyOS. Held back: F6 (GTK3 windows) is still open. |
| **Bill Gates** | 6 | **7** | It now holds together as a product for two people: Settings for everything, no terminal, updates and repair that run by themselves. Held back from 9: no working ISO (upstream), and the release-signing key doesn't exist yet — signed updates can't be verified until the owner runs `tools/release-sign.sh --new-key` once. |

**Still open, in order:** the owner's release key (a decision, not a PR); the
ISO, blocked upstream (watched weekly by #26); F6, GTK3 → GTK4; a look at the
desktop on the owner's own monitor (VRR, scaling) — the only check CI can't do;
`layer/branding/previews/bar.png` predates the new default look (rendering it
needs a Wayland compositor the build sandbox lacks).
