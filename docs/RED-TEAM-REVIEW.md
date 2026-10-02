# Prime Linux — red-team review 1

**Date:** 2026-09-25 · **Reviewers:** a 30-year senior Ubuntu/Fedora OS developer, a 30-year
senior Apple software engineer (HIG + accessibility), and a senior systems engineer for the
update/security/recovery surface. Three independent audits, read-only, run against this repo.

**Method / rules of evidence:** every claim below is either VERIFIED (file:line or command
output) or explicitly marked hypothesis. Nothing is marked passing because the code looks
right. Acceptance bar: [`SHIP-GATES.md`](SHIP-GATES.md).

---

## Verdict

**Not shippable, and the gap is not where the state doc says it is.** The design layer is
genuinely good — atomic image, supervised updates, an identity interview, a permission
ladder. What is missing is the *delivery path* and three safety-critical defects. In
plain terms:

1. **Nobody can get it.** Repo is private; GHCR answers `401` anonymously and `403` even
   with the owner's token.
2. **No installable media has ever been built.** Every `build-disk.yml` run has failed
   inside `bootc-image-builder` on `mount: permission denied`.
3. **The shipped image does not contain the product.** The recipe installs neither the
   resident agent nor the Hyprland session the README promises.
4. **First run is a terminal.** The desktop route that the design of record mandates was
   never written, and the flow never asks for an API key — it tells the student to run a
   command that does not exist.
5. **The update engine can reboot the machine in the middle of someone's work, and can
   loop on rollback until the machine is bricked.**

Five themes, eleven P0s. Details and evidence below.

---

## P0 register

| ID | Theme | Defect | Evidence | Owning workstream |
|---|---|---|---|---|
| P0-1 | Deliverability | Repo and GHCR package are private → no third party can pull the image or read the source. | `gh repo view` → `isPrivate:true`; `curl ghcr.io/v2/…/manifests/latest` → **401** anonymous, **403** with the owner token (token lacks `read:packages`) | **Owner decision** |
| P0-2 | Deliverability | No installable artifact exists — 5/5 `build-disk.yml` runs failed: `RuntimeError: mount: /run/osbuild/containers/storage: permission denied` (qcow2), `…/tree/dev: permission denied` (iso). | run IDs 35645798688, 35644584532, 35643162249, 35643057867, 35642775715 | W2 (build) |
| P0-3 | Deliverability | The project's own discriminating bisect (`diag-builder.yml`) **has never been run** — the investigation is stalled exactly where its own doc says it resolves. | `gh run list --workflow='diag builder'` → empty | W2 (running it now) |
| P0-4 | Product truth | The image contains neither the resident agent nor Hyprland, yet README:12/36 promise both. The "differentiator" is not in the product. | `recipes/recipe.yml:47-53` (Hyprland deliberately not installed), no agent install step; README:12,36 | **Owner decision** |
| P0-5 | First run | First login opens a **terminal** (`konsole`/`kitty`/…) running `prime-setup`, contradicting the locked decision to use the desktop route; no `desktop-plugins/` exists. | `prime-first-login.desktop:6`; `first-login-interview.sh:30-51` | W1 + later D-route work |
| P0-6 | First run | "Asks for your API key" is **false**, and the command it points at does not exist: Beat 5 prints `run: prime connect`, but the CLI has no `connect` verb and nothing writes `provider.yaml`, a key file, or `spend-cap.yaml`. | `prime-setup:276,281,416`; `prime:218-229`; repo-wide grep for `cmd_connect` | W4 (connect) |
| P0-7 | First run | The promised "sixty-second open" (hardware probe before the first question) never happens — `hw-probe.sh` is written and working but nothing calls it at first run. | only caller is `backend-btrfs.sh:120`; INTERVIEW.md:59-85 | W1 (steered) |
| P0-8 | Updates | **Idle math is dimensionally wrong** (microns vs seconds) → the "only reboot when idle 10 min" gate is effectively always true. The machine can restart mid-work. | `prime-autoupdate:91` (µs) vs `:98` | W3 (running) |
| P0-9 | Updates | **Rollback has no termination condition** — post-boot restore+reboot never consults `FAIL_LIMIT`, so two deployments can flip-flop forever. Brick. | `prime-autoupdate:327-341` vs `:212` | W3 |
| P0-10 | Updates | **Boot-time health check produces false failures**: it demands a default route, a DRM output and a logind session *at boot, before login*. A Wi-Fi laptop, a closed lid, or a login screen → "unhealthy" → rollback → reboot → repeat. | `prime-boot-verify.service:4`; `backend-bootc.sh:172-176,180-186,189-197` | W3 |
| P0-11 | Truth | The **state-of-record is stale**, so every other agent works from wrong facts: "interview beats not written" (they are, as `prime-setup`), "qemu not installed" (it is), `README:130` claims `ID=primelinux` (must be `fedora`). | PROJECT-STATE.md:32,79-81; README.md:130; `check-os-release.sh:36` | W4 |

