# Prime Linux — ship gates

The bar: this must be usable by a student who has never seen Linux, at the level of a
macOS Setup Assistant and a Windows out-of-box experience. Not "it boots" — **it is
ready to hand to someone else**.

This file is the acceptance checklist. Every gate is pass/fail and every gate names how
it is verified. A gate cannot be marked ✅ by reading code; it needs the stated
observation or command output. `docs/PROJECT-STATE.md` stays the source of truth for
*state*; this file is the source of truth for *what "ready" means*.

Status legend: ✅ verified · ⚠️ partial · ❌ not met · ⏳ awaiting evidence

**Last audit: 2026-09-25** — three independent reviews; see
[`RED-TEAM-REVIEW.md`](RED-TEAM-REVIEW.md) for the P0 register. Statuses below were filled
from that audit's evidence, not from intent.

---

## A. Install and first run (the out-of-box experience)

| # | Gate | How it is verified | Status | Evidence (2026-09-25) |
|---|---|---|---|---|
| A1 | A stranger can download, install and reach a desktop with **no terminal**, in under 10 minutes, with no Linux knowledge. | Boot the published installable media in a clean VM (`tools/vm-boot.sh`), install it, time the run. | ❌ | Boot-verified 2026-09-25 (run 36186698692, `fix/desktop-first-run`): the qcow2 reaches a working KDE desktop — `plasmalogin` active with `kwin_wayland` + `plasmashell` running, serial prompt reads `prime login:`. Blocked from ✅ by two things that are not code: the repo and GHCR package are private, and the **anaconda-ISO install path has never been booted end-to-end** |
| A2 | First login shows a **graphical** wizard: one question per screen, keyboard-only completable, every control carrying an accessible name. No terminal window appears anywhere in the flow. | Drive the wizard with the keyboard alone; run the wizard's accessibility self-check; read the AT-SPI tree. | ⚠️ | The graphical wizard now **ships and renders on first login** — a real boot's framebuffer shows "Prime Linux setup", Step 1 of 9, with the system-info checklist, the timezone question and Not now / Start / Skip. A runtime audit (`test-wizard-gui.py`) builds all 9 steps and confirms every interactive widget and label has an accessible name and a defined focus order. Still partial: nobody has driven it keyboard-only end-to-end nor read the live AT-SPI tree, and the terminal path still exists as fallback |
| A3 | A wrong, expired, or missing API key and a dead network each produce a plain-language next step. Nothing in the flow can be permanently blocked. | Test all three failure paths; confirm the wizard can be finished later from the menu. | ❌ | No key is ever collected; the flow points the student at a `prime connect` verb that does not exist (P0-6) |
| A4 | No jargon reaches the user (no `bootc`, `ostree`, `image`, `systemd`, `polkit` in any user-facing string). Reading level ≤ grade 8. | Grep user-facing strings against the jargon list; read every string aloud. | ⚠️ | "toolchain" (`prime-setup:235`), "verbatim" (`:291`), "atomic image" / "boot menu" (`firstboot.sh:24-33`) |
| A5 | Skip and Esc always work, and the wizard can be dismissed once and recalled on purpose. | Skip-all run; `--decline`; relaunch from app menu. | ⚠️ | `--decline` exists; no Esc, no back, no review step; Ctrl+C aborts silently |
| A6 | The first-run flow boots **offline** — an unconfigured machine still reaches a working desktop. | Install and log in with networking disabled. | ⏳ | Untested; the connection step must degrade without a network |

## B. Daily use (why the student keeps it)

| # | Gate | How it is verified | Status | Evidence (2026-09-25) |
|---|---|---|---|---|
| B1 | Every user-facing surface of the product says **Prime**. No upstream agent branding or distro branding leaks into a surface the user sees. | Inspect bar, wizard, notifications, menus, app names, About screens. | ⚠️ | Owner's desktop renamed and verified on screen; the shipped image contains no agent at all, so its surfaces cannot pass (P0-4) |
| B2 | Updates install themselves, never interrupt work, notify once, and offer "Later" (which is respected). | Sandbox scenarios + one real-machine update rehearsal. | ❌ | Idle gate is effectively always true (P0-8); notifications cannot reach the session, so "Later" is unreachable |
| B3 | No normal task requires a command line. If anything does, it is a bug with a GUI fix listed. | Walk the five tasks a student actually does: notes/homework, browser + school portal, printing, media, files/backup. | ❌ | The entire first-run flow is a command line today; the study surfaces only exist on the owner's machine |
| B4 | Help is where the user is: every custom control explains what it does when asked (right-click / "what is this"), in plain language. | Right-click every custom surface; read the text. | ⚠️ | Works on the owner's desktop (pill explainers + hint footer); not verified inside the image |

