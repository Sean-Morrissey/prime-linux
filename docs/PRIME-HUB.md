# Prime Hub — design spec

Status: draft 1 · 2026-10-19 · owner: Sean

### Decisions (2026-10-19)
1. **Safety: vetted by default, unlock to go further.** The store shows only
   vetted catalog apps. An *Advanced* toggle reveals "install anything from AUR
   (unverified)" with a ⚠ warning and the PKGBUILD shown first. Safe default, no
   ceiling.
2. **Backend: Prime decides per-app.** The catalog's ordered `backends` list
   picks native-vs-Flatpak per app (native where deep system/GPU access helps,
   sandboxed otherwise). User doesn't choose.
3. **Updates: auto, nightly, snapshot first.** App/model updates ride the existing
   nightly `prime-update` — snapshot → update Prime + all recorded apps/models →
   record new versions. Always rollback-able.
4. **Build order: a working app store on the laptop first** — `prime-install`
   engine + catalog (installs for real, CLI-testable), then the GTK store on top.

Prime Hub is one place to **find, install, and manage everything on a Prime
computer** — apps, local AI models, extensions, widgets, settings and commands —
where you *search or browse (or just ask), click once, and Prime does the rest*:
it verifies what you're installing, snapshots first, installs it the right way
for your hardware, writes down exactly what it did, and keeps that record so later
updates never break the machine.

You can also **ask in plain language** — "find me a good free video editor",
"what do I need to stream" — and Prime's AI reads the catalog and your hardware,
recommends, and installs on confirm. That AI is **yours to choose**: a local
model, Claude, OpenAI, or any provider you plug in — set once, used everywhere in
Prime.

This is not "add an app store." Prime already has the hard parts — signed-release
verification (`prime-release-verify`), snapshot-before-change (snapper/btrfs),
an install manifest, reversible uninstall, and a safe ff-only updater. The Hub
points that same **verify → snapshot → install → record → keep-updatable** loop
at *everything the user installs*, behind one GTK front door.

---

## 1. The promise

> Search or browse. Click. It just works — and it keeps working.

Four guarantees, in plain language, that every install through the Hub must meet:

1. **Safe to install** — Prime checks the source and signature/checksum before
   anything lands, and refuses or warns clearly when it can't vouch for it.
2. **Safe to the system** — a snapshot is taken first, so any install can be
   rolled back to the exact prior state.
3. **Set up, not just dropped in** — dependencies, GPU/driver wiring, config and
   launch entries are handled so the thing actually runs the first time.
4. **Safe to update forever** — every install is recorded (what, which version,
   which backend, what it touched), so Prime can update it later without guessing
   and without breaking it.

If a step can't be guaranteed, the Hub says so *before* installing — it never
pretends.

---

## 2. Principles (inherited from Prime's DNA)

- **Verify before install.** Reuse the trust model in `prime-release-verify`:
  signatures/tags for Prime's own content; per-backend verification for third
  party (see §6).
- **Snapshot before change.** Every mutating action takes a snapper pre-snapshot,
  same as `prime-update` already does for the layer.
- **Everything is manifested.** No silent state. Each install appends to a
  machine-readable catalog-state file (§5) the way `install.sh` writes its
  manifest for `prime-uninstall`.
- **Reversible.** Anything installed can be removed to the prior state. Snapshot +
  manifest make this true even for messy backends.
- **Update-safe and documented.** The manifest is the contract `prime-update`
  reads to update apps/models safely; nothing is updated that isn't recorded.
- **Local-first, but bring-your-own-AI.** AI defaults to the user's own hardware
  and local models; cloud APIs are opt-in and never required. The provider is
  **interchangeable** — one setting (§4.2) chooses local / Claude / OpenAI /
  OpenRouter / … and *every* AI feature in Prime uses that choice. No feature is
  hardwired to one vendor.
- **Layer-clean.** The Hub ships in `layer/`; user state lives in
  `~/.config/prime` and `~/.local/state/prime`. Never edit `layer/` on an
  installed machine (breaks the ff-only merge) — ship via the repo.

---

