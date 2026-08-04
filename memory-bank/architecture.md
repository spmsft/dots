# Target Architecture

Living document — refined as design decisions solidify during execution.
See `decisions.md` for the dated rationale behind each choice.

---

## 1. `dots-local` schema (formal, typed)

Replace the current loose flake-output attrset (read ad hoc via
`inputs.dots-local.foo or fallback` in 30+ places) with a `lib.evalModules`
schema defined in `dots` (shared, versioned) and evaluated once in
`flake.nix`. Every module receives an evaluated `dotsLocal` specialArg
instead of the raw `inputs.dots-local`.

Shape (typed axes + open escape valves, per user's multi-axis request):

```nix
dotsLocal = {
  identity = {
    realname, realmail, username, uid, gid, homeDirectory, sshKeyName, ...
  };
  machine = {
    hostname, cpu.march, cpu.barch,
    gpu = enum [ "none" "nvidia" "amd" "intel" ];
    gpuArch = nullable str;          # e.g. "120" for sm_120
    display = { name, resolution, refreshRate } or listOf that (multi-monitor);
  };
  system = {
    distro = enum [ "cachyos" "opensuse" "azurelinux3" "debian" ... ];
    isWsl  = bool;                   # ORTHOGONAL to distro (e.g. Debian-in-WSL)
    isDarwin = bool;                 # macOS, mostly auto-detected via pkgs.stdenv
  };
  context  = enum [ "priv" "work" ... ];   # replaces "profile"
  location = nullable str;                # freeform: home/parents/travel/office/...
  desktop  = { enable, backend (wayland/x11), compositor (niri/none), terminal, renderDrmDevice, ... };
  tune     = { flags.<lang>.<mode> overrides };
  appimages = { localDir, apps.<name> };
  sync     = { tracked = [...] };
  extraModules  = listOf path;       # escape hatch: bespoke per-machine HM modules (stay in dots-local)
  extraOverlays = listOf (pkgs: overlay);  # escape hatch: bespoke packages/inputs from dots-local
  tags     = listOf str;             # open-ended, for anything not yet modeled as a real axis
};
```

Benefits: self-documenting (option descriptions double as docs); typos/
misconfig caught at eval time instead of silently falling through to a
stale default; no more scattered `or` fallbacks to keep consistent.

**Implemented as (post-Phase-9 update — supersedes this section's original
`modules/local/template.nix` sketch below):**
- `templates/local/{flake.nix,appimages.nix,gitignore,host.nix}` — real,
  standalone, syntactically valid files (not a single generated
  `template.nix`, and not a bash heredoc) using `@@TOKEN@@` placeholders.
  `setup.sh` copies these into a fresh `~/dots-local` and runs one
  `sed -i` pass to fill in the identity/machine placeholders, showing
  only the required fields live plus commented-out examples for optional
  axes (mirroring chromaden's real shape) — it does NOT embed a full copy
  of e.g. the tuning defaults table (see section 6). `host.nix` is wired
  in via `extraModules` unconditionally (not commented out, matching
  `appimages.nix`'s own always-present pattern) - deliberately almost
  empty, the standard escape hatch for anything too bespoke to
  generalize (renamed directory `templates/dots-local/` →
  `templates/local/` on 2026-07-19, following the earlier
  `modules/dots-local/` → `modules/local/` precedent - see
  `decisions.md`).
- `dots-local-options` (a real CLI command, `modules/core/scripts.nix`) —
  not a static template file at all — is the actual "see every available
  field" mechanism: it evaluates `dotsLocalEval.options` through
  nixpkgs's own `lib.optionAttrSetToDocList` and pretty-prints path/type/
  default/description live from `modules/local/schema.nix`, so it can
  never drift from the real schema the way a hand-maintained doc could.
  This is *why* the template file itself doesn't need to be exhaustive.
- **Standing rule**: see section 12 below - any schema field change MUST
  also update the template file in the same commit.

---

### 1a. Easy shell vars / init snippets from `dots-local`

Per user request: adding a simple environment variable or a bit of shell
init logic from `dots-local` must be easy — it should **not** require
reaching for the full `extraModules` escape hatch (a whole separate Nix
module file) for something as small as one env var. Add a first-class
`shell` axis to the schema:

```nix
dotsLocal.shell = {
  sessionVariables = attrsOf str;  # merged into programs.bash.sessionVariables
  shellAliases     = attrsOf str;  # merged into programs.bash.shellAliases
  initExtra        = str;          # arbitrary extra bash snippet, appended
};
```

A small module (e.g. `modules/core/dots-local-shell.nix`) picks these up and
merges them into `programs.bash.*`. Since `programs.bash` output flows
through the existing gutter-eval into `.bashrc-nix` (see section 7), this
"just works" through the existing pipeline with zero new plumbing — a user
editing `dots-local/flake.nix` to add `shell.sessionVariables.FOO = "bar";`
gets it applied on the next `apply-dots`, no `dots` changes required.

### 1b. Preserve all existing overlays / package sources — non-negotiable

**Explicit user directive: take great care to preserve overlays, additional
package sources, and the like** throughout the schema/composition rework
(these are exactly the kind of thing that's easy to accidentally drop while
restructuring `flake.nix`). Current inventory that MUST survive unchanged
in behavior:

- Flake inputs: `nixpkgs`, `nixpkgs-quarto-pin` (pinned quarto 1.8.26 +
  pandoc 3.1.11.1 combo), `home-manager`, `nur`, `nixgl`, `niri`,
  `noctalia` (+ its `noctalia-qs` sub-input — **intentional override, do not
  remove**, see decisions.md), `noctalia-qs`, `snippets-ls`, `bookokrat`.
- Overlays applied in `mkProfile`: `nur.overlays.default`,
  `niri.overlays.niri`, `noctalia-qs.overlays.default`, `externalOverlay`
  (defines `pkgs.external.snippets-ls`, `pkgs.external.bookokrat` [with
  `doCheck = false`], `pkgs.external.quarkdown`, and the `quarto`/`pandoc`
  package substitution from `nixpkgs-quarto-pin`), plus the conditional
  `tuneOverlay` (global-scope package tuning, from `package-tuning.nix`).
- `noctalia.homeModules.default` imported unconditionally in `baseModules`.
- Any new `dotsLocal.extraOverlays`/`dotsLocal.extraModules` escape-hatch
  entries must be **appended to**, never silently replace, this existing
  list — order matters (e.g. `tuneOverlay` needs to see the effects of the
  earlier overlays).
- Whatever schema/composition refactor lands in Phase 1/2 must produce an
  *identical* resolved `overlays` list and `pkgs'` for chromaden's current
  config — verify via `nix eval .#homeConfigurations.priv.pkgs.<pkg>` spot
  checks (e.g. `quarto`, `pandoc`, `bookokrat`) before/after, not just "it
  builds".

**Update (2026-07-19)**: this describes the Phase 1/2-era inventory,
when the goal was "don't lose anything *accidentally* mid-refactor." A
later, deliberate flake.nix necessity audit found `nur`/`nixgl` have
zero consumers anywhere - both are now commented out (not deleted) per
explicit user decision (see `decisions.md`). An authorized exception to
the framing above, not a silent reversal - the "no accidental drops"
intent still stands for everything else.

**Update (2026-08-03)**: `nixpkgs-quarto-pin` (and its `quarto` overlay
substitution) has been **deliberately removed** as part of the vk
Quarto→MyST/Pandoc migration (see `decisions.md`) - `vk` now renders
through plain-nixpkgs `mystmd`/`pandoc`/`typst`, none of which need a
pinned nixpkgs revision. This is an intentional current-state change,
not accidental drift; the rest of the flake-input inventory above is
still accurate.

### 1c. When config loses its home in `dots`, document its `dots-local` replacement

**Explicit user directive.** As Phase 1/2 strip host-specific and
per-machine config out of `dots` (in favor of `dotsLocal` fields), some
existing config will no longer have anywhere to live in `dots` at all (e.g.
today's hardcoded `renderDrmDevice`, SSH identity filenames, CUDA arch
flags, per-host `power-toggle.sh` resolution/output-name, appimages
manifests). Whenever this happens:

- **Do not just delete it and move on.** Add/update a documentation file in
  the `dots` checkout (near the relevant schema/template, e.g.
  `templates/local/flake.nix` plus prose docs) that shows exactly
  what to add to `dots-local/flake.nix` to reproduce that config.
- This is in addition to (not instead of) the schema itself being
  self-documenting via option descriptions, AND `dots-local-options`
  (section 1's "Implemented as" note) making that documentation queryable
  live — concrete worked examples in the template still matter though,
  especially for fields that used to be inline Nix (e.g. the power-toggle
  script's display name/resolution, or CUDA `cmakeFlags` overrides) and
  are now data in `dots-local`.
- Practically: maintain a per-axis "how to configure this in `dots-local`"
  reference (README.md's "Adding a New Host" section, or expanded
  commented-out examples in `templates/local/flake.nix`) that's
  updated in the same commit that removes the old home for that config.
  Never let "it's now overridable via dots-local" be an undocumented,
  tribal-knowledge fact.
- Apply this retroactively too: as Phase 2 removes
  `profiles/priv/hosts/<name>.nix` files, whatever host-specific data they
  contained needs a documented `dots-local` equivalent before the old file
  is deleted, not after.

## 2. Composition via explicit dependency rules (replaces profile hierarchy)

Today: `profiles/common/home.nix -> profiles/priv|work/home.nix ->
profiles/<profile>/hosts/<hostname>.nix` — a static directory chain that
*requires* a committed file per host to exist, and hardcodes host-specific
values inline.

New: `modules/composition.nix` always imports `modules/core/*` (the true
minimal, fast-bootstrap baseline — no GUI/AI/tuning unless an axis asks for
it), then applies a small ordered list of **declarative rules** —
`modules/rules.nix`, pure data, easy to read/extend:

```nix
# modules/rules.nix
{ dotsLocal, lib, ... }:
[
  { when = d: d.context == "priv";          set.suites.tui-apps.enable = true; }
  { when = d: d.context == "work";          set.suites.cloud-tools.enable = true; }
  { when = d: d.machine.gpu == "nvidia";    set = { features.llama-cpp.enable = true; suites.ai-apps.enable = true; }; }
  { when = d: d.desktop.compositor == "niri"; set.features.niri-noctalia.enable = true; }
  { when = d: d.system.isWsl;               set.features.opener.backend = "wsl"; }
  # ...
]
```

`composition.nix` folds these with `lib.mkIf (rule.when dotsLocal) (lib.mkDefault ...)`
semantics (rules set *defaults*, so an explicit per-machine override — via
`dotsLocal.extraModules` or a thin escape-hatch file — always wins). This is
literally the "simple dependency rules... if AI hardware enabled, pull in AI
packages" mechanism the user asked for, kept in one small, greppable file
rather than scattered across host files.

Consequences:
- No more requirement for a real `hosts/<hostname>.nix` file to exist —
  most machines need **zero** custom Nix code, only a `dots-local/flake.nix`
  with axis values.
- The (currently broken) `work` profile issue disappears: `work` becomes
  `dotsLocal.context = "work"`, a data value, not a missing directory.
- `modules/distros/*` (dead/vestigial registry) - originally sketched here
  as something to repurpose into real per-distro metadata; ended up
  **deleted entirely instead** post-Phase-9 (see decisions.md's
  "modules/distros/* deleted" entry) since nothing ever needed it and it
  had drifted out of sync with the real alien-package distro list.
- `cloud-tools` (currently defined but never imported anywhere) becomes
  available like every other suite, axis-defaulted.
- True one-off host quirks (e.g. a power-toggle script hardcoded to
  `eDP-1 @ 2560x1600`) get parametrized into `dotsLocal.machine.display`
  fields feeding a generic feature. Anything too bespoke to generalize uses
  `dotsLocal.extraModules` (private repo only, never `dots`).
- `flake.nix` likely collapses `profileDefinitions` + `mkProfile{profileName}`
  into a single `mkHomeConfig` (+ an `-opt` build-perf variant, since that's a
  build axis not a config axis). **User-facing naming change** — needs a
  checkpoint decision before executing (see `open-questions.md`).

---

## 3. Shared platform/OS detection (consolidates clipboard.nix + opener.nix)

Today, `clipboard.nix` and `opener.nix` each independently declare an
identical `backend = enum [ "wayland" "x11" "wsl" "macos" ]` option and their
own command tables. Must support **Linux (Wayland/X11) + WSL2 + macOS** for
these "essentials" per user's explicit requirement.

New: one `modules/core/platform.nix` (or a `platform` value computed in
`flake.nix` and passed as a specialArg) derives a single normalized value:

```nix
platform =
  if dotsLocal.system.isWsl then "wsl"
  else if pkgs.stdenv.isDarwin then "macos"
  else if dotsLocal.desktop.backend == "x11" then "x11"
  else "wayland";
```

`clipboard.nix`/`opener.nix` consume this `platform` value directly instead
of re-declaring their own enum + fallback logic. Command tables
(copy/paste/open per platform) can also be centralized in
`modules/core/platform.nix` so both features just look up
`platformCommands.${platform}.copy` etc., removing the duplicated
`wayland/x11/wsl/macos` attrsets currently in both files.

Follow-up candidates for the same treatment (not required immediately, but
flagged): `network.nix` (ssh-agent socket path differs on macOS), `viewer.nix`
(image viewer choice may need a macOS path).

---

## 4. Alien packages: unify discovery + add Debian

- `modules/flake/alien-package-specs.nix` (flake-level) and
  `modules/core/alien-packages.nix` (HM-level) each independently implement
  the same `*.{distro}-packages.nix` file-discovery algorithm. Extract into
  one shared pure function, consumed by both call sites.
- Add an `apt` backend to the `update-alien-packages` script + a
  `*.debian-packages.nix` spec convention.
- **Preserve the cross-manager orphan-detection fix** (see decisions.md
  2026-07-18 "Alien-package orphan detection") when unifying/refactoring
  this system - `get_all_required()`'s union-based orphan check and the
  removal-loop safety net must carry forward into whatever the unified
  implementation looks like. This was a real, dangerous false-positive bug
  found on the live system (would have uninstalled a needed package); do
  not regress it while consolidating the two discovery implementations.
- Backfill Debian specs for CLI-relevant features first (git, network,
  dev-tools, clipboard/opener essentials, tui-apps CLI subset). GUI/AI specs
  can follow once there's an actual Debian machine to verify against.
- **Known gap, explicitly flagged**: Debian support will be structurally
  ready but runtime-unverified until tested on real hardware.

---

## 5. `mkAppSet` helper (kills repeated suite boilerplate)

Every suite hand-repeats the same triple for each package: enable flag ->
`home.packages` entry (via `alien.mkEntry`) -> `alienPackages.enabledPackages`
entry. gui-apps.nix does this 26 times. New helper in `modules/core/lib.nix`:

```nix
mkAppSet = { cfg, alienNames ? {} }:
  # cfg: attrset of { <name> = { enable = bool; pkg = derivation; }; }
  # alienNames: optional { <name> = "alien-spec-name"; } override (defaults to <name>)
  {
    packages = filter (p: p != null) (mapAttrsToList
      (name: v: alien.mkEntry v.enable (alienNames.${name} or name) v.pkg) cfg);
    alienEnabled = filter (n: cfg.${n}.enable) (attrNames cfg);
  };
```

Migrate gui-apps, tui-apps, pim-apps, scanning, sixel-tools, cloud-tools,
network, dev-tools, ai-apps onto it. Regression-checked by diffing resolved
`home.packages` / `alienPackages.enabledPackages` before/after per suite
(must be identical).

---

## 6. Tuning defaults: single source of truth

Currently duplicated (and already drifted) across `tune-support.nix`
(home-level, local/wrapped scopes), `package-tuning.nix` (flake-level, global
scope via overlay), and `setup.sh` (bootstrap template). Consolidate into one
data file (`modules/core/tune-defaults.nix`) both Nix consumers import.
`setup.sh` stops embedding a copy — generated `dots-local/flake.nix` only
shows override examples.

---

## 7. Shell bootstrap: KEEP the gutter-eval double build; retarget the hybrid file only

**Revised twice now — investigated the actual current implementation, which
was more nuanced than first assumed.** The double-HM-eval ("gutter eval")
mechanism that captures a clean `.bashrc`/`.profile` from a secondary
evaluation stays as-is; there were good reasons for it and we're not
litigating that again.

Actual current state (confirmed by reading `nixon.nix` + inspecting the live
system):
- `~/.bashrc-nix` / `~/.profile-nix` — **already** the pure gutter-eval HM
  output, `home.file`-managed, correctly separated. **No change needed
  here.** (These filenames are already taken/in-use — do NOT reuse them for
  anything else.)
- `~/.bashrc` / `~/.profile` — **also** `home.file`-managed
  (`lib.mkForce`'d) by `nixon.nix`, but contain a hand-authored "NIXON
  gatekeeper" hybrid script (NIXON on/off toggle, `nixon`/`nixoff` aliases,
  editor discovery, LS_COLORS via vivid, fzf/zoxide wrappers, hardcoded `bf`
  butterfish alias, etc.) that conditionally sources `.bashrc-nix` only when
  `NIXON=1`. **This is the part that still fully owns the user's real
  dotfiles** rather than "leaving hooking in to the local user" (the
  original ask).

Fix: move the hybrid/gatekeeper content to a **new, third filename** — since
`-nix` is already taken by the pure HM output — e.g. `~/.bashrc-dots` /
`~/.profile-dots` (exact suffix confirmed with user: "-dots" or similar,
avoiding collision with their existing `.bashrc-nix`). `nixon.nix`:
- keeps writing `.bashrc-nix`/`.profile-nix` exactly as today (unchanged)
- writes the gatekeeper hybrid script to `.bashrc-dots`/`.profile-dots`
  instead of `lib.mkForce`-ing the real `.bashrc`/`.profile`
- does **not** touch the real `~/.bashrc`/`~/.profile` via `home.file`/
  `lib.mkForce` at all anymore
- a small idempotent, additive-only `home.activation` step (or a one-time
  `setup.sh` step) ensures the real `~/.bashrc`/`~/.profile` source
  `.bashrc-dots`/`.profile-dots` — appends the source line only if not
  already present (detected via a sentinel comment), never overwrites or
  removes existing user content. This is the literal "leave hooking in to
  the local user" the original ask described.

Bug found along the way (fix regardless, Phase 0): the gatekeeper script
sources `~/.bashrc_core` (underscore) but the real file on disk is
`~/.bashrc-core` (hyphen) — a naming mismatch means the GTK/QT theme env
vars in that file are silently never loaded. Fix the underscore -> hyphen
typo. Note `~/.profile-core` (hyphen, matches) has no bug — only the bashrc
one is broken.

This also still resolves the duplicate/inconsistent `bf` butterfish alias
(hardcoded in `nixon.nix`, diverging from `butterfish.nix`'s option-driven
version) as a side effect once the hybrid script's alias section is
reconciled with `butterfish.nix`'s real config instead of hardcoding the
endpoint again.

**Not a bug, do not touch:** `flake.nix`'s `noctalia` input has
`inputs.noctalia-qs.follows = "noctalia-qs"`, which currently produces a
"has an override for a non-existent input" warning during `nix eval`
(upstream `noctalia` flake doesn't currently declare that input itself).
User confirmed this override is intentional/needed — leave it as-is despite
the warning.

This phase needs a **live checkpoint** (shell bootstrap is hard to fully
validate via `nix eval` alone).

---

## 8. Script naming convention

Consolidate `install-<x>` / `uninstall-<x>` pairs (llama-cpp, pi, graphify)
into single `setup-<x> {install|remove|update}` commands, sharing one bash
boilerplate library (dedupes the ~5x copy-pasted color/header/gum-detection
code currently in `scripts.nix`, `dots-local.nix`, `alien-packages.nix`).
`apply-dots`/`update-dots`/`dots-sync`/`update-alien-packages`/
`appimage-update` stay as-is (out of scope, already established).

---

## 9. Externalize large embedded scripts

`ai-apps.nix` (1052 lines total, ~800-line embedded Python for grabcontext),
`viewer.nix` (~360 lines bash), `clipboard.nix` (~140 lines bash),
niri-noctalia's helper scripts — move to real files next to their module
(`modules/features/<name>/scripts/*.py`/`*.sh`), read via `builtins.readFile`
/ `pkgs.writers.writePython3Bin`. Mechanical, behavior-preserving, done
per-module with an eval check each time. Gives the currently-empty `bin/`
directory (or a new `scripts/` dir) an actual purpose; enables normal
shellcheck/editing.

---

## 10. Core tool list review (non-aggressive) - resolved

Original approach: `modules/core/default.nix`'s package list wasn't
aggressively trimmed - only genuinely mislabeled/accidental inclusions
were flagged for confirmation first (`psutils` = PostScript utils, not
process utils; `t3` = a tee-replacement, not tree-related, despite its
comment claiming otherwise), leaving plausible-but-unconfirmed overlaps
(pagers, HTTP fetchers) alone pending explicit user input.

**Resolved** (post-Phase-9 core-minimization round): user confirmed
removing `psutils`/`t3`/`moor`/`ov`; kept `curl`+`wget`, moved `curlie`
to `suites.network-tools` as opt-in. Pagers/HTTP-fetcher overlap
confirmed intentional, kept as-is (see `decisions.md`/
`open-questions.md`). Everything else (ripgrep/fd/bat/lsd/zoxide/fzf/
starship/btop/helix/dust/tokei/procs/tailspin/tealdeer/difftastic/
vivid/gum/...) is exactly the "modern CLI / rust rewrite" toolkit the
user wants kept.
- Found in passing: `programs.ssh.matchBlocks` (used in `chromaden.nix`) is
  deprecated in favor of `programs.ssh.settings` — a harmless warning today,
  worth fixing opportunistically.

---

## 11. Bug fixes bundled along the way

Concrete list (laputa's `features.scanning` typo, copy-pasted "Laputa Machine
Configuration" header comments on chromaden.nix/triomino.nix, missing
`gcc15`/`gcc15-libs` alien spec, dead `niriPkg` conditional in
niri-noctalia.nix, `dots-local.nix`'s dead sync-config.json path reference,
double-invoked `sync.sh` per activation, `pim-apps.nix`'s `mkOption` vs
`mkEnableOption` style inconsistency, `sd-switch.nix` missing an `enable`
option, librewolf's dead HM config block, `programs.ssh.matchBlocks`
deprecation).

---

## 12. Standing "keep-in-sync" rules (consolidated)

This whole re-architecture repeatedly ran into the same failure pattern:
something (a doc, a template, a comment) silently drifted from the real
source of truth across several phases, undetected until a fresh-eyes pass
or an actual fresh-setup test surfaced it (see `learnings.md`'s "AGENTS.md
drift" and "conditionally-omitted key vs. conditionally-empty value"
entries, plus the `features.network` ssh-assertion bug it caused). To stop
this recurring indefinitely, every "if you change X, you must also touch
Y" rule discovered/established over the course of this project is
collected here in one place, rather than left scattered across dated
`decisions.md` entries where a future session might not think to look:

1. **Change `modules/local/schema.nix` (add/rename/remove a `dotsLocal`
   field)** → also update:
   - `templates/local/flake.nix` (the real template `setup.sh`
     copies + fills in) - only needs the common/illustrative fields as
     commented examples, not exhaustive (see section 1's "Implemented
     as" note for why).
   - `setup.sh`'s "Next steps" echo output, if the change affects what a
     brand-new user should do first.
   - Then **run the fresh-setup regression test**: sandboxed `$HOME`, run
     just `setup.sh`'s identity-generation half, `nix eval`/`nix build`
     the result. This is the *only* thing that catches "works for
     chromaden (already fully configured), breaks for a brand-new
     machine" bugs - chromaden's own `nix eval`/`nix build` checks cannot
     surface them, by construction (every field is already set there).
   - `dots-local-options` needs no manual update - it's generated live
     from the schema every time it runs.
   - Full write-up/precedent: `decisions.md`'s "setup.sh must track
     schema.nix" and "setup.sh's embedded heredoc replaced with real
     template files" entries.

2. **Change `modules/core/tune-defaults.nix` (the tuning flag defaults
   table)** → check whether any machine's `dots-local` has a `tune.flags`
   override that's now either (a) redundant (identical to the new
   default - safe to delete, see the 2026-07-19 "redundant tune.flags
   override removed" decision) or (b) meaningfully different (a real,
   intentional per-machine override - leave it, but double check it's
   still achieving what it originally intended given the new baseline).

3. **Change anything under `modules/features/*.nix`/`modules/suites/*.nix`
   that a user might reasonably want tracked/synced (new config file
   under `~/.config/*`, etc.)** → consider whether it needs a new named
   syncable in `modules/core/syncables.nix`, and whether the owning
   feature module should assert that syncable is enabled (see
   `modules/features/niri-noctalia.nix`'s assertion for the pattern) -
   remembering the syncable itself must NEVER be auto-enabled by the
   feature, only asserted-for, so temporarily disabling a feature never
   silently drops sync coverage.

4. **Rename/move a module file** (as happened repeatedly this session:
   `composition-rules.nix`→`rules.nix`, `dots-local/`→`local/`,
   `features/git.nix`→`suites/git-tools.nix`, etc.) → grep the *entire*
   repo (not just `modules/`) for both the old path and old option
   namespace before considering it done - stale references hide in
   `AGENTS.md`, `README.md`, `OVERVIEW.md`, `SYNC.md`, and `memory-bank/*.md`
   just as easily as in other `.nix` files. A `git worktree`-based
   before/after `config.home.packages` diff (byte-identical expected) is
   the standard way to confirm a rename introduced zero behavior change.

5. **This file (`architecture.md`) itself** - it's a "living document,
   refined as design decisions solidify" (see the header), not a fixed
   historical record like `decisions.md`. When an earlier section's
   *plan* turns out to differ from what was actually *implemented* (e.g.
   section 1's original `modules/local/template.nix` sketch vs. the real
   `templates/local/` + `dots-local-options` implementation), update
   the section in place with a note explaining what superseded it, rather
   than letting the stale sketch stand uncorrected as if it were still
   the plan.

6. **Change PATH-affecting logic in either branch of `modules/core/
   nixon.nix`'s NIXON gatekeeper** → verify BOTH the `NIXON=1` and
   `NIXON=0` branches still leave the raw system Nix installation
   (`/nix/var/nix/profiles/default/bin` - the actual `nix`/`nix-daemon`
   binaries, NOT part of the Home Manager profile at `~/.nix-profile`)
   reachable on PATH independently of each other, since a shell can
   start directly in either mode without inheriting anything from a
   prior sibling shell. Also verify against a *non-login* interactive
   shell specifically (e.g. a fresh terminal opened inside an already-
   running graphical session) - `.profile`/`.profile-dots`/`.profile-
   nix`'s chain (which eventually reaches `nix.sh`) only runs for
   *login* shells, so anything that silently depends on that chain
   having already run will work in a terminal opened via `nixon`/
   `nixoff` (both explicitly `exec bash -l`) but silently fail in the
   much more common "just open a new terminal" case. See `decisions.md`'s
   2026-07-19 "`NIXON=1` mode never guaranteed the raw `nix` binary was
   on PATH" entry for the concrete bug this caused (`nh` failing
   `apply-dots` with "No output from nix --version command").

7. **Add, rename, or remove any `dots-*` command** (`dots-tools`,
   `dots-sync`, `dots-ports`, etc. - all currently defined in
   `modules/core/scripts.nix` via `pkgs.writeShellScriptBin`) → also
   update:
   - The `dots.tools` registry entry for it at the bottom of
     `modules/core/scripts.nix` (add/rename/remove the matching
     `{ name = "..."; synopsis = "..."; feature = "..."; }` block) - this
     is what `dots-tools`/`.#dotsToolsDoc` reads from, so a script left
     unregistered here is invisible to `dots-tools` even though it's
     installed and runnable; a renamed script left registered under its
     old name is worse (actively misleading). `modules/core/
     tools-registry.nix` also asserts every registered name is unique,
     so a forgotten rename that collides with another entry fails the
     build immediately - but a forgotten *removal* (stale name outliving
     a deleted script) or forgotten *addition* (new script, no entry)
     both build fine and just silently drift.
   - Any other feature/suite's own `dots.tools` entries, if the rename
     affects a *dots-local field name* referenced via that entry's
     `dotsLocalSettings` list (grep for the old field name repo-wide, per
     rule 4 above, if this applies).
   - This is a distinct, narrower rule than rule 4 (module file renames)
     - it's specifically about the *registry entry* staying in lockstep
       with the *script itself*, not about grepping the whole repo for a
       path. New `dots-*` scripts should also each get a runtime
       smoke-test (build the derivation, run the real binary directly,
       not just `nix build` succeeding) before being considered done -
       confirmed via `dots-ports`'s introduction (2026-07-27), which was
       tested by resolving its `.drv`'s real output path and invoking the
       built script against this machine's actual listening sockets.

8. **Add a new MCP server behind the shared `mcp-proxy` gateway**
   (`modules/suites/ai-apps.nix`'s `mcpProxyServersConfig`) → also touch,
   in the same change:
   - The `mcpServers.<name>` entry in `mcpProxyServersConfig` itself
       (command/args/env for the stdio backend).
   - `home.file ".config/opencode/opencode.json"`'s `mcp` block (add the
       matching `type = "remote"; url = mcpServicesUrl "<name>";` entry) -
       opencode is the "always on when enabled" consumer, so a server added
       only to the proxy config but not here is invisible to opencode.
   - `setup-agency-mcp`'s `[ "taskwarrior" "memory" ]` name list (both
       `do_install`'s registration loop and `do_remove`'s removal loop) -
       Agency/Copilot registration is manual/opt-in, but the script should
       still know about every server the proxy hosts.
   - Never bind the proxy itself to anything but `127.0.0.1` (see
       `decisions.md`'s 2026-08-01 "Shared Taskwarrior + Memory MCP
       servers" entry for why `supergateway` was rejected over exactly
       this) - any new backend added here inherits the shared proxy's bind
       address, so this isn't a per-server decision, just a reminder not to
       add a *second*, separately-bound gateway for convenience later.

9. **Add a new platform-aware `features.*` module that `modules/rules.nix`
   needs to set (e.g. enabling it on an `isWsl`/compositor-based rule,
   alongside `opener`/`clipboard`/`notify`)** → also add its `.nix` file
   to `modules/composition.nix`'s *universal* top-level `imports` list
   (NOT just a context file like `priv.nix`/`work.nix`), even if a
   context file also imports/configures it. A NixOS/HM module option
   must be *declared* (its module imported somewhere in the active
   config) before any other module can set a value under that path -
   even inside a conditionally-false `lib.mkIf` - so if `rules.nix` sets
   `features.<name>.enable` but only `priv.nix` imports the module,
   evaluating in `work` context (which doesn't import
   `opener`/`clipboard`/`notify`) throws "option does not exist" (or a
   confusing update-operator/type error, per `decisions.md`'s 2026-08-01
   `features.notify` entry) as soon as `rules.nix`'s always-active rule
   tries to set it. `composition.nix`'s own imports-list comment names
   every feature this applies to - keep both the code and the comment in
   sync when adding another one.