## C. Safety and recovery (the part that earns trust)

| # | Gate | How it is verified | Status | Evidence (2026-09-25) |
|---|---|---|---|---|
| C1 | A bad update rolls back by itself and the machine boots the previous version. **Proven on a real bootc machine**, twice, with the log kept. | Deliberately ship a broken image to a throwaway VM; observe two boots and the rollback; keep the journal. | ❌ | Logic fixed on `fix/supervisor-p0-rollback-idle` (82 checks green); the ordering cycle that stopped `prime-boot-verify.service` from running at all is fixed on `fix/desktop-first-run` and a real boot now shows it running and printing its verdict, with no ordering cycle in the journal. Still ❌ because **no rollback rehearsal has ever happened** — nobody has shipped a deliberately broken image and watched the machine put itself back |
| C2 | A student can reset or reinstall the machine alone, with no terminal and no support call. | Follow a written recovery document on a broken VM. | ❌ | No reset/wipe path exists in the supervisor or the CLI |
| C3 | Prime cannot change anything destructive without asking, and every action it takes is audit-logged where the user can read it. | Inspect the capability ladder; attempt a destructive action; read the audit log. | ❌ | The ladder is prose only — no code reads it, while shipped autonomy mutates unattended; the audit log is split across two files and malformed lines are dropped |
| C4 | The user's API key is stored `0600` under their home and never appears in argv, logs, notifications, crash dumps or git. | Grep process tables, journal, notifications and the repo after a full setup run. | ❌ | Nothing collects a key yet (P0-6); untestable until `prime connect` exists |
| C5 | Backups exist, run without user action, and a restore has actually been performed once. | Restore a deleted file from a real backup. | ❌ | Design only |
| C6 | When the screen is black or Prime will not answer, there is a documented offline path that does not depend on our servers. | Follow it on a VM with networking off. | ❌ | Not written |

## D. Build and publishing (can someone else ship this?)

| # | Gate | How it is verified | Status | Evidence (2026-09-25) |
|---|---|---|---|---|
| D1 | An **installable artifact** (ISO and/or qcow2) is produced by CI, downloaded, and booted in a VM. | GitHub Actions run + artifact name/size/sha256 + boot observation. | ⚠️ | **Met 2026-09-25**, twice. First artifact: run 36173135111 (4704 MiB, sha256 `3bfc04dc…`) — text login only. Current: run 36186698692, `prime-linux-qcow2` 4802 MiB sha256 `a71662e09ca97c7a0f6809dce3e860ce44c3a53a264bbab9241930c374091694` — boots to a **working KDE desktop**, hostname `prime`, wizard on first login. Partial because the `prime-linux-anaconda-iso` (5189 MiB) has never been booted, and the branch's CI is not green (the SBOM/attest job fails) |
| D2 | Base image pinned by digest; every GitHub Action pinned by SHA; image signed **and verified**; SBOM published. | `skopeo inspect`, workflow diff, `cosign verify`, SBOM artifact. | ⚠️ | Branch `fix/installable-artifact` pinned the base to the `stable` tag with a recorded digest (`sha256:94b81908…`), the builder by digest, every action by full SHA (each verified against the GitHub API), and `uv` to 0.12.19 with per-arch sha256 — plus a new verify-and-attest job (`cosign verify` + SPDX SBOM + attestation). Still partial: that job has **never run**, and BlueBuild's schema takes a tag, not a true `@sha256:` pin |
| D3 | A stranger with no secrets can rebuild the image from a clean checkout. | Rebuild from a fork with no repo secrets set. | ❌ | Repo **and** GHCR package are private: anonymous pull 401, owner-token pull 403 (P0-1) |
| D4 | `docs/PROJECT-STATE.md` matches reality on its verified date — no gate above depends on a stale line. | Re-read after this audit; fix the file in the same commit as the code. | ❌ | Says interview beats are "not written" (they are, as `prime-setup`), says qemu is not installed (it is), and `README:130` claims `ID=primelinux` (must stay `fedora`) |

## E. Judgment call

| # | Gate | How it is verified | Status | Evidence (2026-09-25) |
|---|---|---|---|---|
| E1 | A named human is responsible for the first unattended install on someone else's real hardware, and the machine is replaceable if it fails. | Written decision in this file, with the date and the name. | ❌ | Not yet named |

---

## How a gate gets marked ✅

1. Run the stated verification on the real artifact (VM, or the shipped image — never on
   a development machine that the product is not allowed to touch).
2. Paste the evidence next to the gate: run ID, artifact hash, command, or the exact
   observation.
3. If it only passes in a sandbox, it is ⚠️ partial, not ✅.