## 3. Architecture

```
┌───────────────────────────────────────────────┐
│  Prime Hub  (GTK4 / libadwaita app)            │   prime-hub
│  Apps · AI/Models · Extensions · Widgets ·     │
│  Settings · Commands                           │
└───────────────┬───────────────────────────────┘
                │ calls (no business logic in the GUI)
┌───────────────▼───────────────────────────────┐
│  prime-install  — the install engine (CLI)     │   the "never breaks" core
│   resolve → verify → snapshot → install →      │
│   setup → record → report                      │
└───┬─────────┬─────────┬─────────┬─────────┬────┘
    │flatpak  │aur/repo  │model    │webapp   │addon
    ▼         ▼          ▼         ▼         ▼
 flatpak   paru/pacman  hf/ollama prime-     prime-addon
                        /llama.cpp webapp
```

Three layers, deliberately split so the GUI is thin and everything is scriptable
and testable:

1. **`prime-hub`** — the GTK4/libadwaita app. Pure presentation: reads the
   catalog, shows install state, calls `prime-install`. No install logic lives
   here (so the whole store is usable headless/CLI and testable without a
   display).
2. **`prime-install`** — the engine. One verb set
   (`search / info / install / remove / update / status`) over every backend. All
   four guarantees (§1) are enforced here, once, for all backends.
3. **Backends** — thin adapters: `flatpak`, `aur` (paru), `repo` (pacman),
   `model` (local AI), `webapp` (`prime-webapp`), `addon` (`prime-addon`).

### Existing pieces this builds on
- `prime-release-verify`, `cosign.pub`, `layer/system/release/release-keys.asc` — trust model
- `prime-addon` — the extension engine (Extensions tab is a GUI over this)
- `prime-webapp` — turns a URL into a desktop app (the `webapp` backend)
- `prime-missing-packages`, `paru`, `flatpak`/Flathub (already enabled at install)
- snapper/btrfs pre/post snapshots; `install.manifest` + `prime-uninstall`
- `arch-audit` (installed) — CVE check for repo/AUR packages

---

## 4. The six sections

### 4.1 Apps  (the store)
Browse by category or search; cards with icon, description, size, source badge
(Flathub / AUR / Prime webapp) and a verification badge. One click installs via
the right backend. Categories: **Browsers · Communication · Media & Creative ·
Development · Gaming · Office · AI · Utilities · System**. 40+ curated entries at
launch (see companion `catalog.json`), extensible without a Hub release because
the catalog is data, not code.

**Ask-to-find.** A search box that also takes plain language. Behind it,
`prime-ai` (§4.2, whatever provider the user chose) is handed the catalog as
context plus the machine's hardware, and answers with matching catalog ids and a
one-line why. "A good free video editor" → Kdenlive/OBS/Shotcut cards, installable
on the spot. The AI only ever returns catalog ids — it recommends and explains, it
does not install; the verified `prime-install` pipeline still does every install.
No AI configured? The box falls back to plain keyword search.

### 4.2 AI / Models  (the headline)

**One provider layer, used everywhere.** A single component — `prime-ai` — owns
"which AI am I talking to." It exposes a uniform `ask`/`chat` interface over an
OpenAI-compatible call, and every AI touchpoint in Prime (Ask Prime in Spotlight,
right-click/screenshot actions, ask-to-find in the store §4.1, and anything added
later) goes through it. Switch provider once here and the whole system follows.

**Two tiers:**

1. **Base Prime brain — always present.** Prime ships (installs on first run) a
   **small, CPU-runnable local model** (≈0.5–1.5B, quantized GGUF, a few hundred
   MB) served via llama.cpp. It needs **no GPU and no API key**, so *every* Prime
   machine — including a GPU-less laptop — has working AI for the **base
   functions**: maintenance/update explanations, "what does this command do",
   ask-to-find in the store, and light Ask Prime. This is the floor; Prime's own
   features depend only on this, never on a cloud key.