### Notable P1s (fixed next, not first)

- Client-side **signature verification does not exist** — `cosign.pub` is committed and never
  used by any shipped policy; "signed" is CI-side only.
- Auto-update pulls from a **private registry with no credential mechanism** on the machine.
- The **capability ladder is prose only** — no code reads it, yet shipped autonomy performs
  update and rollback unattended, which the ladder pins at *approve each*.
- **Notifications can never reach the user**: the update unit is a system service with no
  session bus and every `notify-send` failure is swallowed → the "Later" 12-hour deferral is
  unreachable, so a notification-based update flow is fiction.
- **"Stops after 2 bad boots" is defeated** — a healthy rollback boot clears the failure
  counter, so the same broken image is re-staged forever.
- Base image unpinned (`aurora:latest`), `uv` installed by piping an unpinned remote script
  into a root shell, `bootc-image-builder` unpinned, actions pinned inconsistently.
- Accessibility: Orca hardcoded off; no validation or error messages; no undo; essential
  text in ANSI-dim; rofi surfaces expose no AT-SPI tree; hard-coded px font sizes ignore
  user scaling and HiDPI.

---

## Decisions taken by the two leads

1. **The user-facing name is Prime, everywhere.** The agent is Prime; Hermes is only the app
   it runs on. No surface the student sees may say otherwise.
2. **No terminal anywhere in the user path.** The CLI stays as a fallback for power users and
   as the testable core; the wizard is graphical, keyboard-complete, one question per screen.
   (This supersedes "logic in shell + YAML" only in *presentation* — the shared state machine
   stays the single source of question logic.)
3. **Every gate in `SHIP-GATES.md` needs a named verification.** Sandbox-only = ⚠️ partial.
   No ✅ from reading code.
4. **The docs follow the code in the same commit** (project rule 1) — and `PROJECT-STATE.md`
   gets a "known blockers before sharing" section so no agent trusts a stale line again.

## Decisions only the owner can make

- **D1 — How do people get it?** Public repo + public GHCR package (simplest, and the update
  path needs an unauthenticated pull anyway), **or** keep the source private and ship a
  signed downloadable installer. Reviewers recommend: public image, signed, with the client
  verifying the signature — and note that the alternative leaves the auto-update path needing
  per-machine registry credentials, which is worse for a non-technical user.
- **D2 — Does the image ship the agent?** Right now it does not, so the pitch is ahead of the
  product. Either bake the agent + session into the recipe (reviewers' recommendation — it is
  the entire reason this distro exists) or relabel the pitch as roadmap.
- **D3 — Target hardware.** Aurora publishes no NVIDIA image, so an NVIDIA laptop boots
  without accelerated graphics. Either ship the NVIDIA variant for those machines or state
  honestly: AMD/Intel only, for now.

---

## In flight (started from this review)

| Workstream | Scope | State |
|---|---|---|
| W1 first-run wizard | Graphical `prime-welcome`, shared state machine with the CLI, accessibility self-check, tests | running |
| W2 build/media | Run the never-run bisect, fix the disk build, produce a qcow2, boot it here, supply-chain pins | running |
| W3 updates/rollback | P0-8/9/10 fixes + notification delivery, bad-digest memory, audit unification, regression tests | running |
| W4 connect + docs | `prime connect` (key handled correctly, never in argv/logs), doc-truth pass, blockers section | running |

Every workstream lands on its own branch. Nothing merges to `main` until its gate evidence
exists.