2. **Bring-your-own, on top — optional and parallel.** The user can add better
   brains and query them directly: **Claude**, **Gemini**, **OpenAI**,
   **OpenRouter**, **Groq**, any OpenAI-compatible endpoint, or a **bigger local
   model** (llama-server on `:8080`, GPU-offloaded where available). Multiple can
   be configured at once; the user picks per-ask, and a default is chosen for
   Prime's own base functions (falling back to the base brain if none set). Keys
   live in the OS keyring, never in the manifest or a plain file.

- **Ask Prime / Ask <provider>** — extends the existing `ai` add-on, now reading
  its provider from `prime-ai` instead of being wired to one backend.
- **1-click local-model downloads** — a curated model catalog (Qwen, Llama,
  DeepSeek, etc.) tagged by size and quant. Prime **reads the machine's VRAM/RAM**
  (it already knows the GPU) and marks each model *fits / tight / won't fit*,
  recommends one, downloads via the right tool (hf-hub / ollama), and wires it
  into `llama-server` + Ask Prime so it's usable immediately. No hand-editing
  model paths.
- Honors the user's local-first setup: on a GPU box it offers GPU offload; on a
  GPU-less box (e.g. the laptop) it says so and suggests an API provider instead.

### 4.3 Extensions
GUI over `prime-addon`: the shipped add-ons (ai, coding, creator, gaming,
student) plus any personal ones in `~/.config/prime/addons.d`. Toggle on/off,
see what each installs, what it needs, what's enabled. Engine already exists —
this is a browse/toggle front end.

### 4.4 Widgets
Pick bar items (the existing pill/module system — `prime-pill`, audio/notify
pills, gpu monitor, etc.) and, later, desktop widgets. Add/remove to the bar
without editing JSON. Backed by the `prime-bar` merge + `elements.json`.

### 4.5 Settings
One front door to the settings surface that already exists: `prime-settings`,
`prime-system-settings`, `prime-default-apps`, theme (`prime-theme`), updates
(`prime-updates-settings`), security (`prime-security`).

### 4.6 Commands
A browsable palette of the ~70 `prime-*` commands with their one-line summaries
(the `# prime:summary=` headers already in each script), searchable, runnable.
Spotlight half-does this today; this is the complete, discoverable list.

---

## 5. The install engine — `prime-install`

The heart of "nothing ever breaks." One pipeline, every backend:

```
resolve   map a catalog id → concrete backend + package/model/url + deps
verify    §6 — refuse or warn BEFORE any change
snapshot  snapper pre-snapshot (skip only for webapps/addons that touch no system pkgs)
install   run the backend non-interactively
setup     deps, GPU/driver wiring, config, .desktop entry, first-run check
record    append to catalog-state (§ below)
report    success + how to remove/roll back; on failure, auto-rollback to snapshot
```

### Catalog-state (the manifest for installs)
`~/.local/state/prime/apps.json` — one record per installed item:

```json
{
  "id": "google-chrome",
  "name": "Google Chrome",
  "backend": "aur",
  "ref": "google-chrome",
  "version": "129.0.6668.89",
  "installed_at": "2026-10-19T15:20:00-04:00",
  "snapshot_pre": 71,
  "verify": { "method": "pgp-keyring", "result": "ok" },
  "setup": ["desktop-entry", "default-browser-offered"],
  "manages_update": true
}
```

This is what makes updates safe: `prime-update` (or a new `prime-apps update`)
walks this file, updates each item with its *own* backend, snapshots first, and
records the new version. Nothing is touched that isn't written down.

---

## 6. Verification (per backend)

| Backend | How Prime vouches before install |
|---|---|
| **repo** (pacman) | Arch signature chain (pacman keyring) — already trusted; `arch-audit` CVE check, warn on known-vuln |
| **flatpak** | Flathub; prefer **verified** publishers, show the verified badge; GPG-signed OSTree commits by design |
| **aur** (paru) | Show the PKGBUILD source + maintainer; pin to a known-good set in the curated catalog; `arch-audit` after |
| **model** | Download from a pinned repo (HF/ollama) with a **recorded SHA-256**; verify the digest before registering |
| **webapp** | URL is HTTPS + user-confirmed; no system packages, so lowest risk; snapshot skipped |
| **addon** | Prime's own content — `prime-release-verify` trust model applies |

Rule: if verification can't reach "ok", the Hub shows **why** and requires an
explicit confirm (or refuses, for `stable`-channel-grade strictness). Never a
silent install.

---

## 7. Catalog data model

`layer/default/catalog/apps.json` (+ `models.json`). Data, not code — so the
catalog grows without shipping a new Hub binary. One entry:

```json
{
  "id": "obs-studio",
  "name": "OBS Studio",
  "summary": "Record and stream your screen",
  "category": "Media & Creative",
  "icon": "com.obsproject.Studio",
  "backends": [
    { "type": "flatpak", "ref": "com.obsproject.Studio", "verified": true },
    { "type": "aur", "ref": "obs-studio" }
  ],
  "setup": ["gpu-encode"],
  "needs": { "gpu": "optional" }
}
```

`backends` is ordered by preference; the engine picks the first that verifies and
suits the hardware. `setup` names reusable post-install hooks (e.g. `gpu-encode`,
`default-browser-offered`, `register-llama-model`).

---

## 8. UI (GTK4 / libadwaita)

Chosen direction: a **real windowed app**, app-store glossy — not rofi.
- libadwaita for native dark-theme/accent match with Prime's look.
- Left sidebar = the six sections; main pane = search + category grid of cards.
- Card: icon, name, summary, source + verified badges, Install/Open/Remove,
  progress inline.
- Thin GUI: every button shells out to `prime-install`/`prime-addon`/etc., so the
  same actions work from the terminal and in tests.
- New runtime deps: `gtk4`, `libadwaita` (+ `python-gobject` if we build it in
  Python, which keeps it consistent with `prime-bar`). Decide language in Phase 2.

---

## 9. Build phases

0. **Workspaces-by-default** (already in flight) — unrelated to the Hub but ships
   now: `prime-bar` auto-pins N workspaces per detected monitor.
1. **`prime-install` engine + catalog schema** — CLI only, no GUI. The whole
   verify/snapshot/record/rollback loop, `flatpak`+`aur`+`repo` backends, 40-app
   catalog. Fully testable headless. *This is the foundation; everything else is
   a view over it.*
2. **`prime-hub` GTK shell** — window, sidebar, Apps tab over the engine.
3. **`prime-ai` provider layer + AI / Models tab** — the interchangeable-provider
   component first (local/Claude/OpenAI/…), then the model catalog + VRAM-aware
   1-click download + provider setup on top of it; repoint the `ai` add-on at it.
   Unlocks **ask-to-find** in the store (§4.1) and makes every AI feature
   provider-agnostic.
4. **Extensions + Widgets + Settings + Commands tabs** — GUIs over existing
   engines (small each).
5. **`prime-apps update` + manifest-driven updates** — wire app/model updates
   into the existing update/snapshot machinery.

Each phase is independently shippable and testable on the laptop before it
reaches a daily-driver machine.

---

## 10. Open questions

- **Language for the GUI** — Python+GObject (matches `prime-bar`) vs Vala/C vs
  GTK-in-Rust. Leaning Python for consistency and hackability.
- **AUR trust policy** — curated allowlist only, or let users install arbitrary
  AUR with a loud warning? (Security vs. breadth.)
- **Model catalog source** — hand-curated list vs. pulling HF metadata live.
- **Flatpak vs AUR default** when both exist — Flatpak for sandbox/safety, or AUR
  for native integration? Per-app override in the catalog either way.
- **Update cadence** — fold app/model updates into the nightly `prime-update`, or
  a separate, user-triggered "update my apps"?

---

## Companion files (to be added with the phases)
- `layer/default/catalog/apps.json` — the 40+ app catalog (Phase 1)
- `layer/default/catalog/models.json` — the local-model catalog (Phase 3)
- `layer/bin/prime-install` — the install engine (Phase 1)
- `layer/bin/prime-hub` — the GTK app (Phase 2)
- `layer/bin/prime-ai` — the interchangeable AI provider layer (Phase 3)
