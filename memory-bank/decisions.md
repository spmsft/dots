# Decision Log

Append-only. Newest entries at the bottom. Each entry: date, decision,
rationale, and (if relevant) who/what prompted it.

**Standard validation approach used throughout** (not repeated in full
per entry - only entry-specific facts are called out below): `nix eval`
for fast iteration, a full `nix build .../activationPackage` before
considering anything done, before/after `config.home.packages`/
`config.alienPackages.enabledPackages` diffs (`git stash`/`pop` or
`git worktree` for multi-commit spans) to confirm behavior-preservation,
and synthetic `dots-local` copies under `/tmp` for testing axis
combinations without touching the real system.

---

### 2026-07-18 — Memory bank location and format
**Decision:** `dots/memory-bank/` (git-tracked), plain markdown files,
project-specific structure (not the generic Cline-style productContext/
activeContext template) since this is a single large refactor effort with a
clear phase structure, not an evolving general product.
**Rationale:** Needs to survive across machines/clones/sessions like
AGENTS.md does; a phase-tracker shape is more useful here than generic
memory-bank templates.

### 2026-07-18 — Bundle bugfixes into the re-architecture
**Decision:** Yes — fix concrete bugs found during inventory as part of the
relevant phase rather than tracking them separately.
**Rationale:** We're touching most files anyway during the refactor; cheaper
to fix in place than context-switch later.

### 2026-07-18 — Refactor depth: deep
**Decision:** Unify duplicated subsystems (tuning defaults, alien-package
discovery, suite boilerplate) rather than just reorganizing directories.
**Rationale:** User explicitly asked for deep consolidation once we talked
through the specific duplications found.

### 2026-07-18 — mkAppSet-style helper for suite boilerplate
**Decision:** Introduce a shared helper (`modules/core/lib.nix`) replacing
the hand-repeated enable-flag/package/alien-entry triples (26x in gui-apps
alone).
**Rationale:** Highest-leverage single reduction in duplication across every
suite file.

### 2026-07-18 — Dead options: wire up, don't remove
**Decision:** viewer.nix's 5 unused options and fonts.required get actually
wired to behavior, rather than deleted.
**Rationale:** They represent intended-but-unfinished functionality worth
completing rather than surface-area to cut.

### 2026-07-18 — Librewolf: keep native alien package, delete dead HM block
**Decision:** `programs.librewolf.enable = false` stays effectively "off";
delete the ~25 lines of unreachable extension/hardening config in
gui-apps.nix. Keep installing librewolf-bin via the alien/pacman path.
**Rationale:** User's explicit choice — simplicity over switching to a
Nix-managed librewolf.

### 2026-07-18 — Branch/checkout strategy is out of scope
**Decision:** This project does NOT design git branch topology. "Every
machine has its own checkout" — that's the user's process to manage. Our
job is narrower: make `dots` contain zero embedded local/host state so it's
branch/merge-friendly *regardless* of whatever topology is chosen.
**Rationale:** Direct user correction — I had over-specified a
personal/work branch scheme that wasn't asked for.

### 2026-07-18 — `location` axis meaning
**Decision:** `dotsLocal.location` is a freeform/loosely-typed tag for
physical location and/or network "situation" (home/parents/travel/office/
...), not a strict enum yet. Concrete consuming behavior (VPN, proxy, DNS,
etc.) is added feature-by-feature later, not designed upfront.
**Rationale:** User's own clarification; keep it flexible since concrete use
cases aren't fully known yet.

### 2026-07-18 — `dots-local` schema formality
**Decision:** Yes — formalize as a typed `lib.evalModules` schema, defined
in `dots`, evaluated once in `flake.nix`. Escape valves (`extraModules`,
`extraOverlays`, `tags`) included alongside typed axes so unmodeled needs
aren't blocked.
**Rationale:** User agreed; matches the multi-axis ask and removes the
30+ scattered ad-hoc `or`-fallback reads.

### 2026-07-18 — Rollout validation depth
**Decision:** `nix eval`/`nix build` per milestone; live `apply-dots` switch
only at explicitly flagged checkpoints (not every single commit).
**Rationale:** chromaden is the daily driver; balance fast iteration against
not breaking the primary machine on every small step. Shell-bootstrap
changes (Phase 6) and script-consolidation (Phase 7) are flagged as
mandatory live-checkpoint phases regardless, since they're hard to verify
via eval alone.

### 2026-07-18 — Shell bootstrap: KEEP gutter-eval, rename outputs only
**Decision:** Reversed my initial proposal to eliminate the double-HM-eval
"gutter eval" mechanism. It stays as-is. Only change: `nixon.nix` writes to
`.bashrc-nix`/`.profile-nix` instead of force-overwriting the real
`.bashrc`/`.profile`; a small stable loader stub becomes the real
`~/.bashrc`/`~/.profile`.
**Rationale:** Direct user correction: "There were good reasons why we ended
up with that so I'm reluctant to just drop it." Noted and respected —
do not re-litigate this without new information.

### 2026-07-18 — Composition = explicit declarative dependency rules
**Decision:** `modules/rules.nix` as a small, explicit,
greppable list of `{ when = predicate; set = {...}; }` rules over
`dotsLocal` axes, folded via `mkIf`/`mkDefault` in `modules/composition.nix`.
**Rationale:** User's explicit ask: "I can write simple dependency rules
somewhere in dots, like if AI hardware enabled, pull in AI packages."

### 2026-07-18 — Consolidate OS/platform detection
**Decision:** Introduce one shared platform-detection value/module
(`modules/core/platform.nix`) consumed by clipboard.nix and opener.nix
instead of each independently declaring an identical `backend` enum +
command table. Must support Linux (Wayland/X11) + WSL2 + macOS.
**Rationale:** User flagged the existing duplication directly; these are
"essentials" that need solid cross-platform support.

### 2026-07-18 — Core tool list: review non-aggressively
**Decision:** Do not aggressively trim `modules/core/default.nix`. Only flag
genuinely mislabeled/accidental inclusions (`psutils` = PostScript utils,
not process utils; `t3` = tee-replacement, not tree-like, comment is wrong)
for user confirmation before any removal. Multi-tool overlaps that look
redundant at a glance (three pagers, three HTTP fetchers) are left alone
unless the user says otherwise.
**Rationale:** User explicitly uses many of the "modern CLI / rust rewrite"
tools and asked for a light touch, not an aggressive cut.

### 2026-07-18 — `dots-local` gets a first-class `shell` axis
**Decision:** Add `dotsLocal.shell.{sessionVariables,shellAliases,initExtra}`
as typed schema fields (Phase 1), merged into `programs.bash.*` by a small
core module. This is in addition to, not a replacement for, the general
`extraModules`/`extraOverlays` escape hatch.
**Rationale:** User: "make adding shell vars and other shell init stuff easy
in dots-local" — a full extra Nix module is too much ceremony for "I just
want one env var"; needs a dedicated low-friction path.

### 2026-07-18 — Document every config that loses its home in `dots`
**Decision:** Whenever Phase 1/2 removes config from `dots` in favor of
`dotsLocal` fields (host files, hardcoded per-machine values, etc.), a
documentation/template update showing how to reproduce it in
`dots-local/flake.nix` must land in the *same* change — never delete first
and document later (or not at all).
**Rationale:** Direct user instruction: "some of the existing config will
no longer have a home, solve this by putting files in the checkout
documenting how to setup the respective dots-local/flake.nix." This is the
concrete mechanism satisfying the earlier "store the current template in
dots for easy setup/adoption" goal from the original brief.

### 2026-07-18 — Explicit directive: preserve all overlays/package sources
**Decision:** Treat the current overlay list and flake-input set
(`nur`, `niri`, `noctalia`/`noctalia-qs`, `externalOverlay`,
`nixpkgs-quarto-pin`, `tuneOverlay`, etc.) as must-preserve-exactly during
the schema/composition rework, verified by spot-checking resolved packages
before/after each relevant phase, not just "it builds".
**Rationale:** Direct user instruction: "take great care to preserve
overlays additional package sources and the like." Flagged because
`flake.nix` is exactly the file Phase 1 (schema) and Phase 2 (composition)
need to restructure, making this an easy thing to regress silently.

### 2026-07-18 — Shell bootstrap: corrected understanding, new suffix `-dots`
**Decision:** After investigating the live system, `.bashrc-nix`/
`.profile-nix` already exist and are already the correct pure-HM-output
files (no change needed there). The part that still needs fixing is the
*separate* NIXON-gatekeeper hybrid script, which today `lib.mkForce`s the
real `~/.bashrc`/`~/.profile` directly. That hybrid content moves to
`.bashrc-dots`/`.profile-dots` (new suffix, avoiding collision with the
already-in-use `-nix` suffix), and the real dotfiles are no longer
`home.file`-managed at all — an idempotent, additive-only hook (activation
or setup.sh step) ensures they source `.bashrc-dots`/`.profile-dots`,
without ever overwriting existing user content.
**Rationale:** Direct user correction: "I already have bashrc-nix so you may
have to pick yet another suffix (-dots or so)." Investigating first avoided
a filename collision that would have broken the live system.

### 2026-07-18 — `noctalia-qs` input override: intentional, do not touch
**Decision:** The `nix eval` warning "input 'noctalia' has an override for a
non-existent input 'noctalia-qs'" (from `flake.nix`'s
`inputs.noctalia-qs.follows`) is expected and must be left as-is.
**Rationale:** Direct user statement: "The noctalia-qs override I saw nix
complaining about is setup in dots flake.nix we need it." Not a bug to fix.

### 2026-07-18 — Standing procedure: `git add` new files immediately
**Decision:** Any brand-new file created during this project must be
`git add`ed immediately, before treating any `nix eval`/`nix build` against
it as a real validation.
**Rationale:** Discovered the hard way - local Nix flake evaluation only
sees git-tracked/staged files; a new untracked file is silently invisible
(no error), which briefly made the `gcc15`/`llama-cpp` alien-spec fix
inactive despite every eval/build "passing." See learnings.md for the full
trail. This will recur in every later phase that adds files (schema.nix,
composition.nix, externalized scripts, etc.) so it's recorded here as a
standing rule, not just a one-off note.

### 2026-07-18 — Alien-package orphan detection: cross-manager union required
**Decision:** Orphan detection in `update-alien-packages` must check a
package's required-status against the union of ALL managers' required
lists, not just the same manager's list, plus a defense-in-depth check
directly in the removal prompt loop. Implemented via `get_all_required()`
in `modules/core/alien-packages.nix`.
**Rationale:** Real bug, found via a live user report (`ghostty` wrongly
flagged for removal) - a package whose spec moves from one manager to
another (e.g. an AUR package later added to an official repo) was
permanently stuck flagged as an orphan under the old manager forever, even
though still required and installed. This is exactly the kind of
false-positive that could cause real damage on a daily-driver machine if
acted on without investigation - worth the extra robustness given the
consequence of getting it wrong (accidentally uninstalling a needed,
working package).

### 2026-07-18 — Lightweight `alienPackages.protectedPackages` allowlist
**Decision:** Add a simple `listOf str` option, unioned into the orphan
detector's `get_all_required()` check, for native packages dots doesn't
manage but that other native packages depend on (first use: `fzf` on
chromaden, required by `downgrade`/`fontpreview`). Kept intentionally
minimal - no per-manager scoping, no reason/comment field, just a flat list
consumed the same way `enabledPackages` is.
**Rationale:** User explicitly asked to keep it lightweight. A full
solution (e.g. auto-detecting reverse-deps via `pacman -Qi`) would be more
robust but is unnecessary complexity for what's currently a one-package
need; revisit if this comes up often enough to justify automation.

### 2026-07-18 — `dots-local` schema: additive/backward-compatible, not fully nested
**Decision:** Implemented `modules/local/schema.nix` with existing
fields kept flat (host, distro, march, barch, realname, realmail,
username, uid, gid, homeDirectory, profile, enableGuiDefaults,
graphicalBackend, butterfishEndpoint/ApiKey/Model, appimagesDir, appimages,
tune.flags, sync.tracked, nixonDefault) - exactly matching the live
`dots-local/flake.nix`'s current shape - rather than the fully-nested
`identity.*`/`machine.*`/`system.*` design originally sketched in
architecture.md. New axis fields (gpu, isWsl, location, tags, shell.*,
extraModules, extraOverlays) are added inertly alongside the existing flat
ones.
**Rationale:** The nested redesign would have required rewriting the live
`dots-local/flake.nix` as part of Phase 1 just to satisfy an aesthetic
preference, adding risk to the daily-driver machine for no functional
gain. Additive-only keeps Phase 1 low-risk (verified: zero changes needed
to the real `dots-local/flake.nix` to satisfy the new schema) while still
delivering the real goals (typed options, defaults, self-documentation,
new escape-hatch fields). The nested design can still happen later if a
concrete need arises (e.g. Phase 2's composition rules could introduce
`machine.*`/`system.*` groupings at that point if warranted) - not
foreclosed, just not done preemptively.

### 2026-07-18 — Dropped the `graphical` legacy alias
**Decision:** `enableGuiDefaults` is now the sole canonical field (schema
default `false`); the `local.enableGuiDefaults or local.graphical` fallback
chain in `chromaden.nix`/`priv/home.nix` is removed.
**Rationale:** `graphical` was an undocumented, already-dead legacy key
(the live `dots-local/flake.nix` only ever set `enableGuiDefaults`) -
carrying it forward would just be dead code the schema can't even validate
meaningfully.

### 2026-07-18 — Removed manual `graphicalBackend` validation
**Decision:** Deleted the hand-rolled `validBackend`/`assertions` block in
`profiles/priv/home.nix` that checked `graphicalBackend` against 4 valid
strings.
**Rationale:** The schema now types `graphicalBackend` as
`enum ["wayland" "x11" "wsl" "macos"]`, so an invalid value is rejected at
flake-evaluation time with a clear built-in error - the manual check became
redundant (and its own error message was less clear than the module
system's built-in one).

### 2026-07-18 — Unified `march` default to "native" (was inconsistently "znver5")
**Decision:** `dotsLocal.march` defaults to `"native"` in the schema.
`package-tuning.nix` (flake-level) previously defaulted this to `"znver5"`
specifically for its own reads, inconsistent with `tune-support.nix`
(home-level)'s `"native"` default for the exact same field - both now read
`dotsLocal.march` directly with no competing default.
**Rationale:** `"znver5"` is a specific AMD Zen 5 string that would fail to
build on any other CPU - a poor default for a machine that doesn't
explicitly set `march`. `"native"` is safe/portable. Chromaden is
unaffected (explicitly sets `march = "znver5"` in its real dots-local).
Also fixed a related bug while here: the `-opt` profile build in
`flake.nix` previously hardcoded `gcc.arch = "znver5"; gcc.tune = "znver5";`
directly, completely ignoring `dotsLocal.march` - meaning every machine's
`-opt` build was silently building for znver5 regardless of its actual
CPU. Now reads `dotsLocal.march` instead.

### 2026-07-18 — `dots-local`'s flake-metadata attrs must be stripped before `evalModules`
**Decision:** `flake.nix` explicitly `removeAttrs`s a known list of
flake-introspection keys (`_type`, `inputs`, `lastModified`,
`lastModifiedDate`, `narHash`, `outPath`, `outputs`, `rev`, `revCount`,
`shortRev`, `sourceInfo`, `submodules`, `dirtyRev`, `dirtyShortRev`) from
the raw `dots-local` flake-input value before handing it to
`lib.evalModules`.
**Rationale:** Accessing a flake input directly (`inputs.dots-local`)
returns the flake's output attrset *plus* a set of hidden
introspection/metadata attributes Nix attaches for its own bookkeeping.
Passed bare into `evalModules`, these get validated as if they were
declared config options and fail ("The option `_type'/`dirtyRev' does not
exist"). The `dirtyRev`/`dirtyShortRev` variants only appear when
`dots-local` itself has uncommitted changes - both clean and dirty states
needed to be handled since editing `dots-local` without committing is a
completely normal, expected workflow (confirmed in AGENTS.md: "During
apply-dots, it's overridden with git+file://$DOTS_LOCAL_DIR... allows
uncommitted changes in dots-local to be picked up").

### 2026-07-18 — Azure Linux 4 alien specs: new `dnf5` manager, same conservatism as v3
**Decision:** Added `azurelinux4` as a distinct `distro` value using a new
`dnf5` package-manager backend (not reusing `tdnf`, even though Azure Linux
4 ships `tdnf`->`dnf5` compatibility symlinks) - Microsoft's own docs
recommend migrating scripts to `dnf5`/`dnf` rather than relying on the
legacy shim. Specs mirror `azurelinux3`'s exact existing package set
(marksman, nmap, gh, azure-cli, graphviz) at the same confidence level -
deliberately NOT extended further the way Debian's specs were, since Azure
Linux 4 is explicitly described (by Microsoft's own "what's new" docs and
third-party reviews) as a lean, cloud/container-focused distro with a
curated (not general-purpose) package set - lower confidence that generic
CLI utilities are actually packaged for it compared to Debian's
general-purpose archive.
**Rationale:** User asked to "handle azure linux (latest, v4)... try to
cover alien alternatives as for debian" - interpreted as "extend Azure
Linux support the way Debian was extended" in spirit (adding a new
distro/manager combo, structurally ready), but the actual package list
scope intentionally mirrors the existing, already-conservative azurelinux3
set rather than Debian's broader list, given the genuinely different
confidence level between a general-purpose distro (Debian) and an
intentionally minimal cloud distro (Azure Linux).

### 2026-07-18 — Debian alien specs: conservative, official-repos-only
**Decision:** Only added Debian specs for packages confirmed (or high
confidence) to be in Debian's *official* archive - `nmap`/`rclone`
(network) and `btop`/`lazygit`/`imagemagick`/`graphviz`/`pandoc`/`pass`/
`hledger` (tui-apps). Explicitly excluded `doggo`/`xh` (network) and
`zellij`/`yazi` (tui-apps) - web search confirmed the latter two are only
reliably available through unofficial third-party apt repos
(deb.griffo.io), not Debian's own archive.
**Rationale:** Matches the existing, deliberately conservative
`azurelinux3` precedent - dots's alien-package convention assumes official
distro repos, not third-party ones (that would be a much bigger
architectural decision - introducing external repo configuration - not
something to slip in as a side effect of adding Debian support). Better to
under-declare and let a package silently fall through to plain Nix than to
declare a spec for something apt can't actually install.

### 2026-07-18 — Phase 2 scope: `modules/distros/*` deferred to Phase 3
**Decision:** Did not repurpose the vestigial `modules/distros/*.nix`
registry during Phase 2 as originally planned - left as-is (still dead
code), rescoped to Phase 3 instead.
**Rationale:** It naturally belongs with the alien-package unification
work (Phase 3 already touches per-distro spec discovery); doing it in
Phase 2 would be duplicated effort split across two phases for no benefit.

### 2026-07-18 — WSL shell-integration workaround generalized, not left host-specific
**Decision:** Triomino's VSCode-Remote-SSH + WSL shell-integration
workaround (starship PROMPT_COMMAND cleanup, VS Code shellIntegration
sourcing, zoxide/direnv manual re-init) became a real, reusable
`modules/features/wsl-shell-integration.nix`, auto-enabled by the `isWsl`
composition rule - not left as triomino-specific `extraModules` content.
**Rationale:** This fix has nothing to do with the specific machine named
"triomino" - any WSL host connected to via VS Code Remote-SSH needs the
exact same fix. Keeping it host-specific would have meant re-discovering
and re-solving the same problem on any future WSL machine.

### 2026-07-18 — Flake output renaming: CONFIRMED -> `default`/`default-opt`
**Decision:** User explicitly confirmed at the Phase 2 checkpoint:
`homeConfigurations.{priv,work,priv-opt,work-opt}` -> `default`/
`default-opt`. `apply-dots priv`/`apply-dots priv-opt` becomes
`apply-dots`/`apply-dots default-opt` (or similar - see Phase 2 work for
exact final command shape). This is an intentional, confirmed breaking
change to the command surface.
**Rationale:** Reflects that composition is now fully axis-driven from
`dotsLocal` - there's no longer a real "profile choice" to make via the
command line, so a generic `default` name is more honest than keeping
`priv`/`work` around as vestigial selectors.

### 2026-07-19 — `features.fonts.enable`: leave off for now
**Decision:** User confirmed (Phase 9 checkpoint): leave
`features.fonts.enable` at its long-standing default of `false` for now;
revisit later. Fonts continue to be an alien/pacman-managed concern on
chromaden, not a Nix/Home-Manager-managed one.
**Rationale:** User's explicit call. `features.fonts.required` (now
actually wired - `niri-noctalia.nix` contributes `pkgs.inter`) stays
structurally correct but inert until/unless this is revisited -
`cfg.base ++ cfg.required` never gets added to
`home.packages` while `enable` is `false`. No further action needed
unless the user brings this back up.

### 2026-07-19 — Post-Phase-9 module renames
**Decision:** `modules/composition-rules.nix` -> `modules/rules.nix`,
`modules/dots-local/` -> `modules/local/` (both requested directly by the
user). The separate, private `~/dots-local` repo/flake input is
unaffected - only the schema directory inside *this* repo moved.
**Rationale:** User's explicit call, purely mechanical/naming - no
behavior change. Verified via `nix eval`/`nix build` (zero rebuilds
needed, confirming a pure rename) plus a spot-check of the `.#dotsLocal`
and `default-opt` flake outputs.

### 2026-07-19 — `modules/distros/*` deleted (not repurposed)
**Decision:** Deleted `modules/distros/{cachyos,opensuse,azurelinux3,default}.nix`
entirely, per the user's choice after an assessment (requested by the
user) confirmed it was fully dead code.
**Rationale:** Zero references anywhere in the codebase (confirmed via
grep); the `packageManagers = [...]` "order of preference" concept it
encoded is not how the real alien-package system works (each package's
alien spec directly declares which specific managers it's available on -
see `*.<distro>-packages.nix` files). It was also stale relative to that
real system: missing `azurelinux4` (dnf5) and `debian` (apt), both added
in Phase 3, never backfilled here. This closes out the "repurpose
modules/distros/*" item deferred since Phase 2 (see the 2026-07-18
"Phase 2 scope" decision above) - resolved by deletion rather than the
originally-sketched repurposing, since nothing ever ended up needing it.

### 2026-07-19 — Reclassify `features.git`/`features.dev-tools` as suites, split `features.network`
**Decision:** User asked to assess whether the features/suites separation
still made sense. Found the documented rule (AGENTS.md: "features = 
individual capabilities", "suites = bundled application groups, multiple
related packages at once") was not being followed consistently:
- `features.git` (7 independent tools: git, jj, delta, lazygit, gh,
  gh-dash, gitCredentialManager) and `features.dev-tools` (18 independent
  language toolchains/tools) were both structurally identical in shape to
  a suite - every option maps 1:1 to a separate package, not a config
  knob for one cohesive capability. `dev-tools` was in fact bigger than
  most actual suites.
- `features.network` was a genuine hybrid: `nmap`/`rclone`/`doggo`/`xh`
  are independent tools (suite-shaped); `sshAgent`/`gpgAgent`/`gpgSsh`
  are real behavioral config (feature-shaped).
- Confirmed via grep that nothing in the codebase ever treats
  `features.*`/`suites.*` as bulk categories - every reference is to one
  specific named module, so the split has zero programmatic
  significance; purely a human-organization convention.

User chose the most thorough option: move `git.nix` -> `suites/git-
tools.nix` (`suites.git-tools`), `dev-tools.nix` -> `suites/dev-tools.nix`
(`suites.dev-tools`, plus its 3 alien-package spec files), and split
`network.nix` into `features.network` (kept: `enable`/`sshAgent`/
`gpgAgent`/`gpgSsh`/`programs.ssh`/the SSH-include-files activation hook)
+ new `suites.network-tools` (`nmap`/`rclone`/`doggo`/`xh`, its own
`enable`, matching every sibling suite's pattern) - including moving and
renaming its 4 alien-package spec files
(`network.*-packages.nix` -> `network-tools.*-packages.nix`, updating
each file's `feature = "network"` field to `"network-tools"`).

Also tightened AGENTS.md's Module Types section itself to state the
distinguishing rule precisely (options are config knobs for one thing
vs. options that each map to a distinct package), matching what the
assessment actually found in practice, and updated its own `features.git`
example (ironically the doc's own suite-shaped example) to
`suites.git-tools`.

**Rationale:** Purely organizational, no functional impact (confirmed via
a before/after `config.home.packages`/`config.alienPackages.enabledPackages`
diff - byte-identical - plus every renamed option's resolved value
spot-checked to match its pre-move value exactly). Improves discoverability
and keeps the documented convention actually true going forward.

### 2026-07-19 — `setup.sh` must track `schema.nix`; standing rule added
**Decision:** User asked to revise `setup.sh`/`sync.sh` for the current
architecture, and to specifically anchor an ongoing "keep setup.sh
current" rule in the memory bank/AGENTS.md, since `setup.sh`'s generated
`dots-local/flake.nix` template had silently fallen behind
`modules/local/schema.nix` - it predated Phase 2 entirely and never
gained `gpu`/`compositor`/`isWsl`/`machine.*`/`extraModules` fields, nor
an up-to-date `distro` comment (missing azurelinux4/debian).

Fixed `setup.sh`'s template to include all of these as commented-out,
documented optional fields (matching README.md's "Adding a New Host"
example), updated its "Next steps" messaging to mention them, and fixed
the stale `distro` comment.

**Bigger finding while testing the fix**: doing a real fresh-setup
regression test (running the identity-generation half of `setup.sh` in a
sandboxed `$HOME`, then `nix eval` against the result) surfaced a genuine,
previously-undetected bug: with `machine` left fully commented-out (the
literal default state for any brand-new user who hasn't customized
anything yet), evaluation fails outright with `Cannot set
'programs.ssh.extraConfig' if 'programs.ssh.settings."*"' (default host
config) is not declared` - because `features/network.nix` used `settings."*"
= lib.mkIf (dotsLocal.machine.sshIdentityFile != null) { ... };`, which
omits the `settings."*"` key entirely (not just leaves it empty) when
`sshIdentityFile` is null, and Home Manager's own `programs.ssh` module
asserts that key must be declared whenever `enableDefaultConfig = false`
+ `extraConfig` is set. This was never caught by any earlier phase's
validation because chromaden's real `dots-local` already sets
`machine.sshIdentityFile`, masking it completely - only a genuinely fresh,
un-customized config exposes it. Fixed by always declaring `settings."*"`
(as `{}` when there's no identity file to set, populated when there is)
instead of conditionally omitting the key itself. Logged in
`learnings.md` with the general lesson (conditionally-omitted
module-system keys vs. conditionally-empty values are not
interchangeable when something else asserts the key's mere presence).

Also implemented `sync.sh`'s `-g`/`--force-regen` flag, which was
documented in 6 places (`sync.sh`'s own `--help`, README.md, SYNC.md) but
never actually implemented in `sync.sh`'s argument parsing - `dots-sync
-g` would have hit `"Unknown: -g"` and exited 1. Also removed a
now-always-false `${profile%-opt}` suffix-strip in `sync.sh`'s
global-ignores loader - `dotsLocal.profile` has never had a "-opt" suffix
(that distinction lives only at the flake-output level, a separate axis),
so this was dead defensive code left over from before Phase 2's
flake-output rename.

**Standing rule (added to AGENTS.md's "Common Tasks" section)**: any
future change to `modules/local/schema.nix` (add/rename/remove a
`dotsLocal` field) must also update `setup.sh`'s generated template in
the same change, and a fresh-setup regression test (sandboxed `$HOME`,
run setup.sh's identity-generation step, `nix eval` the result) should be
run before considering such a change done - this is the only way to catch
"works for existing configured machines, breaks for brand-new ones" bugs
like the one just found, since chromaden's own validation can't surface
them.

**Rationale:** `setup.sh` is the sole onboarding path for a genuinely new
machine; letting its template silently drift from the schema (as
happened across all of Phase 2-9) means every new-machine bootstrap
either misses newer axis fields entirely or, worse, hard-fails on `nix
eval` before the user even gets to `apply-dots`.

### 2026-07-19 — CLI-only defaults, core minimization, editor/pager cleanup
**Decision:** User requested a CLI-only-by-default `priv` context (no GUI
tools leaking in without an actual UI present), a core package
minimization pass, dropping the `fresh` editor in favor of `helix`, and a
pager-story cleanup. All implemented as follows:

- **CLI-only default**: `contexts/priv.nix` no longer unconditionally
  enables `features.opener`/`features.clipboard` (previously
  `enable = true; backend = graphicalBackend;` regardless of whether any
  UI existed) or `suites.sixel-tools`. Moved opener/clipboard's
  enable+backend logic into `modules/rules.nix` as two mutually-exclusive
  rules: `isWsl` -> `backend = "wsl"`, `!isWsl && compositor != null` ->
  `backend = graphicalBackend`. A host with neither (no compositor, not
  WSL) now gets both disabled by default, matching every other suite's
  off-by-default convention. `suites.sixel-tools`'s `enable = true` block
  moved out of `priv.nix` entirely into chromaden's real
  `~/dots-local/host-chromaden.nix` (chromaden still gets it; a fresh
  clone of `dots` no longer does).
- **Core minimization**: removed `psutils`/`t3` (mislabeled, per
  `learnings.md`'s 2026-07-18 entry) and `ov` (installed, never wired to
  anything) from `modules/core/default.nix`. Also removed 5 confirmed
  duplicate `home.packages` entries (`direnv`, `lsd`, `zoxide`, `fzf`,
  `bat`) - each was already being added a second time via its own
  `programs.X.enable = true` in the same file (confirmed via `nix eval`
  diff showing each package name twice in `config.home.packages` before
  this fix, once after). `nix-direnv` was NOT removed - unlike `direnv`
  itself, it's not auto-added by `programs.direnv.nix-direnv.enable`, so
  the explicit package entry is actually needed.
- **Moved out of core, made opt-in**: `prettier` -> `suites.dev-tools.prettier`,
  `curlie` -> `suites.network-tools.curlie` (grouped with `xh`/`doggo`,
  the other HTTP-ish CLI tools, rather than `dev-tools`), `tailspin` ->
  `suites.tui-apps.tailspin`. All three kept enabled in `contexts/priv.nix`
  (not host-specific concerns, just reclassified from "forced core" to
  "suite toggle", same treatment as `git.nix`/`dev-tools.nix`'s Post-
  Phase-9 reclassification) so no actual behavior changes for anyone
  already using the `priv` context.
- **`fresh` editor removed** in favor of `helix`: confirmed via the
  `EDITOR`/`VISUAL` fallback loop in `nixon.nix` that `hx` is checked
  before `fresh` and always wins since `helix` is installed
  unconditionally - removing `fresh` is a genuine no-op for editor
  selection. Removed the `suites.tui-apps.fresh` option/app-set entry,
  its CachyOS alien spec, the `fresh` word from the `EDITOR` loop, and
  the now-pointless `fr` alias block (had no other purpose).
- **Pager cleanup**: removed `moor` (one of three "general pager"
  candidates) - `nixon.nix`'s `$PAGER`/`$LESS` logic simplified to just
  `less` unconditionally (no more `command -v moor` branching), and the
  `$BAT_PAGER` env var (previously moor-only, no fallback) removed
  entirely. `ov` removed too (see core minimization above - it was never
  wired to anything regardless of pager choice). `difftastic` **kept**
  (per user - it was "installed but never wired to anything" before) and
  now actually wired up: `programs.git.settings.alias.difft = "-c
  diff.external=difft diff"` in `suites/git-tools.nix` - scoped to a
  `git difft` alias rather than setting `diff.external` globally, so it
  doesn't fight with `delta`'s existing `core.pager` integration (delta
  expects normal unified-diff input; difftastic's structural diff output
  would break that pipeline if it became the global default). Also added
  `batwatch` to `programs.bat.extraPackages` (was aliased in `nixon.nix`
  but missing from the package list - the alias may have silently done
  nothing before this fix).

**Rationale:** User's explicit design calls after a full research pass
(see `preserved-features-checklist.md`-style investigation delegated to
research agents) confirming exactly which packages/rules needed to
change and why. All changes verified via before/after
`config.home.packages`/`config.alienPackages.enabledPackages` diffs
(byte-identical except the intended moves/removals/additions), full
`nix build .../activationPackage` for chromaden (unchanged resolved
values for every moved option) plus three synthetic hosts (CLI-only,
niri-compositor, WSL) confirming the new opener/clipboard rule fires
correctly in exactly the intended cases.

### 2026-07-19 — `.bashrc-core`/`.profile-core` removed
**Decision:** User asked where `NIXON` actually gets set (confused not
seeing it in the real `.bashrc`/`.profile`) and to remove the
`.bashrc-core`/`.profile-core` indirection layer entirely.
**Findings:** `NIXON` is set in `~/.bashrc-dots`/`~/.profile-dots`
(generated by `modules/core/nixon.nix`, sourced via a one-line hook
appended to the real `~/.bashrc`/`~/.profile` - which is why grepping
those two files directly shows nothing). Its default comes from
`dotsLocal.nixonDefault`, unset in chromaden's real `dots-local` and thus
falling back to the schema default `false` - confirmed via
`systemctl --user show-environment` that chromaden's actual desktop
session genuinely runs with `NIXON=0` (native mode) by default. Not
changed as part of this request (user didn't ask to flip it) - just
clarified where it comes from.
**`.bashrc-core` findings**: `.profile-core` never existed on disk at all
(dead from the start); `.bashrc-core` held exactly 2 lines
(`QT_QPA_PLATFORMTHEME`/`GTK_THEME`), an unmanaged, non-Nix-tracked
dotfile the hybrid shell sourced unconditionally. Removed both sourcing
lines from `nixon.nix`; migrated the 2 env vars into
`dots-local/host-chromaden.nix`'s existing `home.sessionVariables` block
(separate commit in that repo) so they're actually Nix-managed now;
deleted the real `~/.bashrc-core` file from disk.
**Rationale:** User's explicit call - simplifies the shell bootstrap by
removing a layer of indirection that added no value over just editing the
real `~/.bashrc` directly for anything genuinely ad-hoc in the future.

### 2026-07-19 — AppImage catalog moved from dots-local into dots
**Decision:** User asked to move AppImage app *definitions* (file
pattern, command, desktopName, categories) from `dots-local` into `dots`
itself, so `dots-local` only enables/disables (or narrowly overrides
specific fields - NOT a whole-entry replace) rather than redefining
everything per machine.
**Implementation:** Created `profiles/priv/appimages/manifest.nix` (the
*already-existing* "shared manifest" mechanism, previously only used for
Nix-store-imported `src`-based apps) as the catalog for chromaden's
host-local (file-glob) apps too - `mkWrappedApp` already dispatched on
`app ? file` vs `app ? src`, so no new mechanism was needed, just reusing
the existing one. Catalog entries default `enable = false;` (opt-in per
machine). `dots-local/appimages.nix` simplified to just
`{ tuta.enable = true; ... }`-style entries.

**Found and fixed a real bug while implementing the "field-level
override" requirement**: `modules/features/appimages.nix`'s
`allApps = sharedApps // hostLocalApps;` did a whole-entry replace per
app name, not a field-level merge - changed to
`lib.recursiveUpdate sharedApps hostLocalApps`. That alone wasn't
sufficient though: `dotsLocal.appimages` is schema-validated, and a
schema-validated submodule always materializes every declared option
(with its default value) even when the user's dots-local doesn't mention
it - meaning a partial override like `{ tuta.enable = true; }` would
still carry `file = null; command = null; categories = null;` (the
schema's *defaults* for unset fields) into the merge, and
`recursiveUpdate` can't distinguish "explicitly set to this value" from
"never mentioned, defaulted here by the schema" - so those schema
defaults would silently stomp the catalog's real values. Fixed two ways:
(1) every field in the `dotsLocal.appimages` submodule (schema.nix) now
defaults to `null` (including `enable`/`categories`, not just
`file`/`command`), and (2) `modules/features/appimages.nix` strips all
null-valued fields from each dots-local entry before merging, so only
fields the user actually set participate in the `recursiveUpdate`.
**Rationale:** User's explicit design requirement ("not complete
override but only override specified fields"). Verified via a synthetic
host overriding only `tuta.file` - confirmed the built wrapper uses the
overridden file pattern while the desktop entry still shows the
catalog's `desktopName`/`categories`/`command` unchanged. Also verified
via a before/after `config.home.packages` diff (byte-identical) that
chromaden's actual resolved apps (tuta/chatbox/tolaria, all enabled) are
completely unaffected by the refactor.

### 2026-07-19 — Named "syncables" registry, tied to feature assertions
**Decision:** User asked for a similar treatment for the sync system -
too much copy-pasting of the same sync pattern (e.g. Noctalia's config)
between machines. Wanted: named, reusable sync bundles defined in `dots`,
activated by name from `dots-local`; ideally tied to feature flags, with
a missing-required-syncable-for-an-enabled-feature triggering an
activation error; and syncables must be enabled *manually* (never
auto-enabled by a feature) so temporarily disabling a feature never
silently drops sync coverage for config still worth keeping.
**Implementation:**
- New `modules/core/syncables.nix` - a plain data file (no `lib`/flake
  inputs) mapping name -> `{ pattern; type; on_new; ignore; }`, moved
  `noctalia`/`dms`'s definitions here from chromaden's `dots-local`.
- New schema field `dotsLocal.sync.enable` (list of syncable names) -
  `dotsLocal.sync.tracked` stays as-is for genuinely ad-hoc,
  machine-specific patterns not worth registering.
- `sync.sh`'s `ensure_sync_config_current()` now resolves `sync.enable`'s
  names against the registry (via `nix eval --json --file` - a bare data
  read, no flake machinery needed) and merges the result with
  `sync.tracked`'s raw entries via `jq`, before writing the same
  `{tracked: [...]}` shape to `sync-config.json` that the rest of the
  script already consumed unchanged. Unknown syncable names are warned
  about (not fatal - likely a typo) rather than silently dropped without
  a trace.
- `modules/features/niri-noctalia.nix` gained a `config.assertions` entry
  (needed adding `dotsLocal` to its function args, not previously used)
  checking `!cfg.enable || builtins.elem "noctalia" dotsLocal.sync.enable`
  - fires a clear, actionable `nix build`/`apply-dots` error if the
    feature is on but the syncable isn't, without ever auto-enabling the
    syncable itself.
- chromaden's real `dots-local/flake.nix` updated to
  `sync.enable = [ "noctalia" "dms" ];` (was the two full inline
  definitions).
**Rationale:** User's explicit design, including the "manual enable
only" requirement specifically to avoid silently losing sync coverage on
a temporary feature toggle. Verified via: (1) a byte-identical
`sync-config.json` diff before/after (confirming the registry-resolved
output matches the old inline definitions exactly), (2) three synthetic
assertion tests - feature+syncable both on (builds), feature on without
syncable (fails with the intended message), feature off with syncable
still on (builds fine, syncable stays active) - covering exactly the
"don't lose sync coverage when temp-disabling" scenario the user
described.

### 2026-07-19 — Redundant `tune.flags` override removed from chromaden's dots-local
**Decision:** User asked for chromaden's `dots-local` tune flags to
become the actual dots default so it doesn't need setting there.
**Finding:** They already were - a field-by-field `nix eval` comparison
confirmed chromaden's `tune.flags` override (`c`/`rust`/`go`/`haskell`,
all three modes) was byte-for-byte identical to
`modules/core/tune-defaults.nix`'s built-in table (both parametrized by
the same `march`). Removed the entire block from
`dots-local/flake.nix` - a full `nix build` afterward produced **zero**
new derivations (every resolved store path identical), confirming no
behavior change whatsoever.
**Rationale:** Pure redundancy elimination - `tune-defaults.nix` was
already the single source of truth (per Phase 5), chromaden's copy just
happened to restate it verbatim. `dotsLocal.tune.flags` remains available
as a genuine override mechanism for any future machine that needs
something actually different.

### 2026-07-19 — `dots-local-options` command for schema discoverability
**Decision:** User asked for the best way to see every option settable
in `dots-local/flake.nix` - considered options: a hand-maintained parallel
`.md` doc (rejected - exactly the kind of drift this whole session has
repeatedly found and fixed, e.g. `setup.sh`/`AGENTS.md`), a docstring
convention + grep (workable but fragile for a multi-line, nested
structure), or an extraction script reading the schema directly
(chosen).
**Implementation:** New flake output `dotsLocalOptionsDoc` (`flake.nix`)
evaluates `dotsLocalEval.options` through nixpkgs's own
`lib.optionAttrSetToDocList` - the exact same machinery NixOS/Home
Manager use to generate their own option reference docs - filtering out
internal module-system plumbing (`_module.args`/`check`/etc) that isn't
anything a `dots-local` author would ever set. New command
`dots-local-options` (`modules/core/scripts.nix`) evaluates this output
and pretty-prints path/type/default/description per option, with an
optional substring filter (`dots-local-options machine`). Distinguishes
"no default, required" (option truly has no `default`) from "default is
literal null" (option's `default` value happens to be `null`) - the two
look identical unless checked via `o ? default` specifically.
**Rationale:** Guarantees the option reference can never drift from the
real schema, since it's generated live from `modules/local/schema.nix`
itself rather than maintained as a parallel document - directly avoids
repeating the exact failure mode found and fixed multiple times already
this session (AGENTS.md, `setup.sh`, both left undocumented/stale
relative to schema changes across several phases). Documented in
README.md/AGENTS.md pointing here instead of "read schema.nix's
comments" as the primary discovery path.

### 2026-07-19 — `setup.sh`'s embedded heredoc replaced with real template files
**Decision:** User wanted a maintainable `dots-local` template - asked
whether to move generation into a Nix package, or use real template
files copied/filled in by `setup.sh` directly, using chromaden's actual
current `dots-local` as the baseline shape.
**Chosen approach:** Real, standalone template files
(`templates/dots-local/{flake.nix,appimages.nix,gitignore}`) rather than
a Nix-package-based generator. Rationale for not going the Nix-package
route: `setup.sh` runs *before* a working `dots-local` exists at all (the
whole point of the script) - referencing a package built from `dots`'s
own flake to generate the very first `dots-local` file adds a
bootstrapping dependency (needing `nix` to already resolve and build
something) for what's fundamentally "copy a text file and substitute a
few values," which plain template files + `sed` already do with zero
extra moving parts. The templates are genuinely standalone, valid Nix
files (no bash heredoc, no dual bash+Nix escaping) using `@@TOKEN@@`
placeholders - `setup.sh` now just `cp`s them into place and runs one
`sed -i` pass, rather than interpolating bash variables directly into an
inline Nix-string heredoc (which required things like `\${march}`
double-escaping for the tune.flags example previously).
**Content**: `templates/dots-local/flake.nix` mirrors chromaden's actual
current shape/field order (per the user's "use current dots-local as
baseline" instruction) - required identity fields live (system/barch/
march/distro/host/username/uid/gid/homeDirectory/profile) as
placeholders, everything optional (gpu/compositor/isWsl/machine.*/
extraModules/butterfish*/tune.flags/sync) as commented-out examples
matching chromaden's real usage shape, without presuming any specific
hardware. Since `dots-local-options` (added earlier this session) now
generates the full field reference live from the schema, the template
itself doesn't need to be exhaustive - just illustrative of the common
cases.
**Also fixed two pre-existing, unrelated doc bugs found while touching
this area**: SYNC.md's "Initial setup on new machine" workflow told the
reader to `cd ~/dots-local && ./setup.sh` (wrong directory - `setup.sh`
lives in `dots`, and takes a required profile argument it wasn't
shown with); its "File Relationships" tree also listed `setup.sh` as
living inside `dots-local/` when it's actually in `dots/`. Both fixed.
**Rationale:** Directly what the user asked for; the "no Nix package"
choice avoids adding complexity/a bootstrapping dependency to the one
script that has to work with nothing but a bare `nix` install and a
git clone of `dots` - nothing else in the whole system needs to exist
yet when `setup.sh` runs.
**Validated:** fresh-setup regression test - template-generated
`dots-local` builds cleanly end-to-end; chromaden's real `dots-local`
(hand-edited, not regenerated) unaffected, zero new derivations.

---

### 2026-07-19 — Post-Phase-9 wrap-up audit round (batch of small fixes)
**Context**: user asked for a final pass - anything unhandled, not
nicely fitting the re-architecture, lingering clean-up, or further
consolidation opportunities. Ran research audits plus direct
verification; applied the confirmed, low-risk fixes below in one round
(all committed together after full validation).

**Fixes applied:**
- `modules/suites/git-tools.nix` rewritten to use `mkAppSet` (same
  helper already used by tui-apps/gui-apps/etc.) - `lazygit` and `gh`
  are now correctly alien-aware (their alien specs are owned by
  `tui-apps.cachyos-packages.nix`/`cloud-tools.cachyos-packages.nix`
  respectively; git-tools.nix previously added both as unconditional
  Nix packages with zero alien-awareness, duplicating them whenever the
  native package was already installed). `delta` deliberately excluded
  from the appSet - it has no alien spec anywhere, relies solely on
  `programs.delta.enable` (which already adds the package); it was
  *also* separately hardcoded into `home.packages` before this fix,
  causing a real duplicate.
- `modules/suites/tui-apps.nix`: removed the `programs.zellij.enable =
  true` and `programs.lazygit.enable = true` blocks - both were
  confirmed (by reading home-manager's own module source for each) to
  be pure no-ops beyond re-adding the package a second time (neither
  config's other options were ever set), since the KDL config for
  zellij is written independently via `home.file`, and lazygit needs no
  HM-level config at all here.
- `modules/core/default.nix`: removed the explicit `bash` package-list
  entry - same duplicate class as the already-fixed direnv/lsd/zoxide/
  fzf/bat (round 5); `programs.bash.enable` already adds it.
- `modules/suites/gui-apps.nix`: added a documenting comment on
  `programs.wezterm` explaining it's an accepted, currently-inert
  package-duplication tradeoff (unlike lazygit/zellij, wezterm's
  `package` option is NOT nullable, and it has real `extraConfig` this
  module needs - avoiding the duplicate would require hand-rolling the
  Lua config via `home.file` instead; not worth doing for a feature
  that's enabled nowhere today).
- `modules/suites/ai-apps.nix`: removed dead `piDataDir` let-binding
  (explicitly commented "legacy, kept for reference but not used" -
  confirmed genuinely unreferenced anywhere in the file).
- `modules/features/butterfish.nix`: wired up the previously-declared-
  but-unused `shell` option (was always hardcoded to bash regardless of
  the setting) - `bf`'s `-b` flag now actually resolves to
  `pkgs.zsh`/`pkgs.bash` based on `cfg.shell`; tightened its type from
  freeform `str` to `enum [ "bash" "zsh" ]` and clarified in its
  description that this only affects the shell butterfish itself
  spawns, not the user's actual login/interactive shell (which stays
  bash-only regardless, per nixon.nix).
- `README.md`: added missing feature-table rows for `butterfish`,
  `llama-cpp`, `nix` (nix-tools.nix - noted as "not enabled on any host
  today", same as the existing `fonts` precedent), `quarkdown`,
  `sd-switch`, `wsl-shell-integration` - all real, fully-implemented
  features that were simply never added to the table.
- `memory-bank/open-questions.md`: marked the "flake output naming"
  question RESOLVED (already executed as `default`/`default-opt` back
  in Phase 2, just never marked done here); rewrote the "sync.sh/
  setup.sh deeper improvements" entry to reflect the substantial work
  that has landed since it was written (named syncables, `sync.sh -g`,
  the ssh-assertion bug fix, the real template files) rather than
  reading as still "explicitly deferred, entirely untouched".

**Investigated but NOT changed (findings, not bugs):**
- `modules/flake/alien-package-specs.nix` - confirmed still genuinely
  used (imported directly by `flake.nix:94`), not vestigial; the
  "duplicate discovery engines" issue this filename evokes (see
  `learnings.md`'s 2026-07-18 entry) was already resolved back in
  Phase 3 by extracting shared logic into `alien-discovery.nix` (see
  `plan.md:306-307`) - both `alien-package-specs.nix` (flake-level) and
  `core/alien-packages.nix` (home-level) now call into that shared
  helper rather than duplicating it.
- Seriously considered, then reverted, a "fix" to `modules/core/
  nix-tools.nix`'s `lib.mkIf cfg.foo pkg` pattern inside a
  `home.packages` list literal, believing it to be the same class of
  bug as the ssh-settings one - empirically proven NOT to be a bug (see
  `learnings.md`'s 2026-07-19 "listOf v2 merge" entry for the full
  mechanism and why). No code change needed there or in
  `viewer.nix`/`dev-tools.nix`, which use the identical pattern.

**Validated**: diff shows *exactly* the intended removals (one each of
`bash`/`delta`/`zellij`, two of `lazygit`, one of `gh`) and nothing else.

---

### 2026-07-19 — `suites.git-tools.jj` was installing the wrong package entirely
User caught this directly: nixpkgs' `pkgs.jj` attribute is **not**
Jujutsu (https://github.com/jj-vcs/jj, the VCS this option's
description ("jj (Git alternative)") clearly refers to, and what
`suites.git-tools.jj = true` was meant to enable) - it's
`tidwall/jj`, an unrelated JSON Stream Editor (confirmed via `nix eval
.#homeConfigurations.default.pkgs.jj.meta.{description,homepage}` →
"JSON Stream Editor (command line utility)" /
`https://github.com/tidwall/jj`). Real Jujutsu lives under the
`pkgs.jujutsu` attribute instead (confirmed:
`meta.description` = "Git-compatible DVCS that is both simple and
powerful", `meta.homepage` = `https://jj-vcs.dev/`,
`meta.mainProgram` = `"jj"`). `pkgs.jjui` (the TUI, idursun/jjui) was
never affected - it's a correctly-named, separate package that already
depends on the real `jj` binary at runtime regardless of which `jj`
attribute `dots` itself installed alongside it.

**Fix**: `modules/suites/git-tools.nix`'s `jj` app entry now uses
`pkgs.jujutsu` instead of `pkgs.jj`. No user-facing change to the CLI
surface - `jujutsu`'s `meta.mainProgram` is still `jj`, so the command
stays `jj` either way; only the nixpkgs *attribute name* was wrong, not
the binary users would type. Verified: `nix build` now fetches
`jujutsu-0.43.0` (previously would have fetched the unrelated
`jj-1.9.2` JSON tool), and its `bin/` directory contains exactly one
binary, `jj`.

**Considered but not needed**: since `pkgs.jj` (the JSON tool) isn't
referenced anywhere else in `dots` (confirmed via repo-wide grep), there
was never an actual on-PATH collision between the two - this was purely
"the wrong package was silently installed under the right command
name," not "two different `jj` binaries fighting over PATH priority."
If `dots` ever *also* wants the JSON Stream Editor for its own sake in
the future, it would need an explicit rename/wrapper at that point
(e.g. `pkgs.jj // { ... }` aliased under a distinct `home.packages`
entry, or renaming its binary via `pkgs.runCommand`/`symlinkJoin` to
something like `jj-json` before adding it) to avoid then colliding with
`jujutsu`'s real `jj` - not done now since nothing currently needs it.

---

### 2026-07-19 — `NIXON=1` mode never guaranteed the raw `nix` binary was on PATH (root cause of a real `apply-dots` failure)
User reported `apply-dots` failing with `nh`: "Failed to get Nix
version output... No output from nix --version command". Root-caused
to a real, live-impacting bug in `modules/core/nixon.nix`: the
`NIXON=0` ("pure host") branch of `.bashrc-dots` explicitly does
`export PATH="$PATH:/nix/var/nix/profiles/default/bin"` (the directory
containing the actual system Nix installation's `nix`/`nix-daemon`
binaries - confirmed this is NOT part of the Home Manager profile;
`~/.nix-profile/bin/nix` does not exist, Nix itself is a system-level
install, not a `home.packages` entry), but the `NIXON=1` ("nix-on")
branch only sources `.bashrc-nix` (pure Home Manager gutter-eval
output), which has no PATH-setting logic of its own for this directory
- confirmed via direct inspection, it contains zero `PATH=` lines.
`.profile-nix` (sourced only for *login* shells, only when NIXON=1)
does eventually reach `nix.sh` via `hm-session-vars.sh`, which adds
`~/.nix-profile/bin`, but never the raw system installation's own bin
dir either.

**Consequence**: any shell that starts directly in NIXON=1 mode
without inheriting PATH from a prior NIXON=0 ancestor in the same
process tree (via `nixon`'s `exec bash -l`) - most commonly, any
*non-login* interactive shell (e.g. a fresh terminal opened inside an
already-running graphical session, which is the overwhelmingly common
case) that starts with NIXON=1 either as the default or via inherited
systemd/PAM environment - has **no working `nix`/`nh`/`home-manager`
at all**. Confirmed by inspecting the actual live environment: `NIXON=1`
was set, but `$PATH` had no `/nix/var/nix/profiles/default/bin` and no
`/nix/store/...` entries whatsoever - `nix --version` failed with
`command not found`, exactly matching `nh`'s reported symptom (its
internal `nix --version` subprocess call had nothing to exec).

**Fix**: added an unconditional, idempotent (`case ":$PATH:" in
*":/nix/var/nix/profiles/default/bin:"*) ;; ...`) PATH guard in
`.bashrc-dots`, positioned *before* the NIXON if/else, so both branches
are guaranteed to have the raw Nix installation reachable regardless of
which one runs. NIXON=0's own existing strip-then-readd logic is
unaffected (it strips everything matching `/nix` from PATH first, which
also removes what the new guard just added, then re-adds it back
itself - composes correctly, no behavior change there).

**Validated**: a REAL `apply-dots` run on chromaden (previously
reproducing the exact reported failure) completed successfully
end-to-end; fresh `bash -l` afterward confirms `NIXON=1` with `nix`/`nh`
both resolving correctly, and `nixoff` still works too.

**Related, separate fix in this same round**: found (via the running
`apply-dots` output itself, and via `~/dots-local`'s own uncommitted
working tree) that chromaden's real `dots-local/flake.nix` had
`nixonDefault` present but *disabled and mistyped* - `#nixonDefault =
"1";` (commented out, and using the string `"1"` rather than the
schema's `types.bool`). This was clearly a half-finished attempt by the
user to set it - fixed to an active, correctly-typed `nixonDefault =
true;`, matching their evident intent (and now functions correctly
end-to-end thanks to the PATH fix above). `templates/dots-local/
flake.nix` already set this field as a plain, uncommented, correctly-
typed value (`nixonDefault = false;`) for brand-new machines - no
change needed there, just confirmed. Added a `$NIXON`/`nixon`/`nixoff`
section to README.md (previously undocumented anywhere outside code
comments and the schema option description) and a mention of deciding
on `nixonDefault` to `setup.sh`'s "Next steps" output, so new users are
actually aware this choice exists rather than silently inheriting the
schema default.

---

### 2026-07-19 — Dead-code audit round (user-requested, itemized approval)
User asked whether `modules/profiles` (vs `modules/contexts`) was still
needed, plus a general dead-code sweep with per-item removal approval.
Clarified there is no `modules/profiles` - the top-level `profiles/`
directory is a different, still-needed thing (plain data read by
`sync.sh`/`appimage-update`, keyed by the same profile-name strings as
`modules/contexts/` for convenience, not redundant with it). Ran a
thorough research-agent audit + direct `nix eval` verification; user
approved the following fixes:

- **`modules/suites/sixel-tools.nix`**: real bug, not just dead code -
  `home.sessionVariables = { FONTCONFIG_FILE = ...; } // (lib.mkIf
  cfg.ytdlp {...})` silently dropped `FONTCONFIG_FILE` entirely in
  every configuration (confirmed via `nix eval` - the attribute didn't
  exist in the final config at all). Same root mechanism as the
  ssh-settings/`listOf` mkIf-in-a-list investigations already in this
  log, but a third, distinct variant: merging an `lib.mkIf` result into
  a plain attrset via `//` makes the WHOLE merged value's outer shape
  become the mkIf wrapper, not just the mkIf'd key. Fixed with
  `lib.mkMerge [ {...} (lib.mkIf ... {...}) ]` - the correct idiom for
  "always this, plus conditionally that" on an attrsOf-typed option.
  Re-verified via `nix eval`: `FONTCONFIG_FILE` now resolves correctly,
  `MPV_YTDL_EXE` unaffected.
- **`modules/suites/dev-tools.nix`**: the generated `~/.nixd.json`
  referenced `homeConfigurations."${config.home.username}"`, which has
  never existed in this repo (always `priv`/`work` or `default`/
  `default-opt`, never username-keyed) - confirmed via `git log -p`
  unchanged since the file's very first version, predating even the
  priv/work split. Fixed to `homeConfigurations.default.options`.
  nixd's option-completion for home-manager config was likely never
  working correctly before this fix.
- **`modules/features/viewer.nix`**: removed the dead `_v_warn_images`
  bash function (defined in `programs.bash.initExtra`, confirmed zero
  call sites anywhere including `v.sh`).
- **`modules/core/scripts.nix`**: removed `"$HOME/dots/bin"` from
  `home.sessionPath` - that directory never existed post-Phase-8
  (scripts were externalized into per-module `scripts/` subdirectories
  instead, e.g. `modules/features/viewer/v.sh`), leftover PATH entry
  never cleaned up alongside that move.
- **`profiles/priv/sync.json`**: deleted - confirmed byte-identical
  (md5) to `profiles/common/sync.json`, meaning `sync.sh` was merging
  the same ~150 ignore patterns twice for the priv profile. `sync.sh`
  already handles a missing profile-specific file gracefully. Fixed
  `SYNC.md`'s description to clarify the actual intended design
  (common = shared baseline where the real list lives; per-profile
  files are optional, addition-only, not full copies) and to stop
  documenting a `profiles/work/sync.json` that has never existed.
- **`etc/` directory** (bootloader/greetd configs, wallpapers, niri
  desktop session files - confirmed present since the project's very
  first commit, zero references anywhere in code/docs): user confirmed
  this is intentional, hand-maintained reinstall reference material,
  not meant to be wired into the `settings/`-based sync automation.
  Documented explicitly in `AGENTS.md`'s directory layout so it's never
  mistaken for dead code again.

**Investigated but left open, pending user clarification**: the
`.feature = "..."` key present in every `*.<distro>-packages.nix` alien
spec file (~80+ occurrences). Confirmed via `git show` of the
repo's very first `alien-packages.nix` (commit `ecd7c0c`, predating
this entire re-architecture) that it has **never** been read by either
consumer (`alien-package-specs.nix`/`alien-packages.nix` both only ever
read `.packages`) - not a regression, always inert. User recalled
intending it to "bind to the corresponding Nix package as an
alternative overlay" but this wiring was never actually implemented
anywhere retrievable (checked `OVERVIEW.md`/`architecture.md`/
`decisions.md`/`learnings.md` for any "alternative overlay" mention -
none found relating to this field). Not removed - see
`open-questions.md` for the follow-up question to resolve before
deciding whether to implement the recalled intent or just document it
as inert self-labeling metadata (matching the `barch`/`location`-axis
precedent for kept-but-unconsumed fields).

**Validated**: zero package-list impact from this round, as expected
(all config/doc-only fixes).

---

### 2026-07-19 — `.feature` key removed; added alien-spec conflict detection instead
Follow-up to the open question above: user clarified the original
intent (alien package shadows the Nix counterpart when a feature is
enabled) is already fully achieved by plain package-name matching,
independent of the `.feature` field - confirmed nothing to salvage.
Removed all ~101 occurrences across every `*.<distro>-packages.nix`
file; updated `OVERVIEW.md`/`AGENTS.md`'s doc examples to match, and
fixed `AGENTS.md`'s "use the feature name as the key" instruction
(should always have said "package name", independent of this cleanup).

**More significant part of this round**: user proposed a genuinely new
validation, not just a removal - `modules/flake/alien-discovery.nix`'s
`collectAlienSpecs` previously merged all spec files via a plain `//`
fold with an explicitly-documented-but-silent "later files win on key
collision" behavior. Changed it to detect when the same package name is
defined with **different** content by more than one spec file, and
`throw` a clear build-time error (file paths included) rather than
silently picking one. This runs automatically on every `nix build`/
`apply-dots` (alien-spec discovery is already unconditionally on that
path via the `alien` specialArg) - no separate validation script
needed. Identical-content duplicates across files are deliberately NOT
flagged (harmless redundancy, not a real disagreement) - only genuine
divergence.

**Validated**: confirmed zero real conflicts exist today across all 5
distros' specs before adding the check. Verified it actually fires:
temporarily duplicated `nmap`'s key with divergent content across two
files, confirmed the exact expected error, reverted cleanly.

---

### 2026-07-19 — `noctalia-qs` "non-existent input" warning: root-caused and removed
Long-standing (flagged twice previously, deliberately left alone
pending investigation - see the superseded `open-questions.md` entry)
cosmetic warning on every eval: `input 'noctalia' has an override for a
non-existent input 'noctalia-qs'`. Root-caused conclusively this time:
fetched `noctalia-shell`'s own `flake.nix` directly from GitHub (and
cross-checked via `nix flake metadata github:noctalia-dev/
noctalia-shell --json`'s `locks.nodes.root.inputs`) - it declares only
`nixpkgs` as an input, never `noctalia-qs`, and never has. `dots`'s own
`inputs.noctalia.inputs.noctalia-qs.follows = "noctalia-qs";` was
therefore always a permanent no-op, not a transient lock-file staleness
issue as previously suspected.

**Fix**: removed just that one cross-reference line from the `noctalia`
input block. Did NOT touch the separate, standalone `noctalia-qs` flake
input declared right below it (`noctalia-qs = { url = "github:
noctalia-dev/noctalia-qs"; ...};`) - that one is genuinely used
elsewhere (`noctalia-qs.enable`, `noctalia-qs.overlays.default`) and was
never actually part of the dead cross-reference; the two coincidentally
share a name but are otherwise unrelated.

**Validated**: warning confirmed gone; zero behavior change (purely
removed a no-op line).

---

### 2026-07-19 — `modules/core/platform.nix`: consolidated clipboard/opener backend detection
Resolved the long-pending (since Phase 2) "needs explicit slot"
cross-cutting item: `features.clipboard.backend`/`features.opener
.backend` were two independently-declared `enum [ "wayland" "x11"
"wsl" "macos" ]` options with no default, both set to the identical
value by the same two `rules.nix` rules (WSL -> `"wsl"`, niri desktop
-> `dotsLocal.graphicalBackend`) - confirmed via repo-wide grep that
nothing ever overrode them independently, so a single shared value was
always safe.

**Implementation**: new `modules/core/platform.nix` exposes
`config.core.platformBackend` (`nullOr (enum [...])`, `readOnly =
true`, default computed directly from `dotsLocal.isWsl`/`compositor`/
`graphicalBackend`). Imported universally in `composition.nix` (same
reasoning as `features.opener`/`features.clipboard` themselves - their
config needs this option path to exist regardless of context).
`clipboard.nix`/`opener.nix` no longer declare their own `backend`
option at all - they read `config.core.platformBackend` directly, with
an explicit `assertions` entry (clear message, not a raw Nix
attribute-lookup crash) if ever enabled while it resolves to `null`.
`rules.nix`'s two rules now only set `enable = true` for both
features - the backend VALUE is no longer set there at all, since it's
derived automatically from the exact same `dotsLocal` fields those
rules already gate on.

**Deliberately NOT done**: did not wire `network.nix` (ssh-agent socket
path) or `viewer.nix` (image viewer choice) into this - both were
flagged as "follow-up candidates" for the same platform-detection
consolidation, but there's no macOS host to validate against and no
concrete logic drafted for either yet. Revisit if/when a real need
emerges, same status as before this round.

**Validated**: three synthetic scenarios (default niri/wayland, WSL,
and `compositor = null` with clipboard force-enabled) - all resolve
correctly, including the null-backend case producing the intended clear
assertion instead of a raw crash. Byte-identical for the real config.
Updated README.md/OVERVIEW.md to stop describing `backend` as
user-settable.

---

### 2026-07-19 — Extended Debian (bookworm) alien specs: sixel-tools, cloud-tools, dev-tools, ai-apps
User now has a real Debian 12 (bookworm) machine and specified which
suites it needs. Extended `*.debian-packages.nix` coverage for all
four, verifying every candidate package's presence in bookworm's
**official** archive individually via packages.debian.org before
including it (matching the existing conservative,
official-repos-only convention from `network-tools.debian-packages.nix`/
`tui-apps.debian-packages.nix`):

- **Included** (confirmed present in bookworm's official main archive):
  `chafa`, `catimg`, `yt-dlp` (sixel-tools); `gh`, `azure-cli`
  (cloud-tools); `caddy` (dev-tools); `libfuse2` for the
  `appimages-fuse` alien-spec key (ai-apps, apt's FUSE2 compat package
  is named differently than pacman's `fuse2`).
- **Excluded** (confirmed NOT in the official archive, or inconclusive):
  `lsix` (sixel-tools - no Debian package found at all); `lazydocker`
  (cloud-tools - confirmed unofficial-only, via the third-party
  deb.griffo.io repo per that project's own docs); `marksman` (dev-tools
  - only available via Snapcraft/direct GitHub releases per upstream);
  `mkcert` (dev-tools - inconclusive, treated as "not confirmed" per the
  conservative convention); `opencode`/`github-copilot-cli`/`graphify`
  (ai-apps - none found in the official archive, all niche/recent tools
  typically self-installed rather than distro-packaged).

**Also noted, not fixed** (pre-existing, out of scope for this
request): the `appimages-fuse` alien-spec key (both the pre-existing
cachyos entry and the new debian one) is never actually referenced by
any `alienPackages.enabledPackages` list anywhere in the codebase -
confirmed via repo-wide grep, it only appears in the two spec files
themselves. This is a dormant/orphaned spec (matches the existing
cachyos file's state, not a new inconsistency introduced here) - would
need wiring into `features/appimages.nix` (or wherever FUSE2 support
is actually meant to be conditionally required) to ever take effect.
Left as-is since fixing it wasn't requested and doing so would need
its own design decision about when FUSE2 should actually be required.

**Validated**: real (cachyos) config unaffected, as expected. A
synthetic `distro = "debian"` config with all four suites force-enabled
confirmed: no spec conflicts, every newly-covered package correctly
alien-shadows its Nix counterpart while uncovered ones
(`marksman`/`mkcert`) correctly stay as Nix fallback, and
`required/apt.txt` contains exactly the expected names.

---

### 2026-07-19 — `pkgs/quarkdown.nix` rewritten for v2.4.0: dropped the Nix-provided `jre` entirely
User asked to update to the just-released Quarkdown 2.4.0 and, in the
same pass, throw away the old setup's complexity ("massively
complicated due to having to pin versions of dependencies").

**Root cause of the old complexity**: the v2.0.0-era release only
shipped a lib-only `quarkdown.zip` (jars, no runtime), requiring `dots`
to supply its own `jre` and a hand-substituted launcher script
(`pkgs/quarkdown-launcher.sh`, `--subst-var-by JAVA_CMD/APP_HOME`) -
meaning the Nix-provided JRE version had to stay compatible with
whatever JVM bytecode/dependencies that specific Quarkdown release was
built against, an ongoing pinning burden across upgrades.

**What changed upstream**: as of v2.1.0 (per its changelog - "Bundled
Java runtime" - confirmed by inspecting the actual v2.4.0 release
assets), Quarkdown ships fully self-contained **per-platform** archives
(`quarkdown-linux-x64.zip`, `quarkdown-macos-*.zip`, `quarkdown-
windows-x64.zip` - no more generic `quarkdown.zip`) bundling their own
~50MB jlink-trimmed JRE (`runtime/`) alongside the launcher (`bin/
quarkdown`) and jars (`lib/`). Inspected the bundled launcher script
directly: it's a standard Gradle-generated POSIX start script (APP_HOME
resolved relative to `$0`, following symlinks) with a small prepended
prelude that auto-detects `$SCRIPT_DIR/../runtime` and sets `JAVA_HOME`
to it when present - fully relocatable, no absolute-path assumptions,
as long as the `bin/`+`lib/`+`runtime/` directory structure is preserved
verbatim relative to each other.

**Fix**: rewrote `pkgs/quarkdown.nix` to just `fetchzip` the
`quarkdown-linux-x64.zip` release asset (`stripRoot = true`) and copy
the whole extracted tree into `$out` unmodified (`cp -r . $out/;
chmod +x $out/bin/quarkdown`). No `jre` input, no launcher-script
substitution, no version-compatibility pinning to maintain going
forward - upstream's own bundled runtime is used as-is. Deleted the
now-unused `pkgs/quarkdown-launcher.sh`. Added `meta.platforms = [
"x86_64-linux" ]` since only that Linux architecture's bundle is
wired up (macOS/Windows assets exist upstream but aren't fetched -
no current need, `dots` doesn't target those platforms today).

**Validated**: built the derivation directly and ran the resulting
binary - `quarkdown --version` reports `2.4.0`, and a full `quarkdown c`
compile succeeded end-to-end with correct rendered HTML output. Bundled
JRE runs with zero patching needed (`autoPatchelfHook` etc. not
required - this project targets Nix atop a real FHS distro, not NixOS,
so a prebuilt ELF binary finds the host's own glibc/dynamic-linker
normally). `features.quarkdown.enable = false` on chromaden currently,
so zero live effect either way - correctness validated by direct
invocation instead.

---

### 2026-07-19 — `nixpkgs-quarto-pin`: simplified to a quarto-only pin, dropped the redundant pandoc override
User (correctly) asked whether the pinned-nixpkgs input for quarto/
pandoc was still needed, suspecting leftover complexity similar to the
Quarkdown JRE situation just fixed. Investigated with hard evidence
rather than trusting the existing (already-known-partially-stale, see
the 2026-07-18 "cosmetic warning" investigation entry) flake.nix
comment:

- Built `quarto` directly from **current** `nixos-unstable` (fetched
  live) - version 1.9.37. `quarto check`'s "basic markdown render" step
  genuinely fails: `Aeson exception: Error in $: Unknown option
  "syntax-highlighting"` - a real, reproducible functional break, not
  just a benign strict-version-check warning (quarto 1.9.37 passes a
  pandoc CLI flag that doesn't exist until pandoc 3.8+).
- Built `quarto` from the pinned revision (`15f4ee454b...`) - version
  1.8.26. Same check passes cleanly with no error.
- **Critically**: checked what pandoc version is actually in play in
  both cases by reading each `quarto` binary's own hardcoded
  `QUARTO_PANDOC` default (baked in at nixpkgs build time) - both the
  pinned revision AND current unstable resolve to pandoc **3.7.0.2**,
  identically. The existing flake.nix comment's claim of "pandoc
  3.1.11.1" was simply wrong (matching the earlier-logged, previously
  "pre-existing, unrelated" stale-comment finding) - pandoc's version
  was never actually different between the two revisions; only
  quarto's version (and thus its own compiled-in pandoc-CLI-flag
  expectations) is what matters.
- Confirmed neither existing consumer of `pkgs.pandoc`
  (`tui-apps.nix`, `dev-tools.nix`) has any special dependency on the
  specific pinned build - both just want "a normal pandoc".

**Fix**: removed the `pandoc = inputs.nixpkgs-quarto-pin...` line from
`externalOverlay` entirely - only `quarto` is still sourced from the
pin. `pkgs.pandoc` now resolves to plain main-`nixpkgs` pandoc
everywhere (same reported version, 3.7.0.2, just from the main input
instead of a redundant separate build). Rewrote both the
`nixpkgs-quarto-pin` input comment and the overlay comment to describe
the actual, verified reason (a quarto version-compatibility pin, not a
pandoc version pin) with the concrete evidence above, rather than
perpetuating the stale claim.

**Validated**: `pkgs.pandoc` now resolves from the main `nixpkgs` input
as expected. Ran `quarto check` using the **exact** combination `dots`
will actually use post-fix (pinned quarto 1.8.26 + main-nixpkgs pandoc)
- renders cleanly.

---

### 2026-07-19 — flake.nix necessity audit: `nur`/`nixgl` confirmed unused, commented out
User asked to go through every flake input/overlay and confirm each is
still actually needed. Audited all 9 (at the time): `nixpkgs`/
`nixpkgs-quarto-pin`/`home-manager`/`niri`/`noctalia`/`noctalia-qs`/
`snippets-ls`/`bookokrat`/`dots-local` all confirmed genuinely consumed
somewhere (direct grep evidence for each - `niri`/`noctalia`'s
`homeModules` imports in `niri-noctalia.nix`, `noctalia-qs`'s real
tune-spec entry in `niri-noctalia.tune-specs.nix`, `snippets-ls`/
`bookokrat`/`quarkdown` all wired through `externalOverlay`, etc.).
`dotsLocal.extraOverlays` (the escape hatch) is real but currently
unset on chromaden - inert-but-legitimate, matching the `barch`/
`location`-axis precedent, not flagged as an issue.

**`nur` and `nixgl` confirmed genuinely unused** - exhaustive grep
across both `dots` and `dots-local` repos found zero consumers: `nixgl`
wasn't even applied as an overlay in `flake.nix`'s own `overlays` list
(despite being declared as an input), and while `nur.overlays.default`
IS applied, nothing anywhere ever reads `pkgs.nur.*`.

This directly bumps into the Phase 1/2-era "preserve all overlays/
package sources, non-negotiable" directive (`architecture.md` section
1b, `decisions.md` 2026-07-18) - flagged this explicitly rather than
silently removing, since that directive was on record. User's decision:
**keep both, but commented out** (not deleted) - preserves easy
reactivation later (nixgl in particular is the standard fix for
OpenGL-dependent packages on non-NixOS hosts, plausible future need
given this project's whole "Nix atop a real FHS distro" premise) while
being honest that neither is currently doing anything.

**Implementation**: commented out `nur.url`/`nixgl = {...}` in
`flake.nix`'s `inputs` block (with a comment explaining what's needed
to re-enable each), removed both from the `outputs = { ... }:`
function's destructured argument list (required - Nix errors on a
named-but-absent input otherwise), and commented out
`nur.overlays.default` from the applied `overlays` list in
`mkHomeConfig`.

**Validated**: `nixgl`/`nur` and all their transitive sub-inputs cleanly
removed from the lock graph; zero package-list impact, as expected.
Updated `architecture.md`/`preserved-features-checklist.md` in place to
note this explicitly-authorized exception.

---

### 2026-07-19 — `dots-local`'s sync-config.json confirmed still relevant (it's a generated cache, correctly not templated); `templates/dots-local/` renamed to `templates/local/`; added `templates/local/host.nix`
User asked whether `dots-local`'s `sync-config.json` was still relevant,
and if so why it wasn't represented in the template. Investigated
`sync.sh` directly: `sync-config.json` is a **generated cache artifact**
- `ensure_sync_config_current()` auto-regenerates it from `dots-local/
flake.nix`'s `sync` field (`enable`/`tracked`) plus dots's own
`modules/core/syncables.nix` registry, on every single `sync.sh`
invocation (mtime-checked, unconditional with `-g`/`--force-regen`).
Confirmed correctly gitignored in both the real `dots-local` and the
template (`templates/dots-local/gitignore`, now `templates/local/
gitignore`) - it's not something a user ever hand-authors, so it
correctly has no template counterpart. The REAL source (`dotsLocal.sync
.enable`/`.tracked`) was already present in the template's `flake.nix`
as a commented-out example - nothing was actually missing. While
checking this, found and fixed two genuinely stale, unrelated
`SYNC.md` doc bugs: its "Initial setup on new machine" section told
readers to manually run `nix eval --json .#sync > sync-config.json`,
which has been unnecessary since `sync.sh`'s auto-regeneration was
added (post-Phase-9 round 7) - replaced with just running `dots-sync`.

**Rename**: `templates/dots-local/` → `templates/local/`, following the
earlier `modules/dots-local/` → `modules/local/` precedent (same
"drop the redundant `dots-local` qualifier once it's unambiguous from
context" reasoning). Updated every current-state reference across
`setup.sh`, `AGENTS.md`, `SYNC.md`, and `architecture.md` (a living
document, updated in place per its own section 12 rule #5) - left
`decisions.md`/`plan.md`/`open-questions.md`'s existing historical
entries using the old name untouched (they describe what was true when
written, matching this project's established convention of appending
new entries rather than rewriting old ones for pure renames).

**New `templates/local/host.nix`**: user asked for a generic, always-
present host-specific escape-hatch file in the template (mirroring
chromaden's real `host-chromaden.nix`, but explicitly NOT weaving the
hostname into the filename - "one machine, one dots-local checkout, one
host.nix" per the user's own framing). Added as a deliberately
near-empty module (commented-out illustrative examples only, matching
the style of the rest of the template) and wired into `flake.nix`'s
`extraModules` **unconditionally** (not commented out) - matching
`appimages.nix`'s own "always present, always imported" pattern rather
than treating it as one-of-several optional axis examples. `setup.sh`
updated to copy and `git add` it alongside the other template files;
its "Next steps" output updated to mention it.

**Validated**: real `setup.sh priv` invocation end-to-end (not just the
identity-substitution half) - `host.nix` copied/committed correctly, the
freshly-generated `dots-local` builds cleanly. Real chromaden config
unaffected, as expected.

### 2026-07-20 — Post-rollout fixes: default graphical backend, SSH agent option, `setup.sh --list`, and `profile`→`context` rename

Prompted by the user finishing real setup on two new machines and
reporting three concrete gaps, all fixed together:

1. **`graphicalBackend` now defaults to `"none"`, not `"wayland"`.** Added
   `"none"` to the enum (`modules/local/schema.nix`). A brand-new machine
   with no compositor configured was previously still getting a graphical
   config by default, which is wrong for CLI-only boxes.

2. **New `core.enableGuiDefaults` derived option** (`modules/core/
   platform.nix`), computed as `dotsLocal.enableGuiDefaults &&
   dotsLocal.graphicalBackend != "none"` — mirrors the existing
   `core.platformBackend` pattern (compute an axis-derived value once,
   here, rather than re-deriving ad hoc per consumer). `modules/contexts/
   priv.nix` (the only context with GUI-conditional logic) now reads this
   instead of the raw `dotsLocal.enableGuiDefaults`, so GUI suites are
   force-disabled whenever there's no graphical backend, regardless of
   what a `dots-local` sets `enableGuiDefaults` to. `rules.nix` could not
   express this directly since its rules are always folded via `mkDefault`
   (an explicit `priv.nix` definition would still win) — this is why the
   fix lives in a dedicated read-only option instead.

3. **New `machine.sshAddKeysToAgent` option** (`modules/local/schema.nix`,
   `types.str`, default `"yes"`, accepts ssh's own yes/no/ask/confirm/
   duration values) — `features/network.nix`'s `AddKeysToAgent` was
   previously hardcoded to `"yes"`; the user had a different value
   configured on their previous setup and needs it configurable again.

4. **`setup.sh --list`/`-l`/`list`** — lists `modules/contexts/*.nix`
   (excluding `common.nix`) and exits 0. `setup.sh <context>` previously
   gave no way to discover valid values without reading source.

5. **Full `profile` → `context` rename**, authorized explicitly by the
   user as an exception to the earlier "existing fields keep their flat
   names to avoid rewriting the live `dots-local/flake.nix`" design note
   (see schema.nix's original comment) — "Ok Dont mind renaming the
   schema field, too but it has to be consistent." Renamed everywhere,
   mechanically but carefully (many unrelated "profile" usages exist in
   this repo — Unix `.profile`/`.bashrc` shell files, `/nix/var/nix/
   profiles`, and the `default`/`default-opt` build-variant axis — all of
   which were correctly left untouched):
   - `modules/local/schema.nix`: `dotsLocal.profile` → `dotsLocal.context`
   - Top-level `profiles/` directory → `contexts/` (`git mv`), holding
     `contexts/<context>/sync.json` and `contexts/<context>/appimages/
     manifest.nix` — distinct from `modules/contexts/` (the Nix module
     bundles); both being named "contexts" is a real naming collision,
     called out explicitly in `AGENTS.md`'s directory tree comment so
     future readers don't conflate them.
   - All consumers updated: `modules/composition.nix`, `modules/
     rules.nix`, `modules/features/appimages.nix`, `flake.nix`, `modules/
     core/dots-local.nix`, `modules/core/scripts.nix`, `sync.sh`.
   - Templates updated: `templates/local/flake.nix` (`@@CONTEXT@@`
     placeholder, was `@@PROFILE@@`), `templates/local/appimages.nix`,
     `templates/local/host.nix`.
   - Docs updated: `README.md`, `OVERVIEW.md`, `AGENTS.md`, `SYNC.md`.
   - This machine's own `~/dots-local/flake.nix` updated (`profile =
     "work"` → `context = "work"`) — required immediately, since without
     it the schema would've silently defaulted this machine back to
     `"priv"` instead of erroring, a real regression that could easily
     have gone unnoticed.

**Validated:** `nix flake check --override-input dots-local git+file://
$HOME/dots-local` passes cleanly; `nix eval .#dotsLocal` confirms
`context: "work"`, `sshAddKeysToAgent: "yes"`; `nix eval .#
dotsLocalOptionsDoc` confirms the live-generated docs correctly reflect
`context` (default `"priv"`), `graphicalBackend` (default `"none"`), and
`machine.sshAddKeysToAgent` — no manual doc-string updates needed there
since it's generated straight from `schema.nix`.

### 2026-07-20 — Salvaged pre-refactor `lub` (WSL2) config from `~/dots-local-old`

User asked to mine `$HOME/dots-local-old` (their pre-refactor `dots-local`
checkout, still containing real per-host configs for `lub`/`chromaden`/
`laputa`/`CPC-splan-26YAT`/`TDC476372020`) for anything salvageable that
the new schema/context system doesn't already cover, specifically calling
out VS Code integration and WSL2. Found and fixed:

1. **`isWsl` was never actually set on this machine's own `dots-local`**
   (`~/dots-local/flake.nix` had it commented out), despite `lub` being a
   real WSL2 kernel (`uname -a` → `-microsoft-standard-WSL2`). This meant
   `rules.nix`'s `isWsl` rule never fired, so `features.opener`,
   `features.clipboard`, and — most importantly — `features.wsl-
   shell-integration` (the VS Code Remote-SSH/WSLg shell-integration
   fixup, ported from `lub.nix`'s old `programs.bash.initExtra` into
   `modules/features/wsl-shell-integration.nix` during the earlier
   re-architecture) were all silently OFF. Fixed by setting `isWsl = true`
   in `~/dots-local/flake.nix`. Nothing needed changing in `dots` itself
   here - the feature already existed and just needed the axis flipped.

2. **`suites.ai-apps`/`suites.tui-apps` were enabled unconditionally in
   every old `lub`/`CPC-splan-26YAT` host file** (opencode, grabcontext,
   pi + a specific ~13-plugin `piPackages` list; btop/gping/imagemagick/
   graphviz) but the new `work` context (this machine now uses `context =
   "work"`, not the old `profile = "priv"`) deliberately ships minimal by
   design (see `modules/contexts/work.nix`'s own comment) - neither suite
   is enabled by default there. Restored both into `~/dots-local/
   host.nix` (this machine's own bespoke-config escape hatch), not into
   `dots` itself, since they're this-machine preferences layered on top
   of a intentionally-lean shared context.

3. **`suites.tui-apps.nix` was only ever imported by `modules/contexts/
   priv.nix`**, not `common.nix` or `work.nix` - so setting `suites.tui-
   apps.*` from `work`-context `host.nix` failed with "option does not
   exist". Moved the import from `priv.nix` to `common.nix` (shared
   across every context) rather than duplicating it into `work.nix` too -
   the suite's own options all default off (`mkEnableOption`), so merely
   making it *reachable* everywhere doesn't change any context's actual
   default behavior, it just lets any context/host opt in.

4. **Small direnv UX tweak (`~/.config/direnv/direnvrc`'s `log_status`
   override, silencing direnv's default noisy multi-line ANSI status
   chatter in favor of one compact colored line) existed in every old
   host file but nowhere in the new repo.** User asked for this to be
   promoted into `dots` itself (not per-host) since `programs.direnv.
   enable` is already universal (`modules/core/default.nix`) - added
   right next to it there, applies to every machine now.

**Deliberately NOT restored** (already fully covered by the new schema,
just needed the right dotsLocal axis rather than a manual snippet):
`SSH_AUTH_SOCK`/`WAYLAND_DISPLAY`/`DIRENV_LOG_FORMAT` session vars (all
set automatically by `rules.nix`'s `isWsl` rule once `isWsl = true`),
`programs.zoxide`/`programs.direnv` `enableBashIntegration = mkForce
false` (handled by `features.wsl-shell-integration` itself), SSH
`identityFile`/`AddKeysToAgent` (already schema fields, this machine's
own values already set/defaulted correctly).

**Validated:** `nix build .#homeConfigurations.default.activationPackage
--override-input dots-local git+file://$HOME/dots-local` succeeds fully
(not just `nix flake check`) - confirms `pi`, `opencode.json`,
`.grabcontext`, `graphify.js`, and the new `direnvrc` all build
correctly with the restored config.

## 2026-07-20: Global (non-context-specific) default-enablement policy for tui/gui/sixel/ai/network suites

User asked to redesign default-enablement of a curated package list
*globally* rather than per-context, using the currently-imperative
per-`priv.nix`-override pattern as the thing to move away from. Final
policy implemented:

- **`suites.tui-apps`**: `zellij`/`yazi` -> unconditional `default =
  true` (via `lib.mkEnableOption "..." // { default = true; }`).
  `gping` -> still bare/false at declaration, but a new
  `suites.tui-apps.gping = lib.mkDefault config.suites.network-
  tools.enable;` added in the module's own `config` (cross-suite
  default: on whenever network-tools is enabled). `graphviz`/
  `imagemagick` -> same pattern, tied to `config.core.
  enableGuiDefaults` instead (on whenever there's a real GUI backend).
- **`suites.network-tools.xh`**: `default = true` (unconditional,
  mirroring the suite's own `enable = mkDefault true`).
- **`suites.ai-apps.opencode`**: `default = true` (implicitly tied to
  `suites.ai-apps.enable`, since the whole suite's config is already
  gated by `cfg.enable`). `suites.ai-apps.pi` deliberately left bare/
  false - explicit user instruction: "disable pi by default even if
  suite is enabled" (comment added in the module explaining why, so
  this doesn't look like an oversight later).
- **`suites.sixel-tools.chafa`/`catimg`**: `default = true` (tied to
  `suites.sixel-tools.enable` the same way opencode is tied to ai-
  apps.enable - confirmed via `ask_user` that "sixel tools + when sixel
  is enabled" meant these two core tools, not the whole suite unconditionally).
- **`suites.gui-apps`**: `enable`, `ghostty`, `keepassxc` -> new
  `lib.mkDefault config.core.enableGuiDefaults` entries in the module's
  own `config` (previously this axis only lived inline in `priv.nix`).
  `librewolf`/`libreoffice` -> removed their old `default = true`,
  now opt-in only (bare `mkEnableOption`), per "only when requested".
  `chromium`'s pre-existing `default = true` deliberately left
  untouched (out of scope for this request).
- **Architectural choice**: `rules.nix`'s `rule.when`/`rule.set` only
  ever receive `dotsLocal` (no `config` access), so any default that
  depends on *another suite's computed config* (gping on network-
  tools.enable, ghostty on core.enableGuiDefaults) was added directly
  in the *consuming* suite module's own `config` block instead (suite
  modules already receive `config` in their args) - avoided any change
  to `rules.nix`'s signature, keeping "derive once, in the natural
  place" intact. `core.enableGuiDefaults` (from `modules/core/
  platform.nix`) was reused as-is as the canonical "real GUI backend
  present" signal for every "when ui is enabled" default in this list.
- **`modules/contexts/common.nix`** now imports all three of
  `tui-apps.nix`/`gui-apps.nix`/`sixel-tools.nix` (previously only
  `tui-apps.nix` had been moved there; `gui-apps.nix`/`sixel-tools.nix`
  were `priv.nix`-only) so every context/host can reach these options,
  though most suites still gate actual installs behind their own
  `enable`.
- **Gotcha discovered and fixed**: `common.nix` had a stale, explicit
  `suites.network-tools.xh = lib.mkDefault false;` left over from
  before this redesign. An option's own inline `default = true` is a
  lower-priority default than an explicit `lib.mkDefault false`
  assigned elsewhere, even though both "look like defaults" - so this
  stale line silently killed the new module-level default. Removed it.
  **Lesson**: whenever a module's own option default is changed/added,
  grep every context file for that same option name and remove any
  now-redundant explicit `mkDefault` assignments, or the module-level
  default becomes dead code. No other stale overrides were found for
  the other changed options (zellij/yazi/opencode/chafa/catimg/ghostty/
  keepassxc/graphviz/imagemagick) - `priv.nix`'s existing explicit
  `true` values for these are harmless duplicates of the new defaults,
  not conflicts.

**Validated:** `nix flake check` and a full `nix build .#home
Configurations.default.activationPackage --override-input dots-local
git+file://$HOME/dots-local` both succeed; `nix eval --json .#home
Configurations.default.config.alienPackages.enabledPackages` confirms
the final computed list includes `ghostty, keepassxc, graphviz,
imagemagick, gping, zellij, yazi, opencode, libreoffice-fresh, zathura,
xh` (the last of these only after the `common.nix` fix above) alongside
this machine's explicit `~/dots-local/host.nix` additions (btop,
libreoffice, zathura). `chafa`/`catimg` correctly absent since this
machine doesn't enable `suites.sixel-tools`.

## 2026-07-20: priv/work/common consolidation - pull shared defaults into common.nix

Following the global default-enablement pass above, went through
`modules/contexts/{common,priv,work}.nix` line-by-line to find (a) values
both `priv.nix` and `work.nix` set identically (real duplication -> move
to `common.nix`) and (b) explicit values in `priv.nix` that had become
dead code because a global `mkDefault` (from this session or the prior
one) already provides the same value.

**Moved into `common.nix`:** `features.network.gpgAgent`,
`programs.bash.initExtra` (GPG_TTY export + GitHub Copilot CLI bash
alias - previously priv-only, now considered universal enough not to
gate behind a context), `suites.git-tools.{lazygit,gh,gh-dash}` (gh/gh-
dash already defaulted true at the option level - restated explicitly in
common.nix purely so the file stays a complete picture, not because it
changes behavior), `suites.dev-tools.json`, `suites.tui-apps.
{btop,gping,lazygit,tailspin}`, `suites.network-tools.doggo`,
`suites.ai-apps.grabcontext`.

**Moved into `modules/suites/gui-apps.nix`'s existing global
`core.enableGuiDefaults`-gated default block** (previously just enable/
ghostty/keepassxc): added `librewolf`, `zathura`, `drawio`, `vscodium`,
`ffmpeg` - now a "desktop app baseline" that applies to any context/host
with a real GUI backend, not just `priv`. **Note**: this reverses part of
the earlier same-day decision that made `librewolf` opt-in-only - user
explicitly asked for it back in the baseline once thinking through the
full desktop app set they actually want (libreoffice remains opt-in-only,
not part of this baseline - not requested).

**Moved into `modules/suites/ai-apps.nix`**: the curated ~13-item
`piPackages` list (previously duplicated verbatim in both `priv.nix` and
`~/dots-local/host.nix`) is now the option's own default value - inert
unless `pi = true` is also set (still off by default everywhere, per the
earlier "disable pi by default" decision), so this doesn't change any
behavior, just removes the duplication.

**`work.nix` reduced to a single line beyond its header comment**:
`suites.network-tools.rclone = true;` (plain assignment, not
`mkDefault` - needed to win over common.nix's own `mkDefault false` for
the same option, since two `mkDefault`s of different values at the same
priority is a hard conflict, not a "last one wins"). This was a deliberate
per-context choice (rclone/cloud-sync treated as work-specific, not moved
into common) - not a duplication removal.

**`priv.nix` shrank substantially**: entire `suites.gui-apps` and
`suites.tui-apps` blocks removed (fully covered by global defaults now),
`suites.network-tools`/`suites.git-tools`/`suites.dev-tools`/`suites.ai-
apps`/`features.network`/`programs.bash` blocks trimmed to only the
attributes that are genuinely priv-specific (jj, gitCredentialManager,
the full dev-tools toolchain list, rclone/curlie, pi's absence, etc.).

**`~/dots-local/host.nix` (this machine)** also cleaned up the same way -
removed now-dead `opencode`/`grabcontext`/`piPackages`/`btop`/`zathura`/
tui-apps.enable, kept only `pi = true` (this machine's own opt-in) and
`libreoffice = true` (still opt-in-only globally).

**Gotcha hit while doing this**: setting `suites.network-tools.rclone =
lib.mkDefault true;` in `work.nix` while `common.nix` already had
`rclone = lib.mkDefault false;` produced a hard eval error ("conflicting
definition values") rather than silently picking one - two `mkDefault`s at
the same priority with different values is an error, not resolved by
declaration order. Fixed by using a plain (higher-priority) assignment in
`work.nix` instead of `mkDefault`, same pattern already used by
`priv.nix`'s explicit overrides.

**Validated**: `nix flake check` and a full `nix build .#home
Configurations.default.activationPackage --override-input dots-local
git+file://$HOME/dots-local` both succeed; `nix eval --json .#home
Configurations.default.config.alienPackages.enabledPackages` produced an
identical package list before and after the `host.nix` cleanup step,
confirming no regression (this machine currently has `context = "work"`,
so this run exercised the new `work.nix` directly, not just `priv.nix`).

## 2026-07-20: Pull common.nix defaults back down into their owning suite/feature modules; tie GPG_TTY/copilot alias to their actual features

Immediately after the priv/work/common consolidation above, went one step
further per user feedback: `common.nix` is *always* imported (every
context pulls it in), so anything set there as `lib.mkDefault true` is
functionally identical to just setting `default = true` on the option
itself in its owning module - moved all such defaults down to their
option declarations instead of leaving them in `common.nix`:

- `features.viewer.enable`, `features.network.{enable,sshAgent,gpgAgent}`,
  `suites.network-tools.{enable,doggo}`, `suites.git-tools.
  {enable,git,delta,lazygit}`, `suites.dev-tools.{enable,nixd,entr,json}`,
  `suites.tui-apps.{btop,lazygit,tailspin}`, `suites.ai-apps.
  grabcontext`, `features.tune.enable` (in `modules/core/tune-support.nix`)
  - all now `lib.mkEnableOption "..." // { default = true; }` at the
  option itself, rather than restated as `mkDefault true` in
  `common.nix`.
- `common.nix` is now a pure import aggregator (no `config = {...}`
  block at all) - just makes `tui-apps`/`gui-apps`/`sixel-tools` suites
  reachable from every context. Its own comment explains why (common.nix
  is always-imported, so "default here" and "the option's own default"
  are the same thing - no reason to duplicate).

**Also fixed two bugs the user flagged directly**: the `GPG_TTY` export
and the `github-copilot-cli` bash alias eval, previously bundled
together as one unconditional `programs.bash.initExtra` in `common.nix`,
were each not actually tied to the feature that makes them meaningful:
  - `GPG_TTY` is only useful when GPG agent/pinentry is actually running
    - moved into `modules/features/network.nix`'s own `config` block,
    `lib.mkIf cfg.gpgAgent`. `gpgAgent`'s own option default was also
    flipped to `true` (previously bare/false, only ever turned on
    explicitly per-context) since GPG agent is now treated as a
    universal default like `sshAgent` already was.
  - the copilot alias is only useful when `suites.ai-apps.copilot` (the
    actual `github-copilot-cli` package toggle) is enabled - moved into
    `modules/suites/ai-apps.nix`'s own `config`, `lib.mkIf cfg.copilot`.
    `copilot` itself is still bare/false by default (nobody had asked
    for a default-on policy for it) - `~/dots-local/host.nix` now
    explicitly sets `suites.ai-apps.copilot = true;` for this machine
    (previously relied on eval always running regardless of whether the
    package was even installed).

**Lesson reinforced**: a shared `initExtra` snippet that references a
tool/service should live in the module that owns that tool/service's
enable flag (gated by `lib.mkIf`), not in a generic always-imported
context file - otherwise the snippet runs unconditionally even on
machines/contexts where the underlying feature is off, and there's no
single place to look to understand why a given shell behavior exists.

**Validated**: `nix flake check` and `nix build .#homeConfigurations.
default.activationPackage --override-input dots-local
git+file://$HOME/dots-local` both succeed; `nix eval --json .#home
Configurations.default.config.alienPackages.enabledPackages` unchanged
from before this pass (plus `github-copilot-cli` now correctly appearing,
since `~/dots-local/host.nix` sets `copilot = true`); inspected the built
`.bashrc-nix` directly and confirmed both `export GPG_TTY=$(tty
2>/dev/null || echo /dev/tty)` and the `if command -v github-copilot-cli`
block render correctly.

## 2026-07-20: sixel-tools.enable and dev-tools.marksman now default true

Two more items pulled to always-on per user feedback, following the same
"default at the option itself, since common.nix/dev-tools are always
imported" pattern as the rest of today's consolidation:
- `suites.sixel-tools.enable` -> `default = true` (chafa/catimg already
  defaulted true individually; the suite gate itself hadn't been flipped
  yet, so it never actually installed on any machine that didn't
  explicitly opt in).
- `suites.dev-tools.marksman` -> `default = true`, since `helix` (the
  core editor, unconditionally installed in `modules/core/default.nix`)
  needs it as its Markdown LSP, same rationale as `bash-language-server`
  sitting right next to `helix` in that same package list. Removed the
  now-redundant explicit `marksman = true;` from `priv.nix`.

Validated via `nix flake check` + full `activationPackage` build;
confirmed `chafa`/`catimg`/`marksman` all present in
`config.alienPackages.enabledPackages`.

## 2026-07-20: features.appimages.enable defaults to core.enableGuiDefaults

Considered a separate `dotsLocal.appimagesEnable` toggle first (bool,
default false, shown in the template) but abandoned it per user
feedback: no new schema field at all - `features.appimages.enable`'s
*default* should simply track the same `core.enableGuiDefaults` axis
already used by `suites.gui-apps`/`suites.pim-apps` (which itself is
`dotsLocal.enableGuiDefaults && dotsLocal.graphicalBackend != "none"` -
see `modules/core/platform.nix`). AppImages are predominantly GUI
desktop apps not (yet) packaged for Nix/the native package manager, so
gating them on the same "does this machine actually have a usable GUI"
axis as the rest of the GUI-app baseline is the consistent choice.

Implementation notes:
- Considered doing this in `modules/rules.nix` (mirroring the `isWsl`
  rule right above it) but `rules.nix`'s `when`/`set` functions only
  ever receive raw `dotsLocal`, never the evaluated `config` - so
  `d.enableGuiDefaults` there would miss the `graphicalBackend != "none"`
  carve-out that `core.enableGuiDefaults` provides. Instead, added the
  default straight to `modules/features/appimages.nix`'s own `config`
  (`lib.mkMerge [ { features.appimages.enable = lib.mkDefault
  config.core.enableGuiDefaults; } (lib.mkIf cfg.enable { ... }) ]`),
  mirroring the same cross-module `mkDefault` pattern already used in
  `gui-apps.nix`/`tui-apps.nix`.
- Moved the `../../modules/features/appimages.nix` import from
  `priv.nix` into `common.nix` (it's a plain feature module, no
  priv-specific bits), so the new default actually applies regardless
  of context (`work` included) rather than only ever being reachable
  from `priv`.
- Removed the now-redundant explicit `features.appimages.enable = true;`
  block from `priv.nix` (pure duplication of the new default on any
  priv machine that already has `enableGuiDefaults = true`, which is the
  norm).

**Validated**: `nix flake check` and full `activationPackage` build both
succeed (`--override-input dots-local git+file://$HOME/dots-local`);
`nix eval --json .#homeConfigurations.default.config.features.
appimages.enable` returns `true` on this machine (context `work`,
`enableGuiDefaults = true` in `~/dots-local/flake.nix`) with no explicit
appimages setting in `dots-local` at all - confirming the default now
propagates correctly outside `priv`.

## 2026-07-20: added dots-context-options (companion to dots-local-options)

New `dots-context-options` command (`modules/core/scripts.nix`), same
flag surface (`-i`/`--interactive` via gum filter, plain filter arg
otherwise) as `dots-local-options`, but covering `features.*`/`suites.*`
toggles instead of `dotsLocal` schema fields. Backed by a new
`dotsContextOptionsDoc` flake output (`flake.nix`), generated the same
way (`lib.optionAttrSetToDocList`) but over the full evaluated Home
Manager option tree (`defaultHomeConfig.options`, filtered to
`features.`/`suites.` path prefixes) rather than just
`modules/local/schema.nix`.

Key difference from `dotsLocalOptionsDoc`: each entry also carries
`current` - this machine's actual resolved value (`lib.attrByPath o.loc
null defaultHomeConfig.config`, JSON-stringified via a `tryEval`-guarded
`safeJson` helper to tolerate any non-serializable values without
failing the whole doc). This matters because a lot of these are
`mkDefault`s computed from `dotsLocal` axes (e.g.
`features.appimages.enable`'s declared default is the literal text
`config.core.enableGuiDefaults`, not a plain `true`/`false`) - showing
only the declared default text wouldn't tell a user what's actually
enabled on their machine, unlike `dotsLocal` schema fields which are all
plain literals.

Refactored `mkHomeConfig { optimized = false; }`'s result into its own
`defaultHomeConfig` `let` binding, shared between `homeConfigurations.
default` and `dotsContextOptionsDoc`, so both use the exact same
evaluation (no risk of the doc silently describing a different
config than what `apply-dots` would actually build).

Gotcha hit during implementation: `o.description or ""` (the pattern
already used in `dotsLocalOptionsDoc`) does NOT guard against options
whose `description` attribute exists but is explicitly `null` (common
across upstream Home Manager options, unlike `dots-local`'s own
schema.nix where every option has a real description) - `or` only
covers a *missing* attribute, not a present-but-null one. Fixed via
`if (o.description or null) == null then "" else o.description`.

**Validated**: `nix eval --json .#dotsContextOptionsDoc --override-input
dots-local git+file://$HOME/dots-local` succeeds and correctly shows,
e.g., `features.appimages.enable` (default: "false", current: "true")
and `suites.gui-apps.drawio` (default: "false", current: "true" - from
gui-apps.nix's own enableGuiDefaults-gated block); `nix flake check` and
full `activationPackage` build both succeed; ran the built
`dots-context-options` binary directly (`$GEN/home-path/bin/
dots-context-options appimages` and `... gui-apps`) and confirmed
correct plain-mode output, and `-i` mode correctly reaches `gum filter`
(fails only on "no TTY" in this sandboxed shell, same as
`dots-local-options -i`'s already-accepted failure mode).

## 2026-07-20: coreLib.mkDefault{Enabled,Disabled}Option helpers

Two new helpers in `modules/core/lib.nix`, alongside `mkAppSet`:
- `coreLib.mkDefaultEnabledOption "desc"` = `lib.mkEnableOption "desc" //
  { default = true; }` (the "on by default" idiom already used 32 times
  across 10 files, now named instead of needing the `// {...}` merge
  spotted/understood at every call site).
- `coreLib.mkDefaultDisabledOption "desc"` = plain `lib.mkEnableOption
  "desc"` (mkEnableOption's own default is already `false`) - added
  purely for call-site symmetry/consistency with the above, per explicit
  user request ("Be consistent!"): every enable-option declaration in
  the repo now goes through one of these two `coreLib.mkDefault*`
  helpers, rather than mixing bare `lib.mkEnableOption` calls (implying
  "off by default" only by omission) with explicit `coreLib.
  mkDefaultEnabledOption` calls.

Did a full repo-wide sweep (26 files) replacing every remaining plain
`lib.mkEnableOption "..."` call with `coreLib.mkDefaultDisabledOption
"..."`, adding a `coreLib = import ../core/lib.nix { inherit lib; };` (or
`./lib.nix` for files already inside modules/core/) binding to the 11
files that didn't already have one. Every `core/lib.nix` import site
across the whole repo is now consistently bound to the name `coreLib`
(verified via grep - no stragglers under any other binding name).

Found and fixed two pre-existing, unrelated bugs surfaced while touching
gui-apps.nix during this sweep:
- `firefox`/`sublime`/`masterpdfeditor`/`sioyek`/`tuba`/`betterbird`/
  `newsfeed` options were declared as `lib.mkOption "description string"`
  - a copy-paste typo for `lib.mkEnableOption` (`mkOption` requires an
    attrset with `type`/`default`/..., not a bare string; this either
    errors or produces a broken, unusable option depending on what reads
    it). Fixed to `lib.mkEnableOption` (then swept to `coreLib.
    mkDefaultDisabledOption` along with everything else) - all opt-in-off
    by default, matching intent.
- `papers` (GNOME document viewer) was referenced in gui-apps.nix's
  `appSet` (`papers = { enable = cfg.papers; pkg = pkgs.papers; };`) but
  had no corresponding `options.suites.gui-apps.papers` declaration at
  all - a hard eval error ("attribute 'papers' missing") the moment
  anything evaluates the option set fully (which the `coreLib.
  mkDefaultDisabledOption` sweep's own build/check immediately
  triggered). Added the missing option declaration.

**Validated**: `nix flake check` and full `activationPackage` build both
succeed (`--override-input dots-local git+file://$HOME/dots-local`);
`config.alienPackages.enabledPackages` eval unchanged (30 packages); the
full build reused the exact same store path from before this sweep,
confirming zero behavioral drift from the mechanical rename.

### 2026-07-20 — Split DTP tools into `suites.dtp-tools`; relocate bandwhich/gping/rclone
**Decision:** Created a new `modules/suites/dtp-tools.nix` suite
consolidating the two previously-duplicated, independent DTP option sets
(`suites.dev-tools.{quarto,typst,pandoc}` and `suites.tui-apps.
{imagemagick,graphviz,pandoc,typst}`) into one place: `imagemagick`,
`graphviz`, `pandoc`, `typst` (all alien-managed via `mkAppSet`) plus
`quarto` (still a plain `home.packages` entry via the pinned
`nixpkgs-quarto-pin` overlay, not alien-managed - unchanged handling from
its old home in dev-tools.nix). `suites.dtp-tools.enable` defaults to
`lib.mkDefault config.suites.tui-apps.enable` (the "consolidate with
tui-apps" cross-suite tie, same pattern tui-apps.nix already used for its
own `gping` default); `typst`/`pandoc` default to `cfg.enable`; `graphviz`/
`imagemagick` default to `config.core.enableGuiDefaults` (preserving
tui-apps.nix's original GUI-tied logic for those two specifically).
Also relocated `bandwhich`/`gping` from `suites.tui-apps` into
`suites.network-tools` (both are network-monitoring tools, a better fit;
`gping` now just uses `coreLib.mkDefaultEnabledOption` directly since it
lives inside network-tools itself, which already defaults `enable = true`
- no more cross-suite tie needed), and `rclone` from `suites.network-tools`
into `suites.cloud-tools` (a cloud-storage sync tool, better fit there).
Migrated all corresponding alien-package spec files: new `dtp-tools.
{cachyos,debian,azurelinux3,azurelinux4}-packages.nix` (only the distros
that already had entries for these packages under tui-apps); `bandwhich`/
`gping` specs moved into `network-tools.cachyos-packages.nix` (only
cachyos had them); `rclone` specs moved into `cloud-tools.{cachyos,
debian}-packages.nix`. `tui-apps.{azurelinux3,azurelinux4}-packages.nix`
were deleted outright (their sole entry was `graphviz`, now fully owned by
dtp-tools). Wired `../suites/dtp-tools.nix` into `modules/contexts/
common.nix`'s imports. Context updates: `priv.nix` now sets `suites.
dtp-tools.quarto = true` (dropped from its old `suites.dev-tools` block)
and `suites.cloud-tools.rclone = true` / `suites.network-tools.bandwhich =
true` (both dropped/moved from its old `suites.network-tools` block);
`work.nix` now sets `suites.cloud-tools = { rclone = true; azure = true;
};` (previously just `suites.network-tools.rclone = true;`). `~/dots-
local/host.nix` (this machine, context = work) now explicitly sets
`suites.network-tools.bandwhich = true`, since `bandwhich` isn't on for
the work context by any other default. Also added a representative,
fully-commented `suites.*` example block to `templates/local/host.nix`
(previously had zero `suites.*` mentions anywhere in the onboarding
templates - only a single `features.llama-cpp.enable = true;` example).
**Rationale:** `pandoc`/`typst` existed as two entirely separate,
independently-toggleable options in two different suites - a real
duplication bug, not just a stylistic quibble; consolidating into one
DTP-focused suite removes that split-brain state going forward.
`bandwhich`/`gping`/`rclone` were miscategorized relative to their actual
purpose (network monitoring vs. general TUI grab-bag; cloud sync vs.
general network tooling).
**Validated:** `nix flake check` and a full `nix build .#homeConfigurations.
default.activationPackage` both succeed (`--override-input dots-local
git+file://$HOME/dots-local`). Targeted `nix eval` against the real `work`
context (this machine) confirmed exactly the expected resolved values:
`suites.dtp-tools.enable = true` (tracks `tui-apps.enable`), `suites.
dtp-tools.typst = true`, `suites.dtp-tools.pandoc = true` (both cfg.enable-
tied), `suites.dtp-tools.quarto = false` (correctly *not* set for `work` -
only `priv.nix` enables it), `suites.network-tools.bandwhich = true`
(from dots-local's own host.nix), `suites.network-tools.gping = true`
(now-plain default-enabled option), `suites.cloud-tools.azure = true` and
`suites.cloud-tools.rclone = true` (both from `work.nix`).

### 2026-07-20 — Add tasksh/timewarrior/lazytask to `suites.pim-apps`, enable universally in common
**Decision:** Added three Taskwarrior-companion tools to `modules/suites/
pim-apps.nix`: `tasksh` (taskshell - interactive Taskwarrior REPL),
`timewarrior` (time tracker), and `lazytask` (a standalone lazygit-style
TUI for TaskChampion/Taskwarrior-compatible storage, github.com/
OsamaMahmood/lazytask). `tasksh`/`timewarrior` are real nixpkgs packages,
added to the suite's existing `appSet` like every other alien-manageable
option. `lazytask` has **no nixpkgs attribute and no AUR package**
(confirmed via `nix search` and the AUR RPC search API returning zero
results) - explicitly built from source rather than fetched as a
prebuilt-binary tarball (user's explicit instruction: "pull from pacman/
paru if possible, if not build from src. dont want pkgs that pulls a
binary tarball!"), via a new `pkgs/lazytask.nix` using `rustPlatform.
buildRustPackage` (`fetchFromGitHub` at tag `v0.1.0` + `cargoHash` -
Cargo.lock pins `taskchampion` and all transitive deps, including
`libsqlite3-sys`'s bundled/vendored sqlite3 C source, entirely from
crates.io, no git deps, so a plain vendor build works with no extra
native inputs), wired into `flake.nix`'s `externalOverlay` as `pkgs.
external.lazytask` (same override mechanism as quarkdown/bookokrat/
snippets-ls) since it can't go through the alien-package machinery (no
distro package exists to substitute).
Also enabled the whole `suites.pim-apps` suite **universally** in
`modules/contexts/common.nix` (moved its import there from `priv.nix`,
which previously was its only importer) with `tasksh`/`timewarrior`/
`lazytask` all defaulted on - the other pim-apps options (khal/todoman/
pimsync/khard/superproductivity, all genuinely priv/personal-calendar-
specific) stay off by default, still opt-in per context/host as before.
Also fixed a latent alien-spec bug found while touching `modules/suites/
pim-apps.cachyos-packages.nix`: `taskwarrior`'s pacman spec used the
wrong package name (`taskwarrior` instead of Arch's actual `task`),
silently falling back to the (working, but Nix-store-provided rather
than pacman-provided) Nix package on every CachyOS machine; corrected to
`task`, and added `timew` (real Arch pacman name for timewarrior; `task`/
`timew` are both in Arch's official `extra` repo per archlinux.org).
`tasksh` was initially added as AUR-only (`paru = [ "tasksh" ]`), but
**this was reverted the same day** - see the following entry.
**Validated:** `nix flake check` and a full `activationPackage` build
both succeed (`--override-input dots-local git+file://$HOME/dots-local`).
`nix eval .../config.alienPackages.enabledPackages` confirms
`taskwarrior`/`timewarrior` resolve as alien-managed (i.e. matched
against the corrected pacman/paru specs) on this (CachyOS) machine.
Directly ran the standalone-built `lazytask` binary (`--version`/
`--help`) to confirm it actually works, not just that it compiles.

### 2026-07-20 — Drop `tasksh`'s AUR spec entirely: build failed under this machine's Nix toolchain
**Decision:** The AUR `tasksh` PKGBUILD (added in the previous entry)
failed to build via `paru` on this machine with a linker error:
`libtasksh.a: error adding symbols: archive has no index; run ranlib to
add one` / `clang++: error: linker command failed`. This is a static-
library-indexing mismatch between the AUR build environment's `ar`/
`ranlib` and this machine's Nix-supplied `clang`/`binutils` (visible in
the paru log: the C/C++ compiler checks were skipped in favor of
`/home/sp/.nix-profile/bin/cc`/`c++`, but linking still picked up the
Nix store's `binutils`) - an environmental toolchain quirk, not a real
PKGBUILD bug, and not something worth fighting given nixpkgs already
builds `tasksh` correctly.
**Fix:** Removed `tasksh`'s entry from `modules/suites/pim-
apps.cachyos-packages.nix` **entirely** (not just emptied its
`pacman`/`paru` lists) - `collectAlienSpecs` merges spec files keyed by
mere top-level attribute presence, and `alien.mkEntry` treats
`alienSpecs ? pkgName` as "alien takes precedence" regardless of whether
that package's manager-specific lists are actually non-empty for the
current distro. So an *empty-but-present* entry would have suppressed
the Nix package with nothing to install in its place (installing
nothing at all) - only a fully absent key correctly falls through to
`pkgs.tasksh`. Documented this footgun with a comment in the spec file
in place of the deleted entry.
**Validated:** `nix flake check` and a full `activationPackage` build
both succeed. Confirmed via `nix eval` that `home.packages` includes the
plain nixpkgs `tasksh` derivation (`pname == "tasksh"`), and that
`tasksh` no longer appears among the packages actually resolved through
`rawAlienSpecs` in `modules/core/alien-packages.nix`'s
`packagesPerManager` (i.e. `update-alien-packages` won't try to install
it via pacman/paru at all).

### 2026-07-20 — `common.nix` defaults: taskwarrior, quarto+typst, and GUI-gated `tolaria`; `caddy` removed entirely
**Decision:** Three small default-enablement changes requested together:
`suites.pim-apps.taskwarrior` switched from `coreLib.
mkDefaultDisabledOption` to `coreLib.mkDefaultEnabledOption` (now on by
default anywhere `suites.pim-apps` is enabled, i.e. universally per the
entry above). `suites.dtp-tools.quarto` changed from a fixed disabled-by-
default option with no suite-level tie to `lib.mkDefault cfg.enable`
inside the suite's existing `config` merge block, matching how `typst`/
`pandoc` already behaved (quarto's *previous* on-switch was a standalone
`suites.dtp-tools.quarto = true;` in `priv.nix` - removed, since the new
default supersedes it, along with a comment noting other contexts can
still opt in/out explicitly). The `tolaria` AppImage (`priv`-context
only) had its hardcoded `enable = false;` in `contexts/priv/appimages/
manifest.nix` removed and replaced with a new cross-suite default in
`modules/features/appimages.nix`: `features.appimages.apps.tolaria.
enable = lib.mkDefault config.core.enableGuiDefaults;` - mirroring the
existing `features.appimages.enable` GUI-tied pattern, so it now follows
the same "on whenever a GUI is present" rule as the rest of the AppImage
defaults instead of being permanently off. Separately, `caddy` was
removed from the whole setup per explicit request: its option/appSet
entry/doc-comment in `modules/suites/dev-tools.nix`, its `caddy = true;`
in `priv.nix`, its pacman spec in `dev-tools.cachyos-packages.nix`, and
the now-empty `dev-tools.debian-packages.nix` file (caddy was its only
entry) were all deleted.
**Validated:** `nix flake check` passed; a full `activationPackage`
build passed under the real `work` context (this machine); and, since
`work` context wouldn't otherwise exercise the priv-only `tolaria`/
`quarto` paths, a **simulated `priv` + GUI-enabled** synthetic
`dots-local` (`context = "priv"; enableGuiDefaults = true;
graphicalBackend = "wayland";`) was built and `nix eval`-checked to
confirm `suites.dtp-tools.quarto`, `suites.pim-apps.taskwarrior`, and
`features.appimages.apps.tolaria.enable` all resolve `true` under that
scenario.

### 2026-07-20 — New `features.vk`: terminal-first wiki/Zettelkasten engine
**Decision:** Added a new `modules/features/vk.nix` + `modules/features/vk/`
subdir implementing `vk`, a `gum`-driven TUI wrapper around `helix`,
`quarto`, and `dufs` for managing local Markdown Zettelkasten "vaults"
under `$HOME/Vaults/<name>/` (per-vault `permanent/`/`literature/`/
`daily/` note trees, Quarto-rendered to a git-ignored `_site/`, with an
AST-based `wikilinks.lua` Pandoc filter resolving `[[wikilink]]` syntax
to real `.html` links, including cross-vault relative links). Follows
the same "small Nix preamble resolves package paths into shell
variables + one big static, shellcheck-able `.sh` file" pattern as
`viewer.nix`/`clipboard.nix`, rather than embedding the whole script as
a Nix string. The shared Lua filter lives once at `modules/features/vk/
wikilinks.lua` and is copied verbatim into every new vault by `vk new`
(not regenerated per-vault from a heredoc), so every vault always gets
the exact same, already-tested filter.
`gum`/`helix` were already core packages (`modules/core/default.nix`);
added `dufs` there too (zero-config static HTTP server, used by `vk
watch`/`vk serve-all`) since it's a genuinely general-purpose core
utility, not `vk`-specific config. `quarto`/`git` are pulled in directly
by `features.vk`'s own `home.packages` so `vk` works regardless of which
suites/contexts happen to be enabled (`quarto` already has its own
nixpkgs-quarto-pin override in `flake.nix`, reused automatically here).
Imported `../features/vk.nix` universally in `modules/contexts/
common.nix`, **disabled by default** (`coreLib.mkDefaultDisabledOption`)
- this is a new, personal-choice, vault-managing tool (not a baseline
utility like `features.viewer`), so it should be opt-in per
context/host rather than pulled in unconditionally.
`vk`'s `watch`/`build`/`serve-all` subcommands accept `-p`/`--port` and
`-b`/`--bind` (alias `--host`), both also as `--flag=value`, in any
order relative to the optional vault-name argument - parsed by a small
`parse_serve_flags`/`build_dufs_args` helper pair in `vk.sh` that passes
them straight through to `dufs`'s own `-p/--port`/`-b/--bind` flags,
falling back to dufs' own defaults (`0.0.0.0:5000`) when unset rather
than hardcoding an address/port in the script.
**Gotcha (fixed during implementation):** the original spec's shell used
several bare `[ -z "$X" ] && exit 1` / `[ -n "$Y" ] && ARR+=(...)`
statements under `set -e` - when the test is *false* (the common/success
path), `&&` short-circuits and the whole statement's exit status is 1,
which under `set -e` aborts the entire script even though nothing was
actually wrong. Rewrote every such guard as an explicit `if ...; then
...; fi` block instead of relying on `&&` short-circuiting as a
"one-line if" - this class of bug is easy to miss since it only
manifests on the *non-error* branch (e.g. `vk watch` immediately exiting
0-but-silently, or 1-with-no-message, whenever `--bind` was left unset).
**Validated:** `nix flake check` and a full `activationPackage` build
pass (feature disabled, its default). Also temporarily flipped the
default to enabled, rebuilt, confirmed the `vk` wrapper derivation
builds and its `--help`/unknown-command paths behave correctly, and ran
`vk.sh` standalone (stubbed `gum`/`quarto`/`dufs`/`git`/`hx` binaries via
env-var overrides) to confirm `new` scaffolds a vault correctly and
`watch`/`serve-all`'s `--port`/`--bind` flag parsing (both orders, both
`--flag value` and `--flag=value` forms, and the fallback defaults)
all produce the expected `dufs` argv and printed URL, before reverting
the default back to disabled.

### 2026-07-20 — Fix: `pkgs.taskwarrior` renamed/thrown; use `pkgs.taskwarrior2`
**Decision:** nixpkgs converted `taskwarrior` to a `throw` alias
("'taskwarrior' has been renamed to/replaced by 'taskwarrior2'",
2025-10-27) on a revision the `pheno` (Debian) machine's `dots-local`
had already picked up, breaking `suites.pim-apps`'s `appSet` entry which
still referenced `pkgs.taskwarrior` directly. Switched to
`pkgs.taskwarrior2` in `modules/suites/pim-apps.nix` - confirmed via
`nix eval` that `taskwarrior2`'s own `pname`/`version` are still
`"taskwarrior"`/`2.6.2` (i.e. it's the same Taskwarrior 2.x, just
renamed at the nixpkgs-attribute level - not a new major version).
Deliberately did NOT switch to `taskwarrior3` (nixpkgs' newer 3.x
rewrite, different on-disk data format) since `tasksh` 1.2.0 (also in
this suite) targets the 2.x task API/data format.
**Validated:** `nix flake check` and a full `activationPackage` build
both succeed on this (CachyOS) machine after the fix; the same
`pkgs.taskwarrior` throw was reproduced locally by evaluating
`nixpkgs#taskwarrior.pname` directly, confirming this wasn't a
Debian-machine-specific nixpkgs-pin quirk - any machine tracking a
recent-enough nixpkgs revision would hit the same failure.

### 2026-07-20 — Correction: use `pkgs.taskwarrior3`, not `taskwarrior2`
**Decision:** The previous entry's choice of `taskwarrior2` was wrong for
the user's actual intent - user wants the current Taskwarrior 3.x series
(TaskChampion/SQLite-backed), not the legacy 2.x line `taskwarrior2`
provides (confirmed via `nix eval`: `taskwarrior2.version` = `2.6.2`,
`taskwarrior3.version` = `3.4.2`). Switched `modules/suites/
pim-apps.nix`'s `appSet` entry to `pkgs.taskwarrior3`. `tasksh` only
talks to `task` via its CLI (not its on-disk storage format), so it
stays compatible with either series - no `tasksh` changes needed.
Arch's `task` pacman package (referenced in `modules/suites/
pim-apps.cachyos-packages.nix`) is *also* already on the 3.x series
(3.4.2-1 in the `extra` repo as of this writing), so no alien-spec
change was needed there - the existing `pacman = [ "task" ]` entry
already matches 3.x on this distro.
**Validated:** `nix flake check` and a full `activationPackage` build
both pass with `taskwarrior3`.

### 2026-07-20 — Fix: `update-alien-packages` perpetually re-offering `pandoc` on Arch/CachyOS
**Decision:** Arch renamed the `pandoc` pacman package to `pandoc-cli`
(the new package `Provides`/`Replaces` the old `pandoc` name, per
archlinux.org). `update-alien-packages`' missing-package detection
(`modules/core/alien-packages.nix`'s `update_packages`) compares literal
package names via `comm -23 <(required) <(pacman -Qq)` - it has no
concept of `Provides`, so as long as `modules/suites/dtp-
tools.cachyos-packages.nix` required the literal name `pandoc`, the diff
would see `pandoc` in the required list but never in `pacman -Qq`'s
output (which reports the real installed name, `pandoc-cli`) - so it was
never actually possible for this to resolve as "installed", no matter
how many times the user re-ran `update-alien-packages`. Confirmed on
this (CachyOS) machine: `pacman -Qq pandoc` and `pacman -Qq pandoc-cli`
both resolve to `pandoc-cli` (the actually-installed package), and
`which pandoc` -> `/usr/sbin/pandoc` confirms it really is installed,
just under the new package name.
**Fix:** Changed `modules/suites/dtp-tools.cachyos-packages.nix`'s
`pandoc` alien spec from `pacman = [ "pandoc" ];` to `pacman = [
"pandoc-cli" ];`. `modules/suites/dtp-tools.debian-packages.nix`'s
`apt = [ "pandoc" ];` is unaffected (Debian's package is still literally
named `pandoc`) - this was Arch-repo-specific.
**Validated:** `nix flake check` and a full `activationPackage` build
both pass; confirmed the generated `~/.local/share/dots/packages/
required/pacman.txt` now lists `pandoc-cli` (matching `pacman -Qq`'s
real output) instead of the never-matching `pandoc`.
**General lesson for future package-rename issues:** when
`update-alien-packages` perpetually re-offers a package that's
genuinely installed, suspect a `pacman`/`apt`/etc. package rename
(old-name -> new-name via `Provides`/`Replaces`) before assuming a bug
in the diff logic itself - the diff is a plain literal-name comparison
by design (see `get_installed_packages`/`update_packages` in
`modules/core/alien-packages.nix`), so any such rename silently breaks
detection until the alien spec is updated to the new literal name.

### 2026-07-20 — `features.vk` flipped to default-enabled
**Decision:** Reversed the earlier "disabled by default" choice for
`features.vk` - user confirmed (asked directly, since this contradicts
the original decision) they want it enabled for everyone by default,
not opt-in. Changed `modules/features/vk.nix`'s `enable` option from
`coreLib.mkDefaultDisabledOption` to `coreLib.mkDefaultEnabledOption`.
No other changes needed - it was already imported universally in
`modules/contexts/common.nix`, just off by default until now.
**Validated:** `nix flake check` and a full `activationPackage` build
both pass; the build now actually compiles the `vk` derivation (visible
in the build's derivation list) and wires it into `home-manager-path`,
confirming it lands on `$PATH` after `apply-dots` with no dots-local
changes required.

### 2026-07-20 — Fixed phantom-orphan bug in `update-alien-packages` (pandoc rename fallout)
**Problem:** After the `pandoc` -> `pandoc-cli` alien-spec rename (see prior
entry), `apply-dots`/`update-alien-packages` on the user's `pheno` machine
started reporting "To remove: pandoc" under pacman every run, even though
`pandoc` was never a real package name on that system (it's genuinely
`pandoc-cli`, installed and working). Manually running `pacman -R pandoc`
correctly failed with "target not found" - the entry was a phantom.
**Root cause:** `modules/core/alien-packages.nix`'s `update_packages`
persists a tracking file (`installed/<mgr>.txt`) that gets overwritten with
the *literal required-package-list contents* on every successful run, not
the actually-installed package names. When a required literal name changes
upstream (pandoc -> pandoc-cli), the *old* name lingers in that tracking
file from before the rename. The orphan computation only ever cross-checked
`previously_installed - get_all_required` (i.e. "no longer required by any
manager"), never against what's actually installed on the system - so a
phantom name that's simply been renamed away keeps reappearing as a
"remove this" candidate on every routine `update` run, forever, with no
self-correction. (`remove_packages`'s `--action remove` path *does* have a
`comm -12`-based self-healing filter against `actually_installed` at its
end, but that only runs when the user explicitly invokes `--action
remove` - not on the default `update` action most people run day-to-day.)
**Fix:** In `update_packages`, both the immediate `orphans` calculation and
the persisted `orphaned_file` reconciliation now additionally intersect
against `actually_installed` (via a second `comm -12` pass), matching the
same safety filter `remove_packages` already had. A package is now only
ever reported/tracked as an orphan if it is BOTH no-longer-required AND
genuinely present in the real system package list - phantom/renamed-away
names are filtered out automatically on the very next `update` run, with
no manual `--action remove` invocation needed.
**Validated:** `nix flake check` and a full `activationPackage` build both
pass with the updated `alien-packages.nix`.
**Interim guidance for the user's `pheno` machine:** running
`update-alien-packages --action remove --target pacman` once (answering
either y or n to the "Remove pandoc?" prompt is safe either way - the real
`pandoc-cli` package is untouched, only the nonexistent literal name
`pandoc` is targeted) will immediately clear the stale entry via the
existing `remove_packages` self-healing filter; after this fix lands via
the next `apply-dots`, routine `update` runs will no longer need that
manual step for future renames.

### 2026-07-21 — Added taskwarrior-tui + Taskwarrior/TaskChampion sync tooling
**Decision:** Added `taskwarrior-tui` as another opt-in `suites.pim-apps`
companion toggle (alongside `tasksh`/`timewarrior`/`lazytask`), defaulted
on in `modules/contexts/common.nix` alongside those three siblings. Added
a new universally-imported (`modules/contexts/common.nix`) feature,
`features.task-sync` (`modules/features/task-sync.nix`), providing:
- The `taskchampion-sync-server` binary, always on `$PATH` when the
  feature is enabled (default-on), mirroring `features.vk`'s "always
  available" precedent.
- An optional systemd `--user` service running that server locally
  (`dotsLocal.taskSync.autoSpawnServer`), auto-started via
  `WantedBy=default.target` (no shell-startup hook needed).
- An optional systemd `--user` timer running `task sync`
  (`dotsLocal.taskSync.syncInterval`, default `"never"` = no timer at
  all - manual sync only).
- A `home.activation` hook wiring `sync.server.url`/
  `sync.encryption_secret` into `~/.taskrc` via a filter-then-append
  model (strip any previously-written dots-managed block bracketed by
  marker comments, then re-append a fresh one) - deliberately never
  touches anything else in the file, and deliberately skips entirely if
  `~/.taskrc` doesn't exist yet (so it can never pre-empt Taskwarrior's
  own first-run auto-init of `data.location`/`news.version`).
New `dotsLocal.taskSync` schema fields (`modules/local/schema.nix`):
`autoSpawnServer` (bool), `interface`/`port` (server bind), `url`
(client override; null defaults to `http://127.0.0.1:<port>` when this
machine hosts its own server), `credential` (the actual
`sync.encryption_secret` - the only field that must be shared,
byte-identical, across every syncing device), `syncInterval`.
**Secret handling:** `credential` is stored in plaintext in dots-local's
`flake.nix` (same tradeoff as `butterfishApiKey` - no secrets-encryption
layer exists in this repo). Mitigations: `setup.sh` now `chmod 700`s a
freshly-created dots-local directory immediately, and
`modules/core/dots-local.nix` now re-asserts `chmod 700` on every
activation (`home.activation.protectDotsLocalPerms`) so the permission
isn't a one-time-only guarantee (e.g. survives a fresh `git clone` of
dots-local, which wouldn't otherwise preserve that bit). `setup.sh` also
pre-generates a random credential (`openssl rand -hex 32`, with an
`/dev/urandom`+`od` fallback) into the template's commented-out
`taskSync` example, so turning sync on later doesn't require inventing a
secure secret by hand.
**Updated:** `templates/local/flake.nix` (commented-out `taskSync`
example block + `@@TASK_SYNC_CREDENTIAL@@` token) and `setup.sh`'s
"Next steps" output, per the standing schema.nix/template-drift rule.
**This machine (lub):** enabled for real per explicit user choice -
`autoSpawnServer = true`, `interface = "127.0.0.1"` (loopback-only, not
yet exposed to other machines), `port = 8080`, `syncInterval = "never"`
(manual `task sync` only), with a freshly-generated real credential.
**Validated:** `nix flake check` + full `activationPackage` build both
pass. Ran `apply-dots` for real on lub: `taskchampion-sync-server.service`
came up active/enabled via systemd --user, `curl 127.0.0.1:8080` returns
200, `~/.taskrc`'s pre-existing `urgency.user.*` lines were preserved
untouched with the new sync block cleanly appended below them, re-running
the filter+append snippet standalone twice in isolation confirmed it's
idempotent (no duplicate blocks), and `dots-local` is now `chmod 700`.

### 2026-07-21 — Changed default taskSync port to 9999; hooked lazytask into task-sync config
**Decision:** `dotsLocal.taskSync.port`'s default changed from 8080 to
9999 (`modules/local/schema.nix`, `templates/local/flake.nix`'s example).
This machine (lub) and its running `taskchampion-sync-server` systemd
unit were updated to match via a real `apply-dots` run.
**lazytask hook:** Investigated `lazytask` v0.1.0 (the pinned version in
`pkgs/lazytask.nix`) to wire `dotsLocal.taskSync`'s server URL/credential
into it - found it has NO persistent sync-config mechanism at all: its
`src/config.rs` schema has no server/credential fields (only theme/
keybindings/taskwarrior{taskrc_path,data_location,sync_enabled}/ui), it
takes no relevant CLI flags/env vars (`src/main.rs` only accepts
`--config`/`--verbose`), and its own README explicitly states sync
settings are "held in memory only and not persisted across launches" -
entered by hand every session via the app's own Shift+S modal. Given
that, `modules/suites/pim-apps.nix` now wraps the `lazytask` binary (only
when `dotsLocal.taskSync` is actually configured, i.e. both a resolved
server URL and a credential exist) with a `writeShellScriptBin` launcher
that prints those two values to the terminal before `exec`-ing the real
binary, so the user has them ready to paste into the Shift+S modal
instead of having to look them up separately each session. This is a
best-effort convenience wrapper, not a real config-file/env wire-up -
revisit if/when lazytask itself adds persistent sync-config storage.
**Validated:** `nix flake check` + full `activationPackage` build pass;
confirmed via a real `apply-dots` run on lub that the systemd unit now
binds `127.0.0.1:9999` (server responds 200 there) and that `lazytask`
on `$PATH` now prints the correct URL/credential before launching.

### 2026-07-21 — Vendored a real env-var sync-config patch into lazytask
**Decision:** Superseded the "print info for manual copy-paste" lazytask
wrapper from the entry above with a genuine automatic wire-up, by
vendoring a small unified diff patch into the `lazytask` v0.1.0 source
itself (`pkgs/patches/lazytask-env-sync.patch`, applied via `patches =`
in `pkgs/lazytask.nix` - first use of a vendored source patch in this
repo, hence the new `pkgs/patches/` directory).
**Why a patch was necessary:** Confirmed via a full read of the real
upstream source (cloned directly, not guessed) that lazytask v0.1.0 has
zero persistent/automatic sync-config path: `TaskChampionIntegration::new`
hardcodes `sync_settings: None` on every startup regardless of
`config.toml`; `config.toml`'s `TaskwarriorConfig` fields are dead/
unused; the `LAZYTASK_REMOTE_SYNC_URL`/`_CLIENT_ID` env vars the user
spotted in the project's own test-running instructions are read only by
`tests/integration_remote_sync.rs`, compiled solely into `cargo test`,
never into the shipped binary. The only real code path that configures
sync is `TaskChampionIntegration::configure_sync(SyncSettings{..})`,
called exclusively from the interactive Shift+S modal.
**Patch content:** ~15 lines in `src/app.rs`'s `App::new()` - imports
`SyncSettings`, then if `LAZYTASK_SYNC_SERVER_URL`,
`LAZYTASK_SYNC_CLIENT_ID`, and `LAZYTASK_SYNC_ENCRYPTION_SECRET` are ALL
present, calls the same unmodified `configure_sync()` the modal itself
calls. Silently a no-op if any var is missing or if `configure_sync`
rejects the values (e.g. a non-UUID client id) - never panics, never
logs the secret.
**Wrapper update:** `modules/suites/pim-apps.nix`'s `lazytaskPkg` now
exports those three env vars for real before `exec`-ing the patched
binary, rather than just printing them. Since lazytask keeps its own
standalone TaskChampion replica (separate from Taskwarrior CLI's
`~/.task`), it needs its own device client-id distinct from
`sync.server.client_id` in `~/.taskrc` - the wrapper generates one via
`/proc/sys/kernel/random/uuid` on first run and persists it at
`~/.local/share/lazytask/client_id`, reusing it on subsequent launches
(a fresh UUID every run would break the server's per-device snapshot/
versioning). Caught and fixed a bug during testing: the client-id path
must NOT be run through `lib.escapeShellArg` at the Nix level, since that
produces a literal single-quoted `$HOME` that bash then never expands -
the `$HOME`-containing path is written directly into the heredoc instead
and left to expand at shell runtime.
**Validation method:** Cloned the real `v0.1.0` tag independently twice
(once to build the patch via `git diff`, once fresh to verify
`patch -p1` applies cleanly), then validated for real in this repo: (1)
`nix build` of the patched `lazytask` derivation compiles successfully,
(2) full `activationPackage` build and `nix flake check` both pass, (3)
a real `apply-dots` run on lub activates cleanly, (4) inspected the
generated wrapper script on `$PATH` and confirmed correct env var values
and runtime `$HOME` expansion, (5) ran the actual patched binary under a
pty (`script -qec "timeout 3 lazytask" ...`) and confirmed it starts
without panicking/erroring and persists a stable client-id file across
runs.

### 2026-07-21 — Fixed two real production bugs: `awk` missing from activation `$PATH`, and `sync.server.client_id` semantics

**Symptom reported by user:** after syncing tasks in lazytask, `task
sync` errored with "sync.server.client_id and sync.encryption_secret are
required", and once that was fixed, `task list` still showed zero tasks
even after a successful `task sync`.

**Bug 1 — `~/.taskrc` sync block duplicating on every `apply-dots` run.**
`modules/features/task-sync.nix`'s `hookTaskrcSync` activation script
uses a strip-then-append model (bare `awk` to delete any previously
written block, then unconditionally re-append a fresh one) specifically
so repeated activations stay idempotent. In practice it wasn't: the
block count climbed by one on every single `apply-dots` run (confirmed
by running it repeatedly and counting). Root cause: home-manager's
generated `activate` script sets its own minimal, hand-picked `$PATH`
(bash-interactive, coreutils, diffutils, findutils, gettext, gnugrep,
gnused, jq, ncurses, plus `nix-env`'s dir) that does **not** include
`awk` at all. The bare `awk` invocation silently failed
("command not found", exit 127) inside a `cmd > file && mv ...` chain,
leaving an empty 0-byte `.dots-tmp` file and short-circuiting the `mv` -
so the strip step was a complete no-op every activation while the append
kept running regardless. Confirmed by finding a stray empty
`~/.taskrc.dots-tmp` left on disk, and by the fact the identical script
logic worked perfectly when run manually in an interactive shell (which
has a normal `$PATH`).
**Fix:** reference `${pkgs.gawk}/bin/awk` (an absolute Nix store path)
instead of relying on bare `awk` resolving via `$PATH`. Verified by
running `apply-dots` twice in a row post-fix and confirming the block
count stays at exactly 1 both times, with no stray `.dots-tmp` file.
**General lesson:** any `home.activation.*` script needing an external
tool must reference its absolute Nix store path - activation scripts do
NOT inherit a normal interactive shell's `$PATH`.

**Bug 2 — `sync.server.client_id` misunderstood as a per-device identity.**
Both `task-sync.nix` (Taskwarrior CLI) and `pim-apps.nix` (lazytask)
each generated their OWN separate random UUID for "client_id", on the
(wrong) assumption it was a per-device/per-app identity akin to
`sync.encryption_secret`'s per-list secret. Per the real `task-sync(5)`
manpage, `client_id` actually identifies **the shared task list itself**
("a client ID identifying your tasks" - singular/possessive) - every
replica that should merge into one list (another machine's `task` CLI,
or a different app's own standalone TaskChampion replica on the SAME
machine, e.g. lazytask) must use the exact SAME client_id, exactly like
`credential`. Since `taskchampion-sync-server` doesn't set
`--allow-client-id` (so it silently accepts and auto-creates ANY
client_id), two different client_ids against the same server/secret
produced two entirely separate, non-merging task lists with no error at
all - explaining why `task sync` "succeeded" yet `task list` stayed
empty. Confirmed directly via
`sqlite3 ~/.local/share/taskchampion-sync-server/*.sqlite3 "select
client_id from clients;"`, which showed two unrelated client_ids (one
per app) each with their own real synced version history.
**Fix:** added `dotsLocal.taskSync.clientId` (nullOr str, default null)
to `modules/local/schema.nix`, treated exactly like `credential` -
generated ONCE (`setup.sh` now also generates a `TASK_SYNC_CLIENT_ID`
UUID alongside the existing credential, substituted into
`templates/local/flake.nix`'s commented-out example) and copied
unchanged to every dotsLocal that should share this task list.
`task-sync.nix`'s and `pim-apps.nix`'s per-app/per-machine runtime UUID
generation (`/proc/sys/kernel/random/uuid` + a persisted file) was
removed entirely in favor of directly interpolating the same
`ts.clientId` value in both places; `syncConfigured` in both files now
also requires `ts.clientId != null`.
**Validation:** full `activationPackage` build + real `apply-dots` run
on lub; confirmed `~/.taskrc`'s `sync.server.client_id` and lazytask's
generated wrapper's `LAZYTASK_SYNC_CLIENT_ID` are now byte-identical;
ran `task add` + `task sync`, confirmed `task list` shows the new task,
and confirmed via the server's sqlite `clients` table that the new
shared client_id has real synced version history. The old orphaned
per-app client_ids/task data from before this fix (created entirely
during this session's own smoke-testing, not real user data) are left
in place as harmless orphaned rows rather than actively cleaned up.

### 2026-07-21 — `suites.dev-tools.lua`/`luajit`, defaults driven by new `dotsLocal.lua`

Added Lua/LuaJIT to `suites.dev-tools`: `lua` (pkgs.lua5_4, `lua`/`luac`)
default-on, `luajit` (pkgs.luajit, `luajit`) default-off. Both defaults
come from a new `dotsLocal.lua = { enable; jit; }` schema field rather
than being hardcoded, so any machine can flip either one via its own
`dots-local/flake.nix` without touching this repo - mirrors how
`gpu`/`compositor`/`isWsl` drive other suite defaults via `rules.nix`,
just wired directly (dev-tools.nix takes `dotsLocal` as a module arg,
matching `task-sync.nix`/`pim-apps.nix`'s existing precedent) since
there's no conditional "when" here, just a straight default passthrough.

**Collision found and fixed:** nixpkgs' `luajit` derivation ships its
own `bin/lua` symlink (pointing at luajit itself) in addition to
`bin/luajit` - installing it alongside `pkgs.lua5_4` (which has its own
distinct `bin/lua`) would be a home-manager file collision the moment
both `lua` and `luajit` are enabled together. Fixed by wrapping
`pkgs.luajit` in a tiny `pkgs.runCommand` derivation that only
re-exposes `bin/luajit`, dropping the `bin/lua` symlink entirely - so
`lua` (when enabled) always and only resolves to the standard
interpreter, and `luajit` is always a separate, non-colliding command.
This also directly satisfies the "fallback when no luajit present"
requirement: nothing ever depends on luajit's own `bin/lua`, so `lua`
behaves identically whether or not `luajit` is enabled.

Updated `templates/local/flake.nix` with a commented-out `lua = {...}`
example at its literal defaults. This machine (lub) was left on
defaults (`lua.enable = true`, `lua.jit = false` - user's explicit
choice) - no dots-local edit needed since those already match.
**Validation:** full `activationPackage` build, standalone build of the
luajit-no-lua-symlink wrapper confirming only `bin/luajit` exists and
runs correctly, and a real `apply-dots` on lub confirming `lua` is on
PATH (5.4.7) and `luajit` is correctly absent (default off).

### 2026-07-21 — New `features.rescue-lua`: static-musl Lua/LuaJIT emergency toolkit (ported from a Gemini outline, with two forced deviations)

User supplied a Gemini-generated outline for a `rescue-lua` command:
`pkgsStatic.lua5_4`/`pkgsStatic.luajit`, both bundled with the same
`luafilesystem`/`luaposix`/`dkjson` libraries via `.withPackages`, a
wrapper switching engines on `-jit`/`--jit`, plus static `busybox`/`jq`
and direct top-level access to every raw binary. Implemented it, but
real build/collision testing forced two deviations from the outline:

1. **`.withPackages` is broken for `pkgsStatic` in current nixpkgs.**
   Confirmed by building `pkgsStatic.lua5_4.withPackages (ps: [
   ps.luafilesystem ])` in isolation: it fails during
   `luarocks_bootstrap`'s own `./configure` with "Unknown flag:
   --enable-static" - the static stdenv adapter unconditionally injects
   `--enable-static --disable-shared` into every autotools-style
   configure call, but luarocks' custom configure script doesn't
   recognize that flag. This is upstream, not fixable from this repo
   without a real nixpkgs/luarocks patch. Given user's explicit choice
   (asked directly rather than guessing), shipped WITHOUT bundled Lua
   libraries - bare `pkgsStatic.lua5_4`/`pkgsStatic.luajit` build and
   run fine on their own, just without `require("lfs")`/`dkjson`/etc.
2. **Raw static binaries are NOT installed directly, unlike the
   outline's "direct access to individual static binaries" section.**
   `pkgsStatic.lua5_4` and `pkgsStatic.luajit` both ship a `bin/lua`
   (luajit's is a self-symlink) - installing both raw would collide
   with each other AND with the ordinary dynamically-linked `lua` from
   `suites.dev-tools.lua` (on by default - see this file's earlier
   2026-07-21 dev-tools entry). `pkgsStatic.busybox` ships ~400 applet
   symlinks (ls/cat/grep/awk/sh/...) that would catastrophically
   collide with coreutils/findutils/gnugrep/gawk already installed
   everywhere; `pkgsStatic.jq`'s `bin/jq` would collide with the
   ordinary `pkgs.jq` already installed unconditionally in
   `modules/core/default.nix`. Fix: only install the `rescue-lua`
   wrapper (reaches both static interpreters via absolute store paths,
   no PATH involved) plus distinctly-renamed `rescue-busybox` (exposes
   busybox's own multi-call binary only - invoke applets as
   `rescue-busybox <applet> ...`) and `rescue-jq` wrappers.

New `features.rescue-lua` (default-enabled, imported in
`modules/contexts/common.nix`), with a `emergencyUtils` sub-toggle
(default-enabled) gating the busybox/jq wrappers separately from the
Lua wrapper itself. `rlua`/`rluajit` bash aliases added for
`rescue-lua`/`rescue-lua --jit`.
**Validation:** full `activationPackage` build (no collisions), a real
`apply-dots` on lub, then ran `rescue-lua -e 'print(_VERSION)'` (→ "Lua
5.4"), `rescue-lua --jit -e 'print(_VERSION)'` (→ "Lua 5.1"),
`rescue-busybox echo ...`, `rescue-jq -n '{"a":1}'`, and confirmed via
`bash -ic 'alias rlua; alias rluajit'` that both aliases register
correctly, all while `suites.dev-tools`'s ordinary `lua` stayed intact
on PATH with no collision.

### 2026-07-22 — `git` alien-managed on Azure Linux (tdnf/dnf5)

`suites.git-tools.nix` previously installed `git` purely via
`programs.git.enable = true`'s default package, with zero alien
awareness - unlike `lazygit`/`gh`/`gh-dash`/`gitCredentialManager`
(already routed through `mkAppSet`). Confirmed via `nix eval
.#homeConfigurations.default.options.programs.git.package.type.name` →
`nullOr` that `programs.git.package` is nullable (home-manager only adds
it to `home.packages` when non-null) - the same nullable-package
convention already relied on for lazygit/zellij (see this file's
2026-07-19 entry). `git` itself stays outside `mkAppSet`/`appSet`
(unlike the other tools in this file) since it needs real HM-level
config (`settings`/`signing`/`alias`) that a plain package toggle
doesn't support - so it's wired by hand:
`package = alien.mkEntry cfg.git "git" pkgs.git;` inside the existing
`programs.git` block, plus `"git"` added directly to
`alienPackages.enabledPackages` (not via `appSet.alienEnabled`, since
`git` was deliberately never added to `appSet.apps` - doing so would
have double-added the package through both `appSet.packages` and
`programs.git.package`).

Added new alien specs: `git-tools.azurelinux3-packages.nix` (`tdnf =
[ "git" ]`) and `git-tools.azurelinux4-packages.nix` (`dnf5 = [ "git"
]`) - no other distro (cachyos/opensuse/debian) was touched, since only
Azure Linux was asked about; git-tools.nix's alien-awareness fix is
generic and will pick up any future distro's spec automatically once
added.
**Validation:** full `activationPackage` build (via
`--override-input dots-local`), confirmed no alien-spec name conflict
and `"git"` present in `config.alienPackages.enabledPackages`.

### 2026-07-22 — `nixon`/`nixoff` left `~/.nix-profile/bin` on PATH after `nixoff` (two real bugs, fixed)

User reported `nixoff` didn't produce a genuinely clean host shell -
`~/.nix-profile/bin` (and other entries) stayed on `$PATH`. Root-caused
two independent, real bugs in `modules/core/nixon.nix`, both fixed,
`apply-dots`'d and verified live:

1. **NIXON=0 branch's PATH filter never actually matched
   `~/.nix-profile/bin`.** It used `grep -v "/nix"`, but
   `/home/<user>/.nix-profile/bin` has a `.` between the `/` and `nix`
   (`/.nix-profile`), so the literal substring `/nix` never matches -
   only real `/nix/store/...`/`/nix/var/...` paths did. Fixed by adding
   a second exclusion pattern for the substring `nix-profile` (`grep -v
   -e "/nix" -e "nix-profile"`).
2. **`.bashrc-dots` was being sourced twice per login shell**, silently
   accumulating duplicate PATH entries on every toggle. Home Manager's
   own generated `~/.bash_profile` (from `programs.bash.enable = true`
   in `flake.nix`) unconditionally sources BOTH `~/.profile` AND
   `~/.bashrc`; `~/.profile-dots` (reached via `~/.profile`'s
   dots-managed hook) already sources `~/.bashrc-dots` itself at its
   end, so for any login shell (`nixon`/`nixoff`'s `exec bash -l`
   included) `.bashrc-dots` ran once nested inside `.profile-dots` AND
   again directly via `.bashrc`'s own hook. Fixed with a same-process
   guard (`_DOTS_BASHRC_DOTS_SOURCED`, plain non-exported var, checked/
   set as the very first thing in `.bashrc-dots`) - the second
   invocation returns immediately.

Confirmed the pre-hook/post-hook capability the user also asked about
(freely adding lines to the real `~/.bashrc` before and after the
dots-managed sentinel, with post-hook code able to branch on `$NIXON`)
already works today with zero changes needed -
`home.activation.ensureDotsShellHook` only appends the sentinel line
once (guarded by grepping for it) and never touches surrounding content,
so anything the user adds around it persists across every `apply-dots`.

**Validation:** full `activationPackage` build + real `apply-dots` on
lub. Direct testing (see `learnings.md`'s matching 2026-07-22 entry for
why *naive* nested `bash -lc "..."` string tests are unreliable here)
via standalone script files chaining real `exec bash -l` calls confirmed
clean `$PATH` (no `nix-profile`, no duplicates) after both a bare
`nixoff` and a `nixon` → `nixoff` cycle, while a bare `nixon` still
correctly shows `~/.nix-profile/bin` on PATH.

### 2026-07-22 — New `nix-daemon` shell function (manual per-user Nix profile re-activation)

Follow-up to the `nixoff` PATH-leak fix above: user wants a way to
manually re-run the system Nix installer's own `nix-daemon.sh` (sets
`$HOME/.nix-profile/bin`, `/nix/var/nix/profiles/default/bin`,
`NIX_PROFILES`, `XDG_DATA_DIRS`, `NIX_SSL_CERT_FILE`) from inside a
`nixoff` shell, without a full `nixon`. Added a `nix-daemon` bash
function to `.bashrc-dots` (unconditional, not gated on `$NIXON` -
user explicitly said it's fine for it to also be available in
`nixon`, where it's a harmless no-op-ish re-run of what `/etc/profile`
already did at shell start). Implementation:
`unset __ETC_PROFILE_NIX_SOURCED` then `. /nix/var/nix/profiles/
default/etc/profile.d/nix-daemon.sh` - the `unset` is required because
`nix-daemon.sh` guards itself against being sourced twice per shell via
that exact variable, which `/etc/profile` already set at login-shell
startup (every login shell, `nixoff` included - see the PATH-leak fix
entry above), so without clearing it first `nix-daemon.sh` would return
immediately as a silent no-op.
**Validation:** full `activationPackage` build + real `apply-dots` on
lub; ran `nix-daemon` inside a real `NIXON=0` shell (via a standalone
script, same reliable-testing approach as the PATH-leak fix above) and
confirmed `~/.nix-profile/bin` and `NIX_PROFILES` etc. came back on
PATH/env afterward, with nothing else in the shell disturbed (it's a
plain `source`, not `exec`).

## 2026-07-22: `nixon` mode duplicates `~/.nix-profile/bin` in `$PATH` - root cause and fix

**Problem:** even a single fresh `NIXON=1` login shell (no toggling
required at all) showed `~/.nix-profile/bin` listed twice in `$PATH`,
plus `~/.local/bin` twice (the latter a known, separate, upstream
Home Manager quirk already logged below - not this bug).

**Root cause:** `.bashrc-nix` (pure Home Manager output, produced by
the gutter eval, not something this repo authors) contains, back to
back:
```
. "/nix/store/.../nix-2.34.8/etc/profile.d/nix.sh"          # unguarded
. "/home/sp/.nix-profile/etc/profile.d/hm-session-vars.sh"  # guarded by __HM_SESS_VARS_SOURCED
```
`nix.sh` itself has no re-entry guard and unconditionally prepends
`$NIX_LINK/bin` (`~/.nix-profile/bin`) to `$PATH`. `hm-session-vars.sh`
*also* sources that same `nix.sh` internally, the first time it runs.
So the very first time `.bashrc-nix` is sourced in a process, `nix.sh`
gets sourced twice in immediate succession - once directly, once via
`hm-session-vars.sh` - each unconditionally prepending
`~/.nix-profile/bin`. This is baked into the Home Manager-generated
file itself; nothing in this repo controls its content, so it can't be
"fixed" at the source.

**Fix:** in `.bashrc-dots`'s `NIXON=1` branch (`modules/core/
nixon.nix`), right after `. ~/.bashrc-nix`, dedup `$PATH` in place
(first-occurrence-wins, order-preserving):
```sh
PATH=$(printf '%s' "$PATH" | awk -v RS=: '!seen[$0]++ { printf "%s%s", sep, $0; sep=":" }')
export PATH
```
This is a downstream cleanup, not a guard - deliberately chosen over
trying to prevent the double-source (which would mean patching Home
Manager's own generated file). As a side effect it also cleans up the
long-standing `~/.local/bin` double-entry from `hm-session-vars.sh`'s
own hardcoded-plus-`$HOME`-expanded PATH line, so that pre-existing
quirk is now fully resolved too, at no extra cost.

**Validation:** full `activationPackage` build + real `apply-dots` on
`lub`. Verified via standalone-script-chained fresh login shells
(`env -i HOME=... USER=... bash -l ...`, never nested `bash -lc`
strings - see the testing-pitfall entry in `learnings.md`) covering:
a bare fresh `NIXON=1` shell, a bare fresh default-`NIXON` shell, and
a `nixon` → `nixon` → `nixoff` toggle chain. In every case
`~/.nix-profile/bin` and `~/.local/bin` now appear at most once, and
`nixoff` still fully strips all `/nix`-related paths as before.

## 2026-07-22: `nixon`/`nixoff` re-exec into a genuinely empty environment (`exec -c`)

**Problem:** `nixoff` never actually produced a clean host environment -
only a PATH that *looked* clean. Root cause: the old
`alias nixoff='NIXON=0 exec bash -l'` used `exec`, which replaces the
running program but does **not** clear its environment - every var the
old shell had exported (`NIX_PROFILES`, `XDG_DATA_DIRS`,
`NIX_SSL_CERT_FILE`, `MANPATH`, `FONTCONFIG_FILE`, `RUSTC_WRAPPER`,
`FZF_DEFAULT_*`, `XCURSOR_PATH`, plus the internal re-entry guards
`__HM_SESS_VARS_SOURCED`/`__ETC_PROFILE_NIX_SOURCED`) just carried
straight through. Worse, those surviving guards meant a later `nixon`
(after a `nixoff`) could silently fail to restore the nix env at all -
confirmed live: a `nixon → nixoff → nixon` chain ended with
`~/.nix-profile/bin` **missing** from `$PATH` entirely, because the
still-set `__HM_SESS_VARS_SOURCED` guard tricked `hm-session-vars.sh`
into thinking it had already run.

**Fix:** `nixon`/`nixoff` are now bash functions (`_nixon_toggle`,
`modules/core/nixon.nix`) that re-exec via bash's `exec -c` builtin -
run the given command with a genuinely EMPTY environment - instead of
plain `exec`. Since `-c` clears everything, they explicitly re-populate
just what's needed via `env VAR=val ...`: `NIXON=<target>` plus whatever
is currently set from `dotsLocal.nixonEnvAllowlist` (new schema field,
`modules/local/schema.nix`, sensible built-in default covering
TERM/HOME/USER/SHELL/LANG/DISPLAY/WAYLAND_DISPLAY/XDG_*/SSH_*/WSL
interop vars/etc.) plus any extra names passed as arguments (e.g.
`nixon MY_TOKEN`) - per-invocation escape hatch beyond the default list.
Every toggle now rebuilds state from scratch via `/etc/profile` +
`.profile-dots`/`.bashrc-dots`, deterministically, with zero leftover
guards or nix vars.

Also, per explicit user instruction, removed the PATH-dedup pass added
earlier (previous entry above) - "that's hiding problems not fixing
them." The known upstream `.bashrc-nix` quirk (Home Manager's generated
file unconditionally re-sources `nix.sh` on its own line in addition to
`hm-session-vars.sh`, which - the first time it runs - also sources that
same `nix.sh` internally, giving `~/.nix-profile/bin`/`~/.local/bin` a
harmless double PATH-prepend within any single `NIXON=1` shell) is left
visible and documented in a comment rather than papered over; it's not
something this repo can fix since it lives in Home Manager's own
generated output, and it does not compound across `nixon`/`nixoff`
toggles (confirmed live: stays at exactly 2x, never accumulates further).

Also renamed `nix-daemon` → `source-nix-daemon`, and added two siblings
in the same style/shape: `source-profile-nix` (re-sources `~/.profile-
nix`) and `source-hm-session-vars` (re-sources `hm-session-vars.sh`
directly via the `~/.nix-profile` symlink path) - all three clear their
underlying script's own re-entry guard first to force a real re-run
instead of a silent no-op, for manually pulling in one specific piece of
the nix environment without a full `nixon`.

**Validation:** full `activationPackage` build + real `apply-dots` on
`lub`. Verified via a real pty-backed interactive shell (`script -qec
"bash -l" ... < commands.txt`, required since `.bashrc-nix`'s content is
gated on `[[ $- == *i* ]]` - a plain non-interactive `bash -l script.sh`
does not exercise it) running `nixon` → `nixoff` → `nixon`: `nixoff`
now shows a fully clean `$PATH` with `__HM_SESS_VARS_SOURCED` unset; the
following `nixon` correctly restores `~/.nix-profile/bin` (previously
broken); `source-hm-session-vars` verified working standalone from a
`nixoff` shell.

## 2026-07-22: `nixon`/`nixoff` mode-token interface (`--`/`-`/`*`/`VAR`)

Extended `_nixon_toggle` (`modules/core/nixon.nix`) with an explicit
mode argument, parsed alongside any number of extra var names, in any
order:
- (no args) / `-` - clear the environment, then re-add
  `dotsLocal.nixonEnvAllowlist` (the default set). This is the default
  behavior with no arguments at all.
- `--` - clear the environment fully, no defaults added.
- `*` - keep the current environment as-is (plain `exec`, no `-c` -
  the pre-2026-07-22 behavior).
- `VAR` - preserve this variable's current value no matter what mode
  was otherwise specified, even under `--` (e.g. `nixon -- MY_TOKEN`).

Implementation parses `"$@"` in a loop, classifying each arg as a mode
token (`--`/`-`/`*`) or an extra var name; `*` short-circuits to a plain
`exec bash -l` (keeping the whole environment, no `env`/`-c` involved);
`--`/`-` build an `env VAR=val ...` assignment list (empty allowlist for
`--`, `dotsLocal.nixonEnvAllowlist` for `-`) plus any extra var names,
then `exec -c env "${assigns[@]}" bash -l`.

**Validation:** full `activationPackage` build + real `apply-dots` on
`lub`, verified via pty-backed interactive shell (`script -qec "bash
-l"` + piped commands - see the interactive-testing learning above)
covering all four forms: `nixoff --` (HOME itself ends up unset -
confirms genuinely empty env), `nixon -- MYTOKEN` (only `MYTOKEN`
survives, not `TERM`/other defaults), `nixon *` (verbatim carry-over of
whatever was already set, including a previously-broken `HOME`, since
it deliberately does no rebuild), and plain `nixon`/`nixoff`/`nixon -`
(same clean-scrub/restore behavior as before, confirmed unaffected by
the refactor).

## 2026-07-22: `nixon`/`nixoff` final CLI - `--help`, `VAR=value`, command passthrough, `+` instead of `*`

Finalized the `_nixon_toggle` (`modules/core/nixon.nix`) argument
grammar to:

```
nixon|nixoff [VAR|VAR=value ...] [-|--|+] [COMMAND [ARG...]]
```

- Variable specs come first, in `env`-style syntax: a bare `VAR`
  preserves its current value (unchanged from the mode-token round);
  `VAR=value` sets it to an explicit value instead, working "just like
  `env VAR=value ...`" per the user's request. Explicit assigns are
  appended after the allowlist-derived assigns in the final `assigns`
  array, so they always win for the same name (relies on `env`'s
  keep-the-last-duplicate semantics).
- An optional mode token follows the var-spec list: `-` (default),
  `--`, or `+` (keep-current-env, was `*` in the previous round -
  **changed to `+` because `*` is a shell glob and gets expanded by
  the calling shell unless quoted**; `+` needs no quoting and isn't a
  glob character).
- An optional `COMMAND [ARG...]` follows the mode token (or follows the
  last var spec, if no mode token is given at all). If present, it's
  run via `bash -l -c '"$@"' _ "${cmd[@]}"` (or plain `bash -l -c
  '"$@"' _ "${cmd[@]}"` without `env`/`-c` under `+` mode) instead of
  dropping into an interactive shell. `-l` is kept even in `-c` form,
  so the full `.profile-dots`/`.bashrc-dots` chain still runs before
  the command executes.
- **Important grammar consequence (by design, matches the user's
  literal spec that COMMAND comes "AFTER" the mode token): a bare
  command with no preceding mode token is NOT distinguishable from a
  list of bare `VAR` names to preserve** (both are just bareword
  identifiers) - e.g. `nixon echo hi` is parsed as "preserve vars named
  `echo` and `hi`", not "run `echo hi`". To run a command you must
  always include an explicit mode token first, e.g. `nixon -- echo
  hi` or `nixon + echo hi`. This was verified interactively and is
  intentional, not a bug.
- Added `_nixon_help` (triggered by `--help`/`-h`, checked during the
  var-scanning loop so it works regardless of position among var
  specs) printing the full grammar, semantics of each mode token, and
  worked examples. It's static/generic text (not parameterized per
  `nixon` vs `nixoff`), a deliberate simplification.

**Validation:** full `activationPackage` build + real `apply-dots` on
`lub`; pty-backed tests (`script -qec "bash -l"`, per the
interactive-testing learning) covering `nixon --help`/`nixoff --help`
output, `nixon FOO=barval` (explicit assign visible in the new shell),
`+` mode with an unquoted trailing command (`nixon + echo ... KEEPME=$KEEPME`
- confirmed no glob-expansion issue, unlike the initial `*` design
which got expanded to filenames by the calling shell when unquoted),
and the bare-var-vs-command ambiguity above (confirmed intentional
per-spec behavior, not a regression).

## 2026-07-22: nixon/nixoff redesign - deterministic "as-if-fresh-login-shell" model

**Context:** the previous `exec -c` + allowlist design (see prior entry)
produced a PATH that only *looked* clean - `nixoff` still leaked
`/nix/var/nix/profiles/default/bin`/`~/.nix-profile/bin`, and a deeper
investigation revealed the actual, sole root cause: **the Determinate
Nix installer had dropped an unconditional, unguarded-by-NIXON "Nix"/
"End Nix" block sourcing `nix-daemon.sh` in BOTH
`/etc/profile.d/nix.sh` (system-wide, sourced by `/etc/profile` for
every login shell) AND directly at the top of `/etc/bash.bashrc`
(system-wide, sourced by `/etc/profile`'s own `test -r /etc/bash.bashrc`
line for every INTERACTIVE shell, login or not)**. Both had to be found
and manually disabled (`sed -i '/^# Nix$/,/^# End Nix$/d' /etc/bash.bashrc`
plus renaming `/etc/profile.d/nix.sh` to a non-`.sh` extension) before
`nixoff` could ever be genuinely nix-free - no amount of
`.bashrc-dots`-level scrubbing could have fixed this, since both files
run before `.profile-dots`/`.bashrc-dots` even get a chance to. This is
an out-of-repo, system-level, host-specific fix (not encoded in `dots`
itself) - if `nix upgrade`/installer repair ever recreates either file,
this needs to be redone.

**Confirmed final target design** (superseding the prior allowlist-only
`exec -c` design): `nixon`/`nixoff` should always produce the SAME
result by default - "as if" a brand-new login shell had started with
`$NIXON` already at 1 or 0 - plus dotsLocal/module-registered preserve
vars, plus whatever the caller explicitly asked to carry over. Session/
socket-var leakage (`DISPLAY`, `SSH_AUTH_SOCK`, etc.) surviving via the
allowlist is fine and expected; the hard requirement is no *nix*-specific
leftovers.

- `--`: `exec -c` (genuinely empty env) + only explicit CLI
  `VAR`/`VAR=value` specs.
- `-` (default): `exec -c` + `dotsLocal.nixonEnvAllowlist` + new
  `options.core.nixonPreserveVars` (module-level, mergeable list,
  declared in `modules/core/nixon.nix` itself, following the
  `options.core.*` convention from `modules/core/platform.nix`) +
  explicit CLI specs.
- `+`: plain `exec` (keep everything) + explicit CLI specs layered on
  top.
- Every preserved/explicit var is now handed off via BOTH the real name
  directly (`NAME=value`, so it's genuinely correct from the very start
  of the re-exec'd shell) AND a `_PRESERVE_<NAME>` shadow var (restored
  at the very end of `.bashrc-dots`, after nix-loading, as a final-say
  safety net). The direct form was necessary once we noticed
  `nix-daemon.sh`/`nix.sh` compute `$HOME/.nix-profile` during
  `/etc/profile`/`/etc/bash.bashrc`, i.e. BEFORE `.bashrc-dots`'s own
  shadow-restore step would have run - shadow-only handoff produced a
  broken `/.nix-profile/bin` (empty-`$HOME`-prefixed) PATH entry and an
  empty `NIX_PROFILES`, since the store `nix.sh` requires non-empty
  `$HOME`/`$USER` to do anything at all and has no re-entry guard var of
  its own to signal a skipped run.
- The `/nix/var/nix/profiles/default/bin` PATH entry (needed for
  `nix`/`nh`/`home-manager` themselves, which aren't part of the HM
  profile) moved from unconditional to inside the `NIXON=1` branch only.
- The old `grep -v -e "/nix" -e "nix-profile"` PATH-stripping block in
  the `NIXON=0` branch was removed entirely - no longer needed, since
  `-`/`--` modes now reach that branch with a genuinely empty
  environment to begin with (`+` intentionally keeps whatever was there,
  matching its "retain everything" semantics).

**Validation:** full `activationPackage` build, `apply-dots` on `lub`,
pty-backed tests (`script -qec "bash -l"`) after disabling both system
files, covering: `nixoff` default (byte-identical to a genuinely fresh
`env -i HOME=... USER=... bash -l`'s PATH, confirmed), `nixon` default
(nix fully loaded, `NIX_PROFILES` correctly resolved with a real
`~/.nix-profile` path), a full `nixon`→`nixoff` round trip (clean →
loaded → clean again, no leftover state), `--`/`VAR` (only the named
var survives, `HOME` genuinely empty as intended), default `-`/
`VAR=value` (both allowlist defaults and the explicit assign present),
`+`/command-passthrough (`nixon + echo ...` runs and exits normally),
and `--help` text.

## 2026-07-22: setup.sh works with a --no-modify-profile Nix install

Follow-on to the nixon/nixoff redesign above. Added `install.sh` (a
2-line wrapper around the Determinate Systems installer with
`--no-modify-profile`) as the recommended way to install Nix on a new
machine, matching the "nixon/nixoff manages nix-loading itself" design -
no system profile.d/bashrc hooks are created at all with this install
mode (nothing to conflict with or duplicate what nixon/nixoff already
does).

This means a genuinely fresh terminal right after installing Nix this
way has `nix` nowhere on `PATH` - `setup.sh`'s own `nix run
home-manager -- switch ...` call would otherwise fail immediately with
"nix: command not found". Fixed by adding a small PATH-bootstrap
fallback near the top of `setup.sh` (after context-arg validation, before
`dots-local` template setup): if `command -v nix` fails, fall back to
prepending the well-known daemon-install location
(`/nix/var/nix/profiles/default/bin`) to `PATH` for the remainder of the
script's own run only; error out clearly if that binary doesn't exist
either (told to run `install.sh` first). This fallback is scoped to
`setup.sh`'s own process - it doesn't touch any shell rc file - since
`apply-dots`/`nixon` take over PATH management for every later shell
once the initial Home Manager switch has completed.

Confirmed system-wide Nix flakes/`nix-command` experimental features are
enabled unconditionally by the Determinate installer via
`/etc/nix/nix.conf`'s `extra-experimental-features` line regardless of
`--no-modify-profile`, so `nix run` itself works fine once `nix` is
found on `PATH` - no separate flakes-enablement fix was needed.

Added a short "Prerequisite" step to `README.md`'s Quick Start pointing
at `install.sh`, and a shebang + explanatory comment to `install.sh`
itself (previously a bare 2-line file with no `#!` line).

### 2026-07-22 — `vk.nix` was silently re-installing Nix's `git`, shadowing the Azure Linux alien fix

Follow-up to the same day's "`git` alien-managed on Azure Linux"
decision above. That fix made `suites.git-tools.nix`'s
`programs.git.package` correctly evaluate to `null` on Azure Linux
(confirmed via a throwaway `dots-local` override with
`distro = "azurelinux3"`) - but `git` still resolved to
`~/.nix-profile/bin/git` on a live Azure Linux host with `git` actually
installed via `tdnf`. Root cause: `modules/features/vk.nix` had its own,
completely independent `home.packages = [ vkScript pkgs.quarto pkgs.git
];` - a hardcoded `pkgs.git` with zero alien-awareness, unrelated to
`suites.git-tools`'s logic. Since `nix.sh` prepends `~/.nix-profile/bin`
ahead of `/usr/bin` on `$PATH`, this Nix-built `git` always won
regardless of `git-tools.nix`'s fix.

Dropped `pkgs.git` from `vk.nix`'s `home.packages` entirely (per user:
"drop from vk! This is our module, I always have git enabled so this
will work.") - `suites.git-tools.git` is default-on and already the
single source of truth for `git`'s alien-awareness, so `vk` doesn't need
its own copy. Left `GIT_BIN="${pkgs.git}/bin/git"` (the script's
internal absolute-store-path reference) untouched - that's a
self-contained Nix-build-time reference the `vk` script alone uses, not
a `$PATH`/`home.packages` entry, so it can't shadow anything.

**Validation:** full `activationPackage` build (via
`--override-input dots-local`), plus a targeted `nix eval` with a
throwaway `dots-local` override (`distro = "azurelinux3"`) confirming
zero `git-2.*`-named derivations remain in `home.packages`.

### 2026-07-22 — starship init could run before `~/.nix-profile/bin` was on PATH

`programs.bash.initExtra` (modules/core/default.nix) - which sets
`STARSHIP_CONFIG` and calls `eval "$(starship init bash)"` - is emitted
into the generated `.bashrc-nix` BEFORE Home Manager's own trailing
`nix.sh`/`hm-session-vars.sh` sourcing lines (confirmed live: `grep -n
"starship\|nix.sh" ~/.bashrc-nix` showed `eval "$(starship init bash)"`
at line 189, `. .../nix.sh` at line 194). Since `starship` (a
`home.packages` entry) only lives in `~/.nix-profile/bin`, and that
directory is normally only added to `$PATH` by `nix.sh` - itself only
guaranteed to have already run via `.profile-nix` in a LOGIN shell (see
this file's earlier nixon/nixoff entries) - any interactive NON-login
shell that reaches `.bashrc-nix` without `~/.nix-profile/bin` already on
`$PATH` from an inherited/prior source would silently fail to find
`starship` at the point `initExtra` calls it.

Fixed by prepending `$HOME/.nix-profile/bin` onto `$PATH` (idempotent,
guarded) at the very top of `initExtra`, before referencing `starship`
at all - `.bashrc-nix`'s own later `nix.sh`/`hm-session-vars.sh` lines
just re-add the same, already-present entry (matching the existing,
documented double-nix.sh-sourcing quirk).

**Validation:** full `activationPackage` build + `apply-dots`, then
`env -i HOME=... USER=... PATH=/usr/bin:/bin bash -i -c 'source
~/.bashrc-nix; command -v starship'` (simulating the exact failure
scenario - a bare, nix-free PATH) - `starship` now correctly resolves
to `~/.nix-profile/bin/starship`.

### 2026-07-22 — `setup.sh` now requires `<distro> <context>` (was `<context>` only, distro hardcoded)

`setup.sh` previously hardcoded `DISTRO="cachyos"` unconditionally,
regardless of which machine it was actually bootstrapping - every new
machine's `dots-local/flake.nix` got `distro = "cachyos"` baked in from
the template fill-in step no matter its real distro, silently wrong for
any non-CachyOS host (Azure Linux included) until manually corrected
after the fact.

Made `setup.sh` take two positional args - `./setup.sh <distro>
<context>` (was `./setup.sh <context>`) - validated against a
`VALID_DISTROS` list kept in sync with `modules/local/schema.nix`'s
`distro` option description (`cachyos opensuse azurelinux3 azurelinux4
debian`). `--list`/`-l`/`list` (with no further args) now prints both
available distros and contexts; missing either argument or an unknown
distro value prints usage + the valid list and exits 1, same pattern as
the existing context handling. Updated `README.md`'s Quick Start example
and troubleshooting note to the new two-arg form.

**Validation:** `bash -n setup.sh`, plus live runs of every argument
path (no args, `--list`, distro-only, invalid distro) confirming correct
usage/list/error output and exit codes.

### 2026-07-23 — `vk` category rename + subtype front-matter tagging

Renamed `vk`'s three top-level vault categories (per user request):
`daily` → `records`, `literature` → `materials`, `permanent` → `texts`.
Updated everywhere: vault scaffolding (`mkdir`, `index.md` welcome links -
now includes all three, previously `daily`/`records` had no welcome-page
link at all, an existing gap fixed in passing), `_quarto.yml` sidebar
sections/globs, and the `note` subcommand's category chooser.

Each category now also has a subtype, chosen right after the category in
`vk note` → "Create Note", and recorded as a plain `type: <subtype>`
front-matter field - deliberately NOT a subdirectory (`records`/
`materials`/`texts` each stay a flat list of files, per explicit
instruction: "Still present as flat list. Dont create sudirectories for
subtypes, just tag in front-matter."):
- `records`: note, event, observation
- `materials`: quote, topic, source, entity, project (topic/entity/
  project added in follow-up requests in the same session; "concept"
  renamed to "topic" per explicit follow-up)
- `texts`: article, guide, hub

`records` notes always get a full `date: YYYY-MM-DD HH:MM` timestamp in
the header (not just a date) - daily-log-style entries are
time-sensitive, per explicit instruction ("new pages always with time
stamp in header"). `materials`/`texts` keep the previous date-only
stamp.

**Validation:** `bash -n`, full `activationPackage` build, inspected the
final generated `vk` script content directly from the Nix store, and a
manual smoke test of the frontmatter-generation logic for both a
`records`/`event` note (confirmed timestamp) and a `materials`/`quote`
note (confirmed date-only) - both produced the expected `type`/`date`
front-matter shape.

### 2026-07-23 — `vk search` command (global + per-vault substring search)

User asked whether `vk` can already host all vaults at once, and whether
it can grow a global + per-vault substring search.

- **Hosting all vaults at once**: already existed via `vk serve-all` (one
  dufs instance rooted at `$VAULTS_DIR`, each vault's rendered `_site/`
  reachable at `/<vault>/_site/`) - no code change needed, just confirmed
  and explained to the user (each vault needs a `vk build` first so
  there's a `_site/` for dufs to serve).
- **Search**: previously only existed as "Fuzzy Search Text" buried in
  `vk note`'s interactive menu, and only ever scoped to the single vault
  already `cd_vault`'d into - no cross-vault option existed.
  - Factored the rg → gum filter → hx pipeline into a shared
    `search_content <root> <placeholder>` helper. Passing the search root
    straight through to `rg` (rather than `cd`-ing into it first) keeps
    the returned `path:line` targets valid for `hx` regardless of the
    caller's cwd - required for the global case, which runs before any
    `cd_vault`.
  - `vk note`'s "Fuzzy Search Text" now just calls `search_content "."`.
  - Added a new top-level `vk search [vault|all]` command: with no arg,
    prompts via gum for "All vaults" or a specific vault name; `all`/
    `--all` also selects the global scope explicitly. Global search runs
    against `$VAULTS_DIR` directly; per-vault search `cd_vault`s first
    then searches `.`, identical to the `note` submenu's behavior.
  - Added to `print_usage` and the top-level interactive hub menu.

**Validation:** `bash -n`, full `activationPackage` build + live
activation, and a manual rg smoke test confirming both root-scoping
modes (`rg ... $VAULTS_DIR` for global, `rg ... .` after cd for
per-vault) produce clean `path:line:content` output compatible with the
existing `cut -d: -f1/-f2` + `hx file:line` handling.

### 2026-07-23 — Migrated existing vault + fixed `gum filter --ansi` bug

Migrated the only existing live vault (`~/Vaults/az`) from the old
`permanent`/`literature`/`daily` layout to the new `texts`/`materials`/
`records` layout (via `git mv` inside the vault's own git repo, so
history/renames are preserved): `permanent` → `texts`, `literature` →
`materials`, `daily` → `records` (was empty, recreated fresh with an
`index.md` placeholder since git doesn't track empty dirs to `git mv`).
Regenerated `index.md` and `_quarto.yml` to the current template's
section names/order. Added `type: guide` front-matter to the two
pre-existing `texts` notes (Agentic Coding Tools, WAVE gitconfig) - they
predate the subtype scheme so had no `type:` field; "guide" was chosen
as the closest fit (practical how-to/reference notes) and can be
retagged later if a different subtype fits better. Committed inside the
vault's own repo, separate from the dots repo history.

While smoke-testing `vk search` against this migrated vault, found
`gum filter --ansi` is no longer a valid flag on the installed gum
0.17.0 (replaced by `--strip-ansi`/`--no-strip-ansi`, not-stripping by
default) - `search_content()`'s pipeline was erroring with "unknown
flag --ansi" on every invocation. Fixed by dropping the flag entirely
(rg's `--color=always` output already displays fine unstripped by
default). This bug predates this session's `search_content` refactor
(it was in the original inline "Fuzzy Search Text" block) but only
surfaced now because it was never exercised end-to-end with a real gum
binary before.

### 2026-07-23 — `vk rename` command

User asked whether renaming a vault by just renaming its directory is
sufficient. Answer: functionally yes - every call site (`get_vault`/
`cd_vault`/`watch`/`build`/`serve-all`) resolves a vault purely by its
directory name under `$VAULTS_DIR` at runtime; there's no separate
registry file to keep in sync. But `index.md`'s title
(`"Index // $VAULT_NAME"`) and `_quarto.yml`'s `website.title` are baked
in verbatim at `vk new` time and never re-derived afterwards, so a bare
`mv` leaves the rendered site/index cosmetically showing the old name.

Added `vk rename [old] [new]` (also in the interactive hub menu): moves
`$VAULTS_DIR/<old>` -> `$VAULTS_DIR/<new>` (a plain `mv`, so `.git`
history moves with it), then `sed`-patches the two baked-in title
strings in the new location, and commits the change inside the vault's
own git repo (if one exists) with an `--allow-empty` commit (covers the
case where only the two title strings changed and content diff is
otherwise a no-op, plus records the rename itself as a discrete git
event).

**Validation:** `bash -n`, full `activationPackage` build + live
activation, and a manual dry-run against a throwaway vault (`mv` +
`sed` + git commit) confirming both `index.md` and `_quarto.yml` end up
with the new name and the vault's own git log records the rename.

### 2026-07-23 — `vk` default port changed to 5050

Changed `parse_serve_flags`'s `PORT` default from empty (previously
relying on dufs' own built-in default, 0.0.0.0:5000) to `"5050"`, an
explicit vk-level default always passed to dufs via `--port`. `BIND`
stays empty/unset, still falling back to dufs' own bind default
(0.0.0.0). Updated `dufs_url()`'s fallback and `print_usage`'s text to
match. Affects `vk watch` and `vk serve-all` (both use
`parse_serve_flags`/`build_dufs_args`/`dufs_url`).

**Validation:** `bash -n`, full `activationPackage` build + live
activation, confirmed the generated script's `PORT="5050"` default and
`dufs_url()` fallback.

### 2026-07-23 — `vk serve-all` rewritten: clean `/` index + `/<vault>` URLs

Previous `serve-all` pointed dufs straight at `$VAULTS_DIR`, exposing
each vault's raw internals (`records`/`materials`/`texts`/`_site`/...)
at the root, with vaults only reachable at `/<vault>/_site/`.

Rewritten to stage a throwaway `mktemp -d` directory (cleaned up via
`trap ... EXIT`) containing:
- one symlink per vault that has a built `_site` (named after the
  vault itself, pointing straight at `<vault>/_site`) - so
  `/<vault-name>/` now serves that vault's rendered site directly, no
  `/_site` suffix needed;
- a generated `index.html` listing links to every built vault, so `/`
  is a clean index instead of a raw directory listing of vault
  internals.

Vaults with no `_site` yet (never `vk build`'t) are skipped from both
the symlinks and the index, and reported via a stderr warning
suggesting `vk build <vault>`.

`--allow-symlink` is now passed to dufs (in addition to `-A`), required
since the staged symlink targets live outside the staging directory
dufs is rooted at.

**Validation:** `bash -n`, full `activationPackage` build + live
activation, a standalone dry-run of the staging logic against fake
vault dirs (built + unbuilt), and a full live end-to-end test: rendered
the real `~/Vaults/az` vault with `quarto render`, ran `vk serve-all -p
5099` in the background, and confirmed via `curl` that `/` returns the
generated vault-index HTML and `/az/` serves the vault's actual
rendered `index.html` with no `_site` in the URL. Cleaned up the test
server and the vault's build artifacts afterward.

### 2026-07-23 — `wikilinks.lua` piped-link bug fix + markdown-driven `serve-all` index + `list_vaults()`

Found and fixed a real, previously-shipped bug in `wikilinks.lua`: the
plain `[[target]]` pattern was tried *before* the piped
`[[target|display]]` pattern. Lua's non-greedy `.-` still matches
through to the *first* trailing `]]` it can find, and since a plain
`[[target|display]]` link has no earlier `]]` to stop at, the plain
pattern always "won" first, swallowing the whole `target|display`
string as the link target (e.g. rendering `records/index.md|Records`
as literal link text instead of `Records`). Fixed by trying the piped
pattern first, falling back to plain only when it doesn't match.

Also, this session:
- Added `modules/features/vk/imprint.md` (a stub Imprint page, seeded
  once per vault and once into `$VAULTS_DIR` root - never overwritten
  afterward) and wired `IMPRINT_MD_SRC` into `vk.nix`'s preamble.
- `vk new`'s `index.md`/`_quarto.yml` templates now list
  materials/records/texts alphabetically (matching every other vk
  listing), and `_quarto.yml` gained a `page-footer` Imprint link.
  Quarto resolves an absolute-root link like `/imprint.html` relative
  to *each project's own root*, not a single global filesystem root -
  so every vault needs its own local `imprint.md` for this to work
  both standalone and nested under `serve-all`.
- Added `list_vaults()`: a real vault is any `$VAULTS_DIR` subdirectory
  owning its own `_quarto.yml`. Rewired `get_vault()` and `vk search`'s
  scope picker to use it, since `serve-all` now writes its own
  `_site`/`index.md`/`imprint.md`/`_quarto.yml` directly inside
  `$VAULTS_DIR`, which a naive `ls "$VAULTS_DIR"` glob would otherwise
  misidentify as vaults.
- `serve-all`'s root index is now generated from real Markdown
  (`$VAULTS_DIR/index.md`, rendered via `quarto render`) instead of
  hand-rolled HTML, so `/` gets the same cosmo theme/CSS/page-footer as
  every vault. Quarto's single-file render doesn't cascade to other
  top-level `.md` files in the same project, so `imprint.md` needed
  its own explicit `quarto render imprint.md` call.

**Validation:** `bash -n`, full `activationPackage` build + live
activation, live re-render of `~/Vaults/az` confirming clean link text
(`Materials`/`Records`/`Texts`) and correct `.html` hrefs, and a
throwaway-fake-vaults dry run (`_quarto.yml`-owning vs not) confirming
`list_vaults()`'s filtering.

### 2026-07-23 — Per-vault/root `assets/`, all-global-`.md` pages, `serve-all` watch loop

- `vk new` now creates a per-vault `assets/` directory, and both the
  per-vault and root `_quarto.yml` templates declare
  `resources: - assets/**` so quarto copies the whole directory into
  `_site` verbatim regardless of whether every file in it happens to
  be referenced from a page.
- Generalized `serve-all`'s "render imprint.md specially" into a
  `GLOBAL_PAGES` loop: every top-level `*.md` file in `$VAULTS_DIR`
  except `index.md` is discovered, rendered individually (quarto
  doesn't cascade renders across sibling top-level pages), and listed
  alphabetically under a new "## Pages" section of the generated root
  `index.md` (Imprint keeps its dedicated `page-footer` link too).
- Factored `serve-all`'s whole rebuild body out of the inline case
  into `serve_all_rebuild(quiet)`, called once verbosely at startup
  and then repeatedly (quietly, `|| true`-guarded) from a background
  `while true; do sleep 3; serve_all_rebuild 1; done &` loop, whose PID
  is killed via `trap ... EXIT` (mirroring `vk watch`'s existing
  `Q_PID` pattern) - so `serve-all` now picks up newly built vaults,
  new/edited global pages, and asset changes without needing a
  restart.

**Validation:** `bash -n`, full `activationPackage` build + live
activation, live `vk serve-all -p 5098` run confirming the root
`_quarto.yml`/`index.md` regenerate correctly and quarto renders
`index.md` cleanly; cleaned up test artifacts (test assets, test global
page) afterward.

### 2026-07-23 — Per-vault `main.md` as the live landing-page lead-in

Each vault now has its own `main.md`: free-form, hand-edited content
that's never regenerated once created. `ensure_main_md()` seeds it
(just the vault name as an `# h1`) whenever missing - called both from
`vk new` and from `cd_vault()` (so any pre-existing vault gets
backfilled the next time any vk command touches it, not just brand-new
ones). `index.md`'s template now opens with `{{< include main.md >}}`
instead of a hardcoded "Welcome to your Knowledge Base" header, so
edits to `main.md` show up on the landing page immediately on rebuild
with no need to touch `index.md` again - followed by the unchanged
one-link-per-category list (materials/records/texts).

**Validation:** `bash -n`, full `activationPackage` build + live
activation; manually backfilled `~/Vaults/az` (`main.md` + updated
`index.md`) and confirmed via `quarto render` that the rendered
`index.html` shows the included `# az` h1 with no "Welcome" text,
immediately followed by the Materials/Records/Texts links.

### 2026-07-23 — `serve-all` auto-builds/rebuilds on *any* change, per-category note listings, real `wikilinks.lua` multi-token fix

`serve-all`'s watch loop previously only re-rendered the root
index/global-pages and re-symlinked *already-built* vaults - it never
built a brand-new never-built vault, nor rebuilt a vault whose own
notes changed. Fixed:

- Added `vault_needs_build()`: true if a vault has no `_site` yet, or
  any source file (excluding `_site`/`.quarto`/`site_libs`/`.git`) is
  newer than its `_site` output.
- `serve_all_rebuild()` now loops over every real vault and (re)builds
  it via `quarto render` whenever `vault_needs_build()` says so, before
  recomputing BUILT/UNBUILT - so new/edited notes, brand-new vaults,
  and removed vaults are all picked up automatically on the next poll,
  with no manual `vk build` step. UNBUILT now only means "failed to
  build" (message text updated accordingly).

Also added real per-category note listings and fixed a second,
independent `wikilinks.lua` bug found while testing this:

- Each category's `index.md` (`materials`/`records`/`texts`) is now
  regenerated (via `regen_category_index()`) as an actual alphabetical
  listing of every note inside it - title from the note's own front
  matter (falling back to the filename) - instead of the empty file
  `vk new` used to touch into existence. Only rewrites when content
  actually differs (`cmp -s` first), so an unrelated poll never
  spuriously bumps the file's mtime and falsely triggers
  `vault_needs_build()` every 3 seconds. Wired into `cd_vault()` (every
  vk command touching a vault refreshes it) and into
  `serve_all_rebuild()`'s per-vault loop (which reaches vaults without
  going through `cd_vault()`).
- Dropped the "Index // " prefix from `index.md`'s title (now just the
  vault name); updated `vk rename`'s sed pattern to match.
- **Found and fixed a real, previously-shipped `wikilinks.lua` bug**:
  the filter matched against a single Pandoc `Str` AST node, but
  Pandoc's parser splits a `[[target|display]]` wikilink into several
  separate `Str`/`Space`/`SoftBreak` nodes whenever the target or
  display text contains a space (e.g. any note title with more than
  one word) - so the filter silently never fired for those, printing
  literal brackets. This only went unnoticed earlier because the
  session's only previously-rendered links (`Materials`/`Records`/
  `Texts`) happened to be single words. Rewrote the filter to operate
  on the whole `Inlines` run instead of one `Str` at a time: it
  flattens a run of plain `Str`/`Space`/`SoftBreak` inlines back into a
  string, scans it for `[[...]]` spans (splitting on the first `|` to
  separate target/display), resolves each into a real `pandoc.Link`,
  and reconstructs any surrounding plain text - correctly handling
  spaces and multiple/mixed piped+plain links within the same line.
  Any other inline type (`Emph`, `Code`, an actual `Link`, ...) breaks
  the accumulated run, so this still only recognizes wikilinks written
  as plain text, not nested inside other markup.

**Validation:** `bash -n`, full `activationPackage` build + live
activation. Live end-to-end test via `vk serve-all` on a throwaway
port: force-deleted `az`'s `_site` and created a brand-new
never-built vault, confirmed both auto-built on the next poll and both
appeared in the root index; edited `texts/index.md`'s generated
listing and confirmed real links (`Agentic Coding Tools`,
`WAVE gitconfig` - both multi-word titles) render as working `<a href>`
tags instead of literal `[[...]]` text; confirmed root `index.md`'s
title now reads just the vault name. Synced the same fixes into
`~/Vaults/az`'s own git repo. Cleaned up all test artifacts afterward.

### 2026-07-23 — Removed duplicate title headings on vault pages

Every generated page put a `title:` in its front matter (which quarto
renders as an `<h1 class="title">` in its own title-block header) *and*
a matching literal `# ...` heading at the start of the body - printing
the same title twice on every vault landing page, category page
(`materials`/`records`/`texts`), and the root Vaults index.

Removed the redundant body heading in all three places - front
matter's `title` is now the single source of the on-page heading:
- `regen_category_index()`: dropped the `# $title` line.
- `ensure_main_md()`: seeds an empty `main.md` instead of `# $name`
  (index.md's own front-matter title already covers this once
  included).
- `serve-all`'s generated root `index.md`: dropped `# All Vaults`.

**Validation:** `bash -n`, full `activationPackage` build + live
activation; live `vk build az` + `vk serve-all` on a throwaway port,
confirmed via rendered HTML that `index.html`, `materials/index.html`,
`texts/index.html`, and the root Vaults `index.html` each contain
exactly one `<h1 class="title">` and no duplicate. Backfilled
`~/Vaults/az/main.md` to empty. Cleaned up test artifacts afterward.

### 2026-07-24 — `vk import` feature (MarkItDown/uvx, clipboard, bibliography)

Added `vk import [vault]` - an interactive `gum choose` menu (mirroring
`vk note`'s pattern) offering 6 modes to pull external content into a
new note, in `modules/features/vk/vk.sh` + a small `modules/features/vk.nix`
preamble addition:

- **File**: `uvx markitdown <path>` (path via `gum file` picker) -
  converts the file to Markdown verbatim as the note body.
- **Code**: either reads a given file path (inferring the fenced-block
  language from its extension) or opens `gum write` for pasted/typed
  code with a manually-entered language tag; always wrapped in a
  fenced code block.
- **Clipboard**: reads the OS clipboard via a `CLIP_PASTE_CMD` bash
  array, backend-derived exactly like `features.clipboard`'s own
  `pasteCmdArray` (wayland/x11/wsl/macos) but computed independently in
  `vk.nix` from `config.core.platformBackend` directly - deliberately
  NOT gated on `features.clipboard.enable`, since that feature's paste
  logic only exists as bash functions in `programs.bash.initExtra`, not
  callable from vk's separate script process. Empty array (null
  backend, CLI-only host) errors clearly instead of failing to build.
  Always wraps pasted content in a fenced code block.
- **Bibentry**: `gum write` to paste a BibTeX entry; renders a
  human-readable citation line as "Authors. *Title*. Rest." (title
  italicized, remaining venue/volume/pages/year comma-joined) via a
  **hand-rolled field-by-field formatter** (`bib_field`/
  `format_bib_entry`, regex-extracting `author`/`title`/`year`/
  `journal`/`booktitle`/`publisher`/`volume`/`pages` from the raw
  entry) rather than pandoc's `--citeproc`+default CSL style - the
  default Chicago-author-date CSL quotes article titles and italicizes
  the *venue* instead, the opposite of what was wanted. `pandoc
  --citeproc` is kept only as a fallback for entries where no
  title/author could be parsed at all. Body always includes both the
  formatted line and the raw entry in a ` ```bibtex ` fenced block.
- **Link**: fetches raw HTML via `curl`, extracts `<meta>`
  og:title/og:description/og:site_name/author/article:published_time
  (falling back to a plain `<title>` tag, and trying both attribute
  orders) via `rg`-based regex (`extract_meta_tag`) - builds a
  metadata-only note (frontmatter + "## Metadata" bullets + link), no
  page body.
- **Page**: same metadata extraction as Link, plus `uvx markitdown
  <url>` appended as a "## Content" section - MarkItDown natively
  fetches and converts URLs directly, no separate content-fetch step
  needed.

Shared `write_note()`/`prompt_category_type()` helpers extracted from
`vk note`'s "Create Note" action (previously inlined there) so every
import mode reuses the same front-matter/category/subtype logic
instead of duplicating it.

**Dependency decisions** (both discussed with the user before
implementing):
- MarkItDown is deliberately NOT nix-packaged - nixpkgs'
  `python3Packages.markitdown` pulls a huge, currently-broken (in this
  session's pinned channel) dependency closure (pandas/pdfplumber/
  arrow-cpp, ~1.7GB). Required instead via `uvx markitdown ...` (a
  runtime `command -v uvx` check, `require_uvx()`), relying on
  `suites.dev-tools.uv` (already default-on) being on `$PATH` - uvx
  caches its own tool install after the first (~30s) run.
- `pkgs.pandoc` was added as its own explicit `home.packages` entry
  (not reached through quarto's bundled copy) - quarto's nixpkgs
  derivation doesn't expose a simple standalone pandoc binary path
  (confirmed by inspecting its store output), whereas `pkgs.pandoc` is
  nixpkgs' own stable, self-contained package.

**Validation:** `bash -n`; full `activationPackage` build + live
activation. Functionally verified live using a throwaway `$HOME`
(`/tmp/vktesthome`) and a PTY-driving Python harness (`gum`'s TUI
prompts refuse to run without a real `/dev/tty`, so plain piped stdin
doesn't work for testing them) - confirmed Code mode's file-path
extension-based language detection, Bibentry mode's formatted citation
+ raw fenced block (spot-checked via `quarto render` that the title
renders as real `<em>` italics in the output HTML), and `write_note`/
`prompt_category_type`'s shared refactor didn't change `vk note`'s own
behavior. Cleaned up all test artifacts (`/tmp/vktesthome`, rendered
HTML, PTY harness script) afterward.

### 2026-07-24 — `suites.dev-tools.uvxAliases` (easy uvx-backed shell aliases)

Added `suites.dev-tools.uvxAliases` (`attrsOf str`, `alias-name =
"package"`) - each entry generates a `programs.bash.shellAliases.<name>
= "uvx <package>"` alias, so wiring up a one-off `uvx <tool>` shell
alias no longer means hand-writing a `shellAliases.foo = "uvx bar";`
line. Defaults to `markitdown` and `trafilatura` (both requested
directly - MarkItDown already used non-interactively by `vk import`
via `uvx`, see that feature's own decisions.md entry; trafilatura is a
similar HTML/URL -> Markdown/plain-text extractor). More entries can be
added here (repo-wide) or via `dotsLocal.shell.shellAliases`
(single-machine).

**Validation:** full `activationPackage` build; built
`homeConfigurations.default.config.home.file.".bashrc".source`
directly and grepped it for both generated `alias -- markitdown='uvx
markitdown'` / `alias -- trafilatura='uvx trafilatura'` lines; live
activation + `bash -ic 'type markitdown; type trafilatura'` confirmed
both resolve correctly in a real interactive shell.

### 2026-07-24 — vk-managed Lua filters/shortcodes (`VK_FILTERS_SRC_DIR`/`VK_SHORTCODES_SRC_DIR`)

Generalized the previously-hardcoded `wikilinks.lua` wiring into a
two-tier system so vk itself owns, installs, and keeps every vault in
sync with a growing set of Quarto Lua filters/shortcode extensions,
using the taskwarrior integration sketch as the first worked example
beyond `wikilinks.lua`:

- **Plain whole-document AST filters** (transform the whole Pandoc AST,
  e.g. `wikilinks.lua`) live in `modules/features/vk/filters/*.lua`,
  copied to each vault's root, and referenced from that vault's
  `_quarto.yml`'s `format.html.filters:` list.
- **Shortcode extensions** (`{{< name args >}}` syntax, e.g. the new
  `taskwarrior` one) live in `modules/features/vk/shortcodes/<name>/`
  (each its own `_extension.yml` + implementation `.lua`), copied
  wholesale into the vault's `_extensions/<name>/` - Quarto
  auto-discovers these with zero `_quarto.yml` wiring needed.

`vk.nix` exposes the two directories wholesale as
`VK_FILTERS_SRC_DIR`/`VK_SHORTCODES_SRC_DIR` (replacing the old, single
`WIKILINKS_LUA_SRC` file reference), so dropping a new filter or
shortcode-extension directory into either location is automatically
picked up with no further `vk.nix`/`vk.sh` changes. `vk.sh` gained
`sync_vk_filters()` (diff-guarded copy of every filter/shortcode into a
vault, using the same `cmp -s` guard as `regen_category_index()` - a
plain unconditional `cp` would bump destination mtimes on every call
even when content is unchanged, causing `vault_needs_build()`'s
mtime-based check to spuriously rebuild forever from `serve-all`'s poll
loop) and `ensure_quarto_filters_yml()` (idempotently keeps a filter
listed under `_quarto.yml`'s `format.html.filters:`, a no-op if already
present). Both are called from `cd_vault()` (so any vk command
backfills an older vault) and from `serve_all_rebuild()`'s per-vault
loop (before the `vault_needs_build()` check), and from `vk new`'s
vault-creation path.

**Shortcodes are architecturally distinct from plain filters**: a bare
`filters:` entry in `_quarto.yml` does NOT enable `{{< name args >}}`
syntax - shortcodes must be packaged as a Quarto extension
(`_extension.yml` with `contributes.shortcodes: [file.lua]`) under
`_extensions/<name>/`; no `quarto add`/network call is needed, a
correctly-structured local directory is auto-discovered. A shortcode
function's signature is `function(args, kwargs, meta)`, where each
`args[i]` is `pandoc.Inlines` (parsed Markdown), not a plain string -
use `pandoc.utils.stringify()`.

**`taskwarrior.lua`** (`{{< task-table <task-filter-args> >}}`)
shells out to `task <args> export`, JSON-decodes via
`require("pandoc.json")`, and returns a raw HTML `<table>`
(`pandoc.RawBlock("html", ...)`) rather than a native `pandoc.Table`
built via `pandoc.read()` on a generated Markdown table string (Gemini's
original sketch) - the latter triggers a real Quarto-internal bug
(`filters/modules/jog.lua:173: Don't know how to traverse TableBody`,
its crossref-numbering walker choking on native Pandoc Table AST nodes
returned from a shortcode) that spams on every render, even though
output is still correct. Since every vk vault's `_quarto.yml` only ever
defines `format.html:`, building raw HTML directly sidesteps the bug
with no functional loss. `RawBlock` content is emitted verbatim/
unescaped, so all user-supplied text (task descriptions) is manually
HTML-escaped via a small `html_escape()` helper. JSON numbers decode as
Lua floats (`item.id` came back `1.0`) - reformatted via
`string.format("%d", ...)`. The `task` binary is a soft dependency
(`os.execute("command -v task ...")` check with a graceful fallback
message), matching the `uvx`/MarkItDown soft-dependency pattern - not
added to `home.packages` by `vk.nix` itself; `suites.pim-apps.taskwarrior`
(default-on, provides `pkgs.taskwarrior3`) is the intended real-world
source.

**Validation:** `bash -n`; full `activationPackage` build + live
activation. End-to-end verified via a PTY-driving Python harness
(`gum`'s TUI prompts need a real `/dev/tty`): `vk new` on a fresh vault
correctly installed `wikilinks.lua` at vault root, correctly
back-filled `_quarto.yml`'s formerly-empty `filters:` list via
`ensure_quarto_filters_yml()`, and correctly installed
`_extensions/taskwarrior/`; deleting both from an existing vault and
running any vk command that calls `cd_vault()` (e.g. `vk note`)
correctly re-backfilled them. Seeded real Taskwarrior data (including a
pipe-containing description) and `quarto render`'d a note with
`{{< task-table >}}` - clean render, no `jog.lua` errors, correct
integer IDs, correct date reformatting, correct pipe/HTML-escaping.
Cleaned up all scratch vaults/taskdata/PTY harness scripts afterward.

## 2026-07-25: `textinfer` CLI - in-repo Rust source, fetch/load split, tune registration

New CPU-only, in-process (never spawns a server) text summarize/
paraphrase/translate/title CLI, built on the `mistralrs` crate against
GGUF models (phi-4 default, Qwen2.5-7B-Instruct as the `--quick`
alternative). Source lives at `pkgs/textinfer/` (vendored first-party,
no upstream - unlike `pkgs/lazytask.nix`/`pkgs/quarkdown.nix` which
`fetchFromGitHub`, `pkgs/textinfer.nix` uses `src = ./textinfer;` and a
committed `Cargo.lock`), packaged as `external.textinfer` in
`flake.nix`'s `externalOverlay`, wired up by the always-enabled
`modules/features/ai-textinfer.nix`.

**Fetch/load split (the actual point of this session's redesign):**
loading a model by HF repo id (`GgufModelBuilder::new(repo_id, files)`)
triggers mistralrs' own internal hf-hub network/ETag-freshness checks on
*every* invocation - measured 30-90s of load time even with the model
already fully cached, and unpredictable (`HF_HUB_OFFLINE=1` alone made
this *slower*, 88s, not faster - do not rely on it). Fix: `textinfer`'s
normal inference path now resolves the GGUF file purely from the local
hf-hub cache layout via `hf_hub::Cache::from_env().model(repo_id).get(file)`
(a plain filesystem read, zero network calls - confirmed against
`hf-hub` 0.4.3's own source), then passes the resolved *local directory*
(not the repo id) to `GgufModelBuilder::new()` - passing a local path
makes mistralrs skip its internal hf-hub resolution entirely per its own
docs ("all remote access is bypassed if you give a path"). Measured load
time dropped to ~16-18s doing this. If the model isn't cached, inference
fails fast with `model '<name>' is not downloaded yet - run 'textinfer
--fetch --model <name>' first` instead of silently downloading.
Downloading is now exclusively a separate, explicit `textinfer --fetch`
action (network-only, via `hf_hub::api::sync::ApiBuilder::from_env()`),
fetching one model (`--model`) or every registry model (no args) - never
triggered automatically by `ai-textinfer.nix` or any other module.

**RUSTFLAGS via the package-tuning system, not hardcoded in the
derivation:** per the user's explicit preference (a feature-toggle-style
"always tuned" switch), `pkgs/textinfer.nix` sets no RUSTFLAGS itself.
Instead `flake.nix`'s `tunePackagesByContext` registers
`textinfer.enable = true` for both `priv` and `work` (always-on
regardless of context, unlike ripgrep/fd which are `priv`-only), and
`modules/features/ai-textinfer.tune-specs.nix` pins `mode = "fast"`
(`-C target-cpu=<march> -C opt-level=3 -C codegen-units=1`) - this exact
combination was measured against a real phi-4 summarize+title job and
cut generation time from ~141s to ~92.5s (~35%) on the same machine, so
"fast" (not the tune system's "default" mode, which omits
`codegen-units=1`) is a specifically-justified choice here, not a
generic pick. This required two small, reusable, already-committed
generalizations to the tune-support machinery (`modules/core/
tune-support.nix`'s `localTunedPackages`/`wrappedTunedPackages` and
`modules/flake/package-tuning.nix`'s global-scope overlay): both now
fall back to `pkgs.external.<name>`/`prev.external.<name>` when a plain
top-level `pkgs.<name>` doesn't exist, since `textinfer` (like
`lazytask`/`quarkdown`) lives under the `external.*` namespace. Gotcha
hit once during wiring: the global-scope tune overlay's output packages
land at the **top-level** name (`final.textinfer`, tuned), not
`final.external.textinfer` - `ai-textinfer.nix`'s `home.packages` must
use `pkgs.textinfer or pkgs.external.textinfer` (prefer the tuned
top-level entry, fall back to the untuned `external.*` one), not
`pkgs.external.textinfer` directly, or tuning silently never applies.

**Model storage is `$HOME`-relative** (`~/.local/share/textinfer/models`
by default, `~/.config/textinfer/models.json` for the registry,
overridable via `--models-dir`/`--models-config` or
`TEXTINFER_MODELS_DIR`/`TEXTINFER_MODELS_CONFIG`) - `/opt/ai` (used by
`modules/features/llama-cpp.nix`) is specific to the one machine running
llama.cpp with CUDA and must not be reused here.

**Validation:** full `nix build .#homeConfigurations.default.
activationPackage` (with `--override-input dots-local
"git+file://$HOME/dots-local"`) succeeds; confirmed via the built
derivation's `.drv` that `RUSTFLAGS` is exactly `-C target-cpu=native -C
opt-level=3 -C codegen-units=1`; `--help`, `--fetch` (correctly detects
an already-cached model with zero network calls), and a real end-to-end
summarize+title run against the cached phi-4 GGUF all verified manually
before Nix packaging. Home-manager activation itself (`nh home switch`/
`apply-dots`) was deliberately NOT run by the agent - that mutates the
user's live environment and is the user's own action to trigger.

## 2026-07-25: `textinfer` → `paratext`/`parat` rename + mistralrs → candle rewrite

**Rewrote the CLI's inference engine from `mistralrs` to raw `candle`**
(`candle-core`/`candle-nn`/`candle-transformers`) and renamed the
package `textinfer` → `paratext` (binary `textinfer` → `parat`).

**Why the engine rewrite:** `mistralrs-core` pulled in ~500 transitive
crates for features this tool never used - MCP/agentic tool-calling, web
search, image generation (`image`/`ravif`), audio (`symphonia`/
`rubato`/`hound`/`mistralrs-audio`), HTML scraping, a full async HTTP
server stack, and PagedAttention/continuous-batching. A GPU-via-
llama.cpp-bindings alternative was considered first and rejected: both
mistralrs and candle already expose a `cuda` Cargo feature directly (no
C++ FFI needed), and the repo's existing `modules/features/llama-cpp.nix`
is a disabled-by-default, single-machine ("chromaden"), non-Nix-sandbox
CUDA build producing static libs only - not something a Cargo `build.rs`
could reproducibly/portably link against. Raw candle was chosen over
"keep mistralrs + enable its cuda feature" specifically for the
dependency-bloat/build-time win, accepting the tradeoffs below.

**Architecture:** `model.rs` (new) detects the GGUF's own
`general.architecture` metadata key at load time and dispatches to the
matching `candle-transformers::models::quantized_{llama,qwen2,phi3}`
`ModelWeights` (verified via partial-range GGUF header fetches: phi-4 →
`phi3`, Qwen2.5-7B → `qwen2`, TinyLlama → `llama`) - no per-model `arch`
registry field needed. Chat-formatting is a small hardcoded per-arch
match (Zephyr-style for llama/TinyLlama, ChatML for qwen2, Phi3's own
`<|system|>`/`<|user|>` tags) rather than parsing the GGUF's
`tokenizer.chat_template` Jinja template - candle's own reference
examples use the same hardcoded-per-family approach, and none of the
three families needed anything more elaborate. EOS token id is read from
the GGUF's own `tokenizer.ggml.eos_token_id` metadata key when present
(authoritative per-checkpoint), falling back to a per-arch marker string
looked up in the tokenizer vocab otherwise. Sampling is deterministic
greedy (`Sampling::ArgMax`) - appropriate for a strict-JSON-contract
text-processing tool, not a chat assistant. `run_worker`/the
single-process dispatch path in `main.rs` dropped `tokio` entirely
(candle inference is synchronous) - this also shed the `tokio` dependency
outright, not just mistralrs.

**Tokenizer gap - the one real "not actually free" cost of dropping
mistralrs:** mistralrs parsed a GGUF's own embedded vocab; candle has no
equivalent, and none of this registry's GGUF-only repos
(`microsoft/phi-4-gguf`, `bartowski/Qwen2.5-7B-Instruct-GGUF`,
`TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF`) ship a `tokenizer.json`
themselves - verified via the HF API's file-listing endpoint. `registry.
rs`'s `ModelEntry` therefore gained a required `tokenizer_repo_id` field
(the original non-GGUF model repo, e.g. `microsoft/phi-4`), and
`--fetch` now downloads a companion `tokenizer.json` from it alongside
the GGUF file.

**Performance regression - known, not yet addressed:** end-to-end testing
against the `--tiny` TinyLlama model measured only ~0.5-1.6 tok/s even
with `RUSTFLAGS="-C target-cpu=native"` (the same flag the tune-specs
system applies in the real build) - varying `RAYON_NUM_THREADS` (1/2/4/
8/16) never got meaningfully faster. This is markedly slower than what
the mistralrs backend achieved for CPU quantized inference (candle-core's
stock quantized/k_quants matmul kernels are less optimized than either
llama.cpp/GGML's hand-tuned SIMD kernels or mistralrs-quant's own
kernels - a known, documented tradeoff of depending on candle-core's
quantized ops directly rather than a project that's invested in
CPU-kernel-level tuning on top of it). Not fixed in this pass - flagged
here so it isn't silently reintroduced/rediscovered from scratch; a
future pass could look at candle's `mkl`/`accelerate` BLAS backend
features, or reconsider this whole tradeoff if CPU throughput turns out
to matter more than the dependency/build-time win.

**Rename scope:** `pkgs/textinfer/` → `pkgs/paratext/` (`Cargo.toml`
`name = "paratext"` + explicit `[[bin]] name = "parat"`), `pkgs/
textinfer.nix` → `pkgs/paratext.nix` (`pname`/`mainProgram` updated),
`modules/features/ai-textinfer.nix` → `ai-paratext.nix`
(`features.textinfer` → `features.paratext`, `~/.config/textinfer/` →
`~/.config/paratext/`), `ai-textinfer.tune-specs.nix` → `ai-paratext.
tune-specs.nix` (tune-spec key `textinfer` → `paratext` - this key must
match the derivation `pname` for the tune-support system to find it),
`flake.nix`'s `externalOverlay`/`tunePackagesByContext` entries,
`modules/composition.nix`'s import, and all `TEXTINFER_*` env vars →
`PARATEXT_*`. Older dated entries above this one that still say
`textinfer` are left as-is (historical log, not rewritten).

**Validation:** `cargo build --release` clean (no warnings after a
couple of fixups); confirmed the produced binary is named `parat` under
package `paratext`; a real `--fetch --tiny` + piped `--passthrough`/
`--summarize` run against the actual TinyLlama GGUF + its companion
tokenizer.json produced coherent (if verbose/non-JSON-compliant - a tiny
1.1B model's own instruction-following limit, consistent with its
"smoke-test only" registry documentation) English output, respecting
`--max-tokens` and streaming tok/s progress correctly. Full `nix build
.#homeConfigurations.default.activationPackage --override-input
dots-local "git+file://$HOME/dots-local"` succeeds after `git add`-ing
the new `pkgs/paratext/src/model.rs` (Nix's git-tracked source filtering
silently excludes untracked files - a build failure this produced,
worth remembering for any future new-file-in-package situation);
confirmed the built activation package has `parat` on `$PATH`, `pkgs.
paratext` registered as the tuned top-level package, and `~/.config/
paratext/models.json` rendered with the new `tokenizer_repo_id` field
per model.

## 2026-07-26: `parat`/`paratext` cuda/mkl/cudnn feature wiring

User asked whether cuda/mkl (Cargo features just added to
`pkgs/paratext/Cargo.toml`) can be enabled "by flag/auto-detect", and
what cudnn would add.

**Findings (verified against candle-core/candle-nn/candle-transformers'
actual upstream `Cargo.toml` feature graphs, fetched from GitHub
`main`):**
- `cuda`, `mkl`, `cudnn` are all Cargo **compile-time** features - a
  single binary can't toggle "compiled with cuda support" at runtime.
  "Auto-detect" only applies *within* an already cuda-enabled build:
  `model.rs`'s `pick_device()` already does this correctly (tries
  `Device::new_cuda(0)`, falls back to CPU if no GPU present at
  runtime) - that part needed no change.
- `cudnn = ["cuda", ...]` upstream - requires/implies `cuda`, can't be
  enabled standalone. Not wired into the Nix build: cuDNN mainly
  accelerates convolutions, offering little expected benefit for this
  GEMM-dominated LLM-decode workload. Left defined in Cargo.toml as a
  documented, manually-enablable feature only.
- `mkl = ["dep:intel-mkl-src", ...]` is CPU-only, no GPU dependency -
  initially looked like a promising fix for the documented candle
  CPU-decode performance regression (see the rewrite entry above).
  **Tested directly** (`cargo build --release --features mkl`, outside
  Nix): intel-mkl-src's build.rs downloaded a real static MKL
  redistribution successfully, but linking failed with `undefined
  symbol: hgemm_` - candle-core's mkl matmul path calls the
  half-precision GEMM entry point, which isn't present in
  intel-mkl-src 0.8.1's default static MKL package. This is a genuine,
  reproducible incompatibility between candle 0.9.2 and intel-mkl-src
  0.8.1's current default feature set, **not** a Nix-sandbox/packaging
  problem. Decision: keep the `mkl` Cargo feature defined (for future
  revisiting once upstream fixes it, or a differently-configured
  intel-mkl-src variant is tried) but leave it OFF by default in both
  Cargo.toml (`default = []`) and `pkgs/paratext.nix` (`mklSupport ?
  false`, documented as known-broken).
- Also required adding `#[cfg(feature = "mkl")] extern crate
  intel_mkl_src;` to `main.rs` - enabling candle's `mkl` feature alone
  only makes `intel-mkl-src`'s build.rs run; without the explicit
  `extern crate`, the linker never actually pulls in MKL's native
  symbols (documented behavior, confirmed via candle's own examples).

**cuda wiring implemented ("build only cuda when available" per user
request):**
- `pkgs/paratext.nix` gained `cudaSupport ? false`, `cudaComputeCap ?
  null`, `cudaPackages ? null`, `mklSupport ? false`, `mkl ? null`
  arguments. `cudaSupport` only takes effect if `cudaComputeCap` is
  also non-null - throws a clear error otherwise, since a Nix build
  sandbox has no physical GPU to auto-detect a compute capability from
  (confirmed via candle-kernels' `build.rs`, which uses the
  `cudaforge` crate's `CUDA_COMPUTE_CAP` env var / `nvidia-smi` query
  fallback chain - the env var is the only option available in a
  sandboxed build). When cuda is enabled: adds
  `cudaPackages.cuda_nvcc` to `nativeBuildInputs`,
  `cudaPackages.{cuda_cudart,cuda_cccl}` to `buildInputs`, sets
  `CUDA_COMPUTE_CAP` env to the given value, and adds `"cuda"` to
  `buildFeatures`.
- `modules/local/schema.nix` gained `machine.cudaComputeCap` (nullOr
  str, default null) - the bare-integer compute-cap string (e.g. "89",
  "120") a given host's Nvidia GPU needs, parallel in spirit to
  `llama-cpp.nix`'s hardcoded `CMAKE_CUDA_ARCHITECTURES=120` but
  properly parameterized per-host here (paratext, unlike llama-cpp.nix,
  is meant to be portable across machines, not single-host). Per the
  standing "changing schema.nix" rule, also updated
  `templates/local/flake.nix`'s commented example.
- `flake.nix`'s `externalOverlay` now calls `pkgs/paratext.nix` with
  `cudaSupport = dotsLocal.gpu == "nvidia"; cudaComputeCap =
  dotsLocal.machine.cudaComputeCap;` - `cudaPackages`/`mkl` themselves
  are auto-wired by `callPackage` from the ambient `prev` package set
  (both are real top-level nixpkgs attributes, confirmed via `nix eval`
  on this host's nixpkgs pin), no explicit passing needed. The
  package-tuning overlay (`modules/flake/package-tuning.nix`) needed NO
  changes - it only `overrideAttrs`s the already-built
  `prev.external.paratext` derivation to inject `RUSTFLAGS`, it doesn't
  re-invoke `callPackage`.
- This dev host has no `dotsLocal.gpu == "nvidia"`, so cudaSupport
  correctly resolves to `false` here and no CUDA toolchain was pulled
  in - confirmed via `ldd` on the built `parat` binary (no libmkl/libcuda
  linked) and a full default-args package + full activation-package
  build, both green. Cuda-enabled compilation itself was **not**
  build-tested end-to-end on real hardware in this session (no Nvidia
  GPU on this host) - flagged for verification whenever this is first
  actually run on an Nvidia-equipped `dots-local` host with
  `gpu = "nvidia"` and `machine.cudaComputeCap` set.

## 2026-07-26: llama-cpp.nix CUDA gating; MKL fix investigation; per-worker thread cap

**1. `llama-cpp.nix` now gates CUDA on `dotsLocal.gpu == "nvidia"`.** Its
`setup-llama-cpp` script runs directly on the target machine (clones +
`cmake`-builds llama.cpp into `~/.local/share/llama-cpp-chromaden` at
runtime), NOT inside the Nix build sandbox - so unlike
`pkgs/paratext.nix`, it genuinely can auto-detect the GPU's compute
capability via CMake's `-DCMAKE_CUDA_ARCHITECTURES=native` (queries
nvcc/the real GPU present at that time). Replaced the hardcoded
`CMAKE_CUDA_ARCHITECTURES=120` with `native`, and made the whole set of
CUDA-only cmake flags/env exports (`GGML_CUDA`, `CMAKE_CUDA_ARCHITECTURES`,
`GGML_CUDA_FA_ALL_QUANTS`, `CMAKE_CUDA_HOST_COMPILER`, `CMAKE_CUDA_FLAGS`,
the `CUDA_HOME`/`gcc-15` build-env exports, the `cuda-llama`/`gcc15`/
`gcc15-libs` alien packages, `CUDA_HOME` sessionVariable) conditional on
a new `cudaEnabled = dotsLocal.gpu == "nvidia"` local, computed the same
way as `pkgs/paratext.nix`'s `cudaSupport`. `vulkan-llama` stays
unconditional (cross-vendor). This makes the feature safe to enable on
a non-Nvidia machine too (falls back to a CPU+Vulkan llama.cpp build)
rather than assuming CUDA is always wanted whenever `enable = true`.

**2. Investigated fixing MKL's `hgemm_` link failure (from the previous
entry) - concluded NOT to pursue it.** Root cause confirmed precisely:
`candle-core/src/mkl.rs` declares `hgemm_` (Fortran-style half-precision
GEMM) as an unconditional `extern "C"` binding, always required at link
time whenever the `mkl` feature is on (regardless of whether any F16
matmul actually runs) - and per upstream issue
huggingface/candle#2793 (open since March 2025, still unresolved),
`intel-mkl-src`'s own auto-downloaded static MKL bundle (2020.1) never
had this symbol, while a real, currently-installed Intel oneMKL (2023.1+
oneAPI) reportedly does, IF linked dynamically via `libmkl_rt.so`
instead of the crate's default static mode.
  - Verified this concretely: built `pkgs.mkl` from this nixpkgs pin
    (real oneAPI 2023.1.0 rpm redistribution, not the ancient 2020.1
    bundle) and confirmed via `nm -D libmkl_rt.so` that it DOES export
    `hgemm_`, `sgemm_`, `dgemm_` directly.
  - Tried wiring our own `intel-mkl-src` dependency entry to
    `default-features = false, features = ["mkl-dynamic-lp64-iomp"]`
    (to point it at that dynamic `libmkl_rt.so` instead of downloading
    its own bundle) - this does NOT work: Cargo unifies features across
    the whole dependency graph for a single crate/platform, and
    candle-core's own `Cargo.toml` requests `intel-mkl-src`'s *default*
    feature (the static `mkl-static-lp64-iomp` config) without
    `default-features = false` - so both the static default AND our
    dynamic override get enabled simultaneously, which crashes
    `intel-mkl-src`'s own build script (`error[E0428]: the name
    'MKL_CONFIG' is defined multiple times`, since its
    `def_mkl_config!` macro is invoked twice with conflicting configs).
  - The only way to actually fix this from our side would be
    maintaining a `[patch.crates-io]` override pointing at a modified
    fork of `intel-mkl-src` (with `default = []` in its own manifest) -
    a real, permanent maintenance burden for a first-party tool in a
    dotfiles repo, fixing an issue that's been open upstream for over a
    year with no indication of being prioritized. **Decision: not worth
    it.** Reverted the Cargo.toml experiment back to the plain
    `intel-mkl-src = { version = "0.8", optional = true }` entry (still
    unused/off by default; `mkl` remains a documented, known-broken,
    opt-in-only Cargo feature per the previous entry). Downgrading
    candle-core/intel-mkl-src does NOT help either - the bundled static
    MKL's vintage (2020.1) predates the symbol regardless of which
    candle-core minor version is used, and the issue reproduces on
    current (`main`) candle per the still-open GH issue.

**3. Fixed a real, currently-applicable thread-oversubscription gap** in
worker dispatch (unrelated to MKL, applies to candle's current
rayon-based CPU kernels right now): `topology::pin_current_process()`
restricts a worker's *scheduling* affinity to its assigned core group,
but rayon's global thread pool - which candle-core's gemm/quantized
kernels use internally - defaults to spawning one thread per *visible*
logical CPU, ignoring that affinity mask entirely. Fixed in
`run_worker()` (main.rs) by setting `RAYON_NUM_THREADS` (and,
defensively, `OMP_NUM_THREADS`/`MKL_NUM_THREADS` for if MKL is ever
unblocked per point 2) to the exact pinned core count, before
`load_model()` triggers any rayon-consuming candle op - this is what
actually enforces the intended "1 worker per CCD, 1 thread per physical
core max" design end-to-end, not just the affinity mask alone. The
single-process (workers <= 1) path is intentionally left unbounded, to
use the whole machine for a single interactive job as before.

**Validation:** `cargo build --release` clean for all of the above;
full `nix build .#homeConfigurations.default.activationPackage
--override-input dots-local "git+file://$HOME/dots-local"` succeeds
(this dev host has no `dotsLocal.gpu == "nvidia"`, so it validates the
CPU-only/no-CUDA path for both `paratext` and `llama-cpp.nix`; the
CUDA-enabled path for either was not build-tested end-to-end on real
Nvidia hardware this session).

## 2026-07-26: MKL fix reversed - now actually working, plus flash-attn/LTO/mimalloc

The prior entry's "not worth it" call on MKL is **reversed** - re-evaluated
per explicit user request ("if the change set is small, it's absolutely
worth it") and the real fix turned out to be small and self-contained:

**1. MKL now genuinely links and runs.** Root cause was narrower than
first thought: the *only* substantive problem is candle's own workspace
root `Cargo.toml` hardcoding `intel-mkl-src`'s feature to
`mkl-static-lp64-iomp` (the broken static 2020.1 bundle missing
`hgemm_`). Every candle crate we use just inherits that via
`workspace = true` - so the fix doesn't require a `[patch.crates-io]`
fork of `intel-mkl-src` itself (rejected in the prior entry); it only
requires detaching **candle-core/candle-nn/candle-transformers** from
candle's workspace. Implemented as `pkgs/paratext/vendor/{candle-core,
candle-nn,candle-transformers}/`: unmodified `src/` copied verbatim from
the upstream 0.9.1 tag (~3.9MB total), with hand-written Cargo.toml
manifests using literal dependency versions instead of `workspace = true`
- the ONLY substantive change from upstream is `intel-mkl-src`'s feature:
`mkl-dynamic-lp64-iomp` instead of `mkl-static-lp64-iomp`. Wired in via
`[patch.crates-io]` in `pkgs/paratext/Cargo.toml`. `candle-kernels`,
`candle-metal-kernels`, `ug`/`ug-cuda`/`ug-metal`, and `candle-flash-attn`
are all real, independently-published crates.io packages (verified via
the sparse index, not just `cargo build` resolution) - none of those
needed vendoring, only the three crates that actually declare
`intel-mkl-src = { workspace = true }`.

  - **Gotcha: `[patch.crates-io]` silently did nothing at first.**
    paratext's own `candle-core = "0.9"` requirement resolved to the
    newest matching crates.io release (0.9.2, which has no matching git
    tag - apparently a registry-only point release), while our vendored
    manifests declared `version = "0.9.1"` (matching the tag we cloned
    from) - Cargo's patch mechanism requires the patched crate's version
    to match what the dependency graph actually selects, so it fell back
    to the plain registry crate with a silent `warning: patch ... was not
    used in the crate graph` (easy to miss). Fixed by pinning paratext's
    own deps to the exact vendored version (`candle-core = "=0.9.1"` etc,
    not just `"0.9"`) so resolution can only pick 0.9.1, which only the
    patch provides. **Always verify a `[patch]` actually took effect** by
    checking `Cargo.lock` for the patched crate having no
    `source = "registry+..."` line (path dependencies have none) - a
    successful build alone does NOT prove the patch was used, since Cargo
    silently falls back to the registry version when a patch doesn't
    match.
  - **Gotcha: dynamic MKL needs `-Wl,--no-as-needed`, not just the right
    Cargo feature.** MKL's dynamic layered libraries
    (`libmkl_intel_lp64.so`/`libmkl_intel_thread.so`/`libmkl_core.so`/
    `libiomp5.so`) cross-reference each other via weak symbols resolved
    through the process's global symbol table at runtime, NOT via
    `DT_NEEDED` entries (`readelf -d libmkl_intel_lp64.so` shows only
    `libdl.so.2` as NEEDED - nothing links it to the other three). Our
    own code only directly references symbols re-exported by
    `libmkl_intel_lp64.so` (`sgemm_`/`dgemm_`/`hgemm_`), so the default
    `--as-needed` linker behavior dropped `mkl_intel_thread`/`mkl_core`/
    `iomp5` from the final binary entirely (verified via `ldd` showing
    only one of the four libs linked), causing an `undefined symbol:
    mkl_blas_dgemm` **runtime** error (not a link-time error - passed
    `cargo build` fine, only failed when actually running the binary).
    Fixed with `RUSTFLAGS="-C link-arg=-Wl,--no-as-needed"` for manual
    `cargo build --features mkl` testing, and `env.NIX_LDFLAGS =
    "--no-as-needed"` (only under `mklEnabled`) in `pkgs/paratext.nix`
    for the real Nix build. Also added a `postFixup` `patchelf
    --add-rpath "${mkl}/lib"` so `parat` finds MKL's shared libs at
    runtime without requiring callers to set `LD_LIBRARY_PATH`
    themselves.
  - Verified end-to-end: `ldd` shows all four MKL/iomp5 libs linked,
    `parat --help` runs cleanly both from a plain `cargo build --release
    --features mkl` binary AND from a real `nixpkgs.callPackage
    pkgs/paratext.nix { mklSupport = true; mkl = nixpkgs.mkl; }` build.
    `pkgs/paratext.nix`'s stale "known-broken, do not enable" comment
    block has been rewritten to describe the actual fix.

**2. Enabled `flash-attn` as a Cargo feature, gated on `cuda`.** Of
paratext's three supported model architectures (`quantized_llama`,
`quantized_phi3`, `quantized_qwen2`), only `quantized_phi3` has any
flash-attn wiring in candle-transformers at all - and that happens to be
our **default model's architecture** (`phi-4`, per
`modules/features/ai-paratext.nix`'s `defaultModel`), not an edge case.
`candle-flash-attn` 0.9.1 is a real, independently-published crates.io
crate (verified via the sparse index) - no vendoring needed, just an
optional dependency re-added to `vendor/candle-transformers/Cargo.toml`
plus a `flash-attn = ["cuda", "candle-transformers/flash-attn"]` feature
in `pkgs/paratext/Cargo.toml`. GPU-only (requires `cuda`); CPU builds are
unaffected.

**3. Cross-crate LTO** (`lto = true` in `pkgs/paratext/Cargo.toml`'s
`[profile.release]`): the existing tune-specs.nix "fast" mode's
`codegen-units=1` only optimizes within a single crate, but
candle-core/candle-nn/candle-transformers are separate crates - the vast
majority of actual tensor-op calls cross those boundaries and weren't
being inlined/cross-optimized without this. Safe, always-on, no feature
gate needed.

  - **Deliberately did NOT set `panic = "abort"`** despite it being
    another commonly-suggested release-profile tweak: `main.rs`'s
    worker/writer threads are explicitly joined with
    `.join().map_err(|_| anyhow::anyhow!("... panicked"))` so a single
    job's panic is reported as one failed job, not a whole-batch crash
    (see `spawn_workers`/`run_worker` around main.rs:559-592) - `abort`
    would turn that intentional per-job fault isolation into a total
    process kill. Verified no `catch_unwind` usage exists that this
    would otherwise help.

**4. `mimalloc` as the global allocator** (`#[global_allocator]` in
`main.rs`, unconditional/no feature gate) - candle's tensor ops do heavy
small/medium heap churn per op; mimalloc's thread-caching design is a
known-good drop-in replacement for glibc's malloc for this kind of
workload. Not upstream-candle-precedented or independently benchmarked
in this repo (unlike tune-specs.nix's measured "fast" mode number) - a
reasonable, low-risk default rather than a measured decision.

**5. `MKL_DYNAMIC=FALSE`/`OMP_DYNAMIC=FALSE`** added alongside the
existing per-worker `RAYON_NUM_THREADS`/`OMP_NUM_THREADS`/
`MKL_NUM_THREADS` cap in `run_worker()` (main.rs) - without these, MKL/
OpenMP can dynamically scale the thread count *down* under perceived
contention from sibling workers pinned to other CCDs, defeating the
fixed-size cap and making generation latency unpredictable across
concurrent workers.

**Bug found and fixed along the way:** the entire `pkgs/paratext/vendor/`
directory (250 files) was created but never `git add`ed, so the flake's
git-filtered source silently excluded it - `nix build`/`apply-dots` was
building without the vendor patch at all until this was caught
(`error: failed to read vendor/candle-core/Cargo.toml: No such file or
directory` during a real `apply-dots` run). **Any new file added under a
package's source tree must be `git add`ed before it will be visible to a
flake-driven Nix build** - a successful standalone `cargo build` does NOT
prove the Nix packaging will see the same files, since Cargo reads the
working tree directly while Nix flakes read only the git index/tracked
files.

**Validation:** manual `cargo build --release --features mkl` (with
`MKLROOT`/`LIBRARY_PATH` pointed at a manually-built `nixpkgs.mkl`) links
and runs cleanly; a standalone `nixpkgs.callPackage pkgs/paratext.nix
{ mklSupport = true; mkl = nixpkgs.mkl; }` build succeeds end-to-end; a
full real `apply-dots` run (default, non-mkl, non-cuda build for this
host) completes activation successfully with the vendored patch,
flash-attn feature wiring, LTO, and mimalloc all in place, and the
installed `parat --help` runs correctly.

## 2026-07-26: MKL wired into dots-local via new `machine.mklSupport`; NUMA-aware worker grouping

**dots-local wiring.** Added `machine.mklSupport` (bool, default `false`)
to `modules/local/schema.nix`, next to the existing `machine.
cudaComputeCap`. Wired it into `flake.nix`'s `externalOverlay`:
`external.paratext = prev.callPackage ./pkgs/paratext.nix { cudaSupport
= dotsLocal.gpu == "nvidia"; cudaComputeCap = dotsLocal.machine.
cudaComputeCap; mklSupport = dotsLocal.machine.mklSupport; mkl = prev.
mkl; }`. Unlike `cudaSupport` (gated on the `gpu` axis), `mklSupport` is
CPU-only and independent of any GPU field - a machine can have both,
either, or neither enabled. `pkgs.mkl` needs `config.allowUnfree = true`,
already set repo-wide in `flake.nix`'s two `nixpkgs.legacyPackages`/
`import nixpkgs` calls, so no extra unfree-allow plumbing was needed.

Set `machine.mklSupport = true` in `dots-local/flake.nix` for this
machine ("lub": AMD Ryzen AI 7 PRO 350, integrated Radeon 860M only, no
discrete Nvidia GPU, single NUMA node) - it's CPU-bound for `parat` by
necessity, and MKL now genuinely links and runs (see the prior "MKL fix
reversed" entry). Left `gpu` unset (null) - no Nvidia hardware, and
setting `gpu = "amd"` wasn't evaluated/needed for this request since
nothing currently branches on the AMD case for this host's actual usage.

Updated `templates/local/flake.nix`'s commented `machine = { ... }`
example block with `mklSupport = true;  # CPU-only, independent of gpu:
enables parat's mkl build`, per this repo's standing rule that any
`schema.nix` field needs a template mention in the same change.
`setup.sh`'s "Next steps" text already points at `dots-local-options` for
the full field list rather than enumerating fields itself, so it needed
no change.

Validated via `nix build .#homeConfigurations.default.activationPackage
--override-input dots-local "git+file:///home/sp/dots-local"`: `parat`
rebuilt with the `mkl` feature end-to-end (`cargoBuildHook` compiled the
vendored candle patch + mimalloc + flash-attn-capable transformers, MKL
libs linked via the existing `--no-as-needed`/rpath fix), full home-
manager activation succeeded.

**NUMA mechanical sympathy (`pkgs/paratext/src/topology.rs`).** Prior
worker-core grouping used `/sys/devices/system/cpu/cpuN/topology/die_id`
(CCD) as a proxy for memory locality. This is only a reliable NUMA proxy
on NPS1-configured AMD parts - on multi-socket/NPS>1 EPYC hosts a single
CCD can be split across NUMA nodes, or several CCDs merged into one
node, so grouping by CCD alone could still let a worker's threads span a
real memory-locality boundary. Added `node_id_for_core()`, reading the
kernel's authoritative `/sys/devices/system/cpu/cpuN/node{M}` symlink
(confirmed present and correctly reporting `node0` on this machine's
single-node topology via `ls -d /sys/devices/system/cpu/cpu0/node*`), and
made it the primary grouping key in `cores_by_die()`/
`physical_cores_by_die()`, falling back to `die_id` only when no `node*`
symlink exists (non-NUMA kernel builds, sandboxes). Kept the existing
public function names (`physical_cores_per_die`, `plan_workers`,
`pin_current_process`) unchanged to avoid unnecessary churn in
`main.rs`/`cli.rs`'s user-facing help text - only internal grouping logic
and doc comments changed.

This change is low-risk/high-leverage specifically *because* `main.rs`'s
`run_worker()` already calls `topology::pin_current_process(&cores)`
**before** `load_model()` (confirmed at call sites, line ~459 vs ~487) -
Linux's default "local" memory allocation policy means a thread's first
touch of a page (e.g. mmap'd GGUF weights during model load) allocates
that page on the NUMA node the thread is currently running on. Since
affinity is pinned before any model loading happens, correctly grouping
cores by real NUMA node (rather than CCD) directly and immediately
improves memory locality with no further explicit `numactl`/`libnuma`
membind code needed - no new dependency, no runtime behavior change
beyond which node's DRAM gets used.

**Not done / explicitly out of scope:** no explicit `numactl --membind`/
`libnuma` binding was added (unnecessary given the pin-before-load
ordering above); no live multi-node validation was possible on this
machine (single NUMA node) - the change is a correctness fix on paper,
verified only by inspecting `/sys` layout and by successful compilation,
not by observing an actual before/after latency difference on real
multi-node hardware. Flag for review if this is ever run on a genuine
multi-socket/NPS>1 host.

## 2026-07-27: mmap-based zero-copy GGUF model loading in vendored candle

**Problem:** `parat`'s GGUF model load took ~31s for the default phi-4
(8.5GB Q4_K) model even though a raw sequential `cat` of the same
warm-page-cache file took ~0.4s - a ~77x gap purely from candle's own
per-tensor parsing, not disk I/O. Root cause: candle's stock GGUF path
copies every tensor's bytes **twice** - `TensorInfo::read()`
(`vendor/candle-core/src/quantized/gguf_file.rs`) does `seek`+
`read_exact` into a fresh heap `Vec<u8>`, then `from_raw_data()`
(`vendor/candle-core/src/quantized/ggml_file.rs`) does `.to_vec()` again
to build the final `Vec<T>` stored in `QStorage::Cpu`. Upstream candle
itself has an unaddressed `// TODO: Mmap version to avoid copying the
data around?` comment at `ggml_file.rs`'s `read_one_tensor` - this is a
known, real gap in candle, not something specific to our vendoring.

**Fix implemented (all in the vendored forks, consistent with the
existing MKL-patch precedent of editing vendored candle/candle-
transformers directly):**
- `vendor/candle-core/src/quantized/mod.rs`: added `MmapedBlocks<T>`, a
  read-only `QuantizedType` impl that borrows `data: &'static [T]`
  directly from an `Arc<memmap2::Mmap>` kept alive in the same struct
  (`_mmap` field) instead of owning a `Vec<T>`. `from_float` (only used
  when *writing*/quantizing, never during inference load) bails since
  the storage is read-only.
- `vendor/candle-core/src/quantized/ggml_file.rs`: added
  `qtensor_from_mmap`/`from_mmap_data`, mirroring the existing
  `qtensor_from_ggml`/`from_raw_data` dtype-dispatch, but slicing
  straight from the mmap. `Device::Cpu` builds `MmapedBlocks` (zero
  copy); `Metal`/`Cuda` still slice from the mmap (saves the read()/
  seek() syscalls + one intermediate `Vec<u8>` vs. the old path) then
  fall through to the same unavoidable host->device upload copy.
- `vendor/candle-core/src/quantized/gguf_file.rs`: added
  `TensorInfo::read_from_mmap`; introduced a new `TensorSource` trait
  (`load_tensor(&mut self, info, tensor_data_offset, device) ->
  Result<QTensor>`) with a blanket `impl<R: Read + Seek> TensorSource for
  R` (so every existing `Read+Seek`-based caller keeps compiling
  unchanged) plus a new `MmapSource` (wraps `Arc<memmap2::Mmap>`,
  `unsafe fn open(path)` - safety contract inherited from
  `memmap2::MmapOptions::map`, same as candle's own pre-existing
  `MmapedSafetensors::new`). `Content::tensor` is now generic over
  `S: TensorSource` instead of `R: Read + Seek` directly.
- `vendor/candle-transformers/src/models/{quantized_llama,quantized_phi3,
  quantized_qwen2}.rs`: mechanical signature-only change - each
  `from_gguf`'s generic bound (and phi3's `QLinear::new` helper) changed
  from `R: std::io::Read + std::io::Seek` to
  `S: candle::quantized::gguf_file::TensorSource`, param renamed `R` ->
  `S`. **No call-site bodies changed** - every `ct.tensor(reader, name,
  device)` call across all three files is untouched, since `Content::
  tensor` itself now dispatches through `TensorSource`.
- `src/model.rs`: `LoadedModel::load()` still opens the file normally via
  `std::fs::File` to parse the (small) GGUF header/metadata via
  `Content::read`, then drops that handle and opens an `unsafe {
  gguf_file::MmapSource::open(gguf_path) }` for the actual tensor-loading
  `from_gguf` calls.

**Why this shape and not a smaller "just avoid the second `.to_vec()`"
patch:** the user explicitly asked for the mmap/zero-copy option ("Option
1 for now") in the prior turn's ranked list, which also uniquely enables
future benefit for the multi-worker subprocess architecture (separate OS
processes mmap'ing the same file share the same read-only physical pages
via the page cache, rather than each worker paying its own private
in-process copy cost) - a smaller doubled-copy-avoidance patch wouldn't
provide that cross-process sharing property.

**Validated:** `cargo build --release` clean (only pre-existing,
unrelated warnings); measured model load time for the default phi-4
(8.5GB Q4_K) model dropped from ~31s to a consistent ~1.7-2.6s across
repeated runs (~12-18x faster), matching the ~0.4s raw-I/O floor plus
residual per-tensor `QTensor`/metadata construction overhead. Generation
throughput itself (tokens/sec) is unaffected by this change and remains a
separate, already-flagged, out-of-scope slow-generation issue.

**Not done / explicitly out of scope:** did not touch the GPU
(CUDA/Metal) load path's actual behavior beyond syscall/allocation
savings - the host->device upload copy for those devices is unavoidable
and unchanged. Did not attempt a "resident daemon keeps mmap warm across
invocations" design (that's the separate, previously-flagged, explicitly
out-of-scope "persistent daemon" option (c) from the initial exploration
- would reverse this project's in-process, no-server design decision and
needs explicit sign-off if ever revisited).

## 2026-07-27: `appimage-update` renamed to `update-appimages`; `pi` disabled on `lub`

**Supersedes** the earlier "`appimage-update` naming stays as-is
(well-established)" call recorded in this file and in
`project-brief.md`/`architecture.md` - the user explicitly asked for the
rename this time, so it now follows the same `update-<noun>`/`setup-<x>`
verb-first convention as `update-dots`/`update-alien-packages` instead of
being the one `<noun>-<verb>`-shaped holdout. Renamed the
`pkgs.writeShellScriptBin` name, its own internal usage text, its
`dots.tools` registry entry (`modules/core/scripts.nix`), and all doc
references (`README.md`, `OVERVIEW.md`, `modules/core/scripts/common.sh`
comment) in one pass. Did not touch the historical entries in
`decisions.md`/`project-brief.md`/`architecture.md` that recorded the old
"stays as-is" call - those remain as an accurate record of what was
decided *then*; this new entry is the record of what changed and why.

Also disabled `suites.ai-apps.pi` on this machine (`lub`,
`dots-local/host.nix`) by simply removing the `pi = true;` opt-in line -
`pi` was already off-by-default globally
(`coreLib.mkDefaultDisabledOption` in `modules/suites/ai-apps.nix`), so no
`dots` repo change was needed for the "disable by default" half of the
request; only the machine-local opt-in needed removing.

## 2026-07-31: `zellij` -> `byobu` in `suites.tui-apps`; added `noti` to core

Removed `zellij` (package, `cfg.zellij` option, `~/.config/zellij/`
config.kdl + layouts/compact.kdl, and its bash `initExtra` help hint)
from `modules/suites/tui-apps.nix`, replacing it with `byobu` end to end:
new `cfg.byobu` option (`mkDefaultEnabledOption`, same default-on
behavior as zellij had), `appSet` entry (alien-aware, pulls in the native
`byobu` package on distros where it's cataloged -
`tui-apps.cachyos-packages.nix`'s `pacman = [ "byobu" ]`, and newly added
`tui-apps.debian-packages.nix`'s `apt = [ "byobu" ]` since, unlike
zellij/yazi, byobu ships in Debian/Ubuntu's official archive - conforms
to dots's official-repos-only convention), `~/.byobu/backend` pinned to
`"tmux"` (byobu can also drive GNU screen; pinning keeps behavior
consistent across machines) and a trimmed `~/.byobu/statusrc`, and a bash
`initExtra` hint mirroring the old zellij one but checking
`$BYOBU_BACKEND`/`$TMUX` instead of `$ZELLIJ`.

Also updated `features/niri-noctalia.nix`'s
`terminal-scratchpad-toggle` script/wiring (per explicit user
confirmation this should change too, not just the tui-apps suite) -
swapped its `zellij` binary/session-management calls for byobu's
tmux-compatible subcommands (`list-sessions -F '#S'` + `grep -qx`,
`new-session -d -s`, `attach-session -t`), renamed the shell variable
from `zellij` to `byobu`, and updated the `dots.tools` synopsis text.

**Why byobu over zellij:** user-requested straight swap, no rationale
beyond preference recorded beyond this. No functional gap found - byobu
(tmux-backed here) covers the same "detached session + reattach into a
scratchpad terminal" use case zellij was doing.

**Also added `noti`** (cross-platform CLI notification tool - hooks a
command's exit into a desktop/OSD notification) to the always-installed
`modules/core/default.nix` package list, per explicit request. No alien
wiring needed - like the rest of that file's package list, it's a plain
`pkgs.noti` entry (no `<feature>.<distro>-packages.nix` exists for
`core/default.nix`'s baseline list; this is unrelated to the
suite-scoped alien-package convention used elsewhere).

**Validated:** `nix build .#homeConfigurations.default.activationPackage`
clean (noti + byobu backend/statusrc derivations built, no zellij
derivations); `alienPackages.enabledPackages` confirms `byobu` is
correctly routed to the native `pacman` package on this machine (same
alien-first behavior zellij had).

## 2026-07-31: Byobu Tokyo Night x solarpunk-neon theme

Added `~/.byobu/.tmux.conf` (`modules/suites/tui-apps.nix`, `cfg.byobu`
gated) - byobu's own hook point for a user tmux-conf snippet, sourced
last so it overrides anything the packaged byobu status config sets.
Palette: Tokyo Night's dark base (`#1a1b26` bg / `#c0caf5` fg,
`#414868` for dim borders/inactive chrome) with neon-green (`#9ece6a`)
and neon-cyan (`#7dcfff`) accents standing in for solarpunk's
nature-meets-tech vibe (active window/pane border, session-name status
segment) instead of Tokyo Night's usual blue/purple-only accenting -
purple (`#bb9af7`) kept for tmux's own message/copy-mode chrome, pink
(`#f7768e`)/amber (`#e0af68`) reserved for activity/bell alerts.

**Validated:** `nix build .#homeConfigurations.default.activationPackage`
(--no-write-lock-file) rebuilt cleanly (only the new
`hm_.byobu.tmux.conf` derivation added); confirmed the rendered
`~/.byobu/.tmux.conf` content in the built home-files output matches the
intended tmux directives.

## 2026-07-31: byobu is paru-only (AUR) on CachyOS, not pacman

Correction to the same-day byobu-theme entry above:
`tui-apps.cachyos-packages.nix`'s `byobu` spec was wrongly cataloged
under `pacman`; byobu is only packaged in the AUR on Arch/CachyOS, so
switched it to `paru = [ "byobu" ]`. Debian/Ubuntu's official-archive
`apt` entry (`tui-apps.debian-packages.nix`) is unaffected/still correct.

**Validated:** `alienPackages.enabledPackages` still lists `byobu`;
`nix build .#homeConfigurations.default.activationPackage` rebuilt
cleanly, now emitting byobu via the `paru`-required-packages manifest
instead of pacman's.

## 2026-07-31: Byobu theme - added solarpunk unicode ascii-art flourishes

Enhanced the same-day Tokyo Night x solarpunk-neon byobu theme
(`~/.byobu/.tmux.conf`) per explicit user follow-up request for "good
unicode based solarpunk ascii art": added `░▒▓` Unicode Block Element
gradient transitions (U+2591-2593, no patched/Nerd Font needed) between
status-bar segment colors as a "dissolve" effect, plus more solarpunk/
neon emoji (🌿⚡ session marker, 🕐 clock, 🌱 date) and bullet-style window
markers (`○` inactive / `➤` current) replacing the plain `#I:#W` text.

**Validated:** rebuilt cleanly; confirmed rendered `~/.byobu/.tmux.conf`
in the built home-files output.

## 2026-07-31: Confirmed byobu theme doesn't clobber default keybindings

User asked to make sure the byobu Tokyo Night x solarpunk-neon theme
(`~/.byobu/.tmux.conf`) doesn't kill byobu's default shortcuts (F2-F12,
prefix key, etc.). Verified by static inspection: every directive in
the file is a purely cosmetic `set -g <style/format-option>` (status/
window-status/pane-border/message/mode/clock-mode styles+formats) - none
are `bind-key`/`unbind-key`/`set -g prefix`/`set -g mode-keys`/
`set -g status-keys`, so byobu's own keybindings (set via `bind-key` in
byobu's packaged config, sourced before this user hook file) are
structurally unaffected. Added an explicit comment in the file itself
documenting this guarantee and instructing future edits to stay
style-only.

## 2026-07-31: Fix - removed broken `~/.byobu/statusrc`, was breaking shell startup

User reported byobu erroring on start (`shell-init: error retrieving
current directory: getcwd: cannot access parent directories`, requiring
Ctrl-D twice to exit) and, after ruling out a stale tmux server
(`tmux kill-server` didn't fix it), the real error surfaced:
`/home/sp/.byobu/statusrc: line 3: disk_io: command not found`.

**Root cause:** the `~/.byobu/statusrc` file added when byobu replaced
zellij (same-day entry above) used the wrong format/mechanism entirely.
Confirmed via byobu's own installed template
(`/usr/share/byobu/status/statusrc`, `/usr/share/byobu/status/status`):
- `statusrc` is a bash-*sourced* file for overriding variables like
  `MONITORED_DISK`/`NETWORK_UNITS`/`BYOBU_DISTRO` etc - NOT a list of
  segment names. Our file wrongly contained bare segment-name words
  (`color`, `disk_io`, `network`, ...) one per line, which bash tried to
  execute as commands when sourcing the file, causing the "command not
  found" errors (and very likely the shell-init/cwd/double-exit symptoms
  too, given they only appeared once byobu started sourcing this file).
- Segment enable/disable is actually controlled by `~/.byobu/status`'s
  `tmux_left`/`tmux_right` variables (`#`-prefix a name to disable it) -
  a completely different file/format than what we wrote.

**Fix:** deleted the `~/.byobu/statusrc` home.file entirely rather than
reformatting it into the correct `~/.byobu/status` mechanism, since it
was already functionally moot - `.tmux.conf`'s `status-left`/
`status-right` (set as part of the Tokyo Night x solarpunk-neon theme)
already fully replace byobu's dynamic segment-driven status line with a
minimal static one (session/clock/date only), which was the original
"trim the noisy default segments" goal from when byobu was first
introduced. Left a detailed comment in `tui-apps.nix` explaining both the
wrong-format bug and why no replacement file is needed.

**Validated:** `nix build .#homeConfigurations.default.activationPackage`
rebuilds cleanly with the `statusrc` derivation no longer generated (home
-manager will remove the stale file from a previous activation on next
`apply-dots`, standard home-manager behavior for files no longer
declared). Did not reproduce live in the user's actual session per their
explicit request not to touch their real $HOME/tmux/byobu state for
testing - relied on inspecting byobu's own installed template files
(read-only, via the package manager's file listing) plus the Nix build
result instead.

## 2026-07-31: WSL DrvFs getcwd() guard for `byobu`

Root cause finally pinned down for the reported "byobu shows several
nested/differently-themed layers, needs multiple Ctrl-D's" symptom: this
machine (`lub`) is itself WSL2 (`dots-local/flake.nix`'s `isWsl = true`;
confirmed via `uname -a` -> `-microsoft-standard-WSL2`), and the user was
sitting in a directory under the Windows-mounted drive
(`/mnt/c/Users/splantikow/...`) when invoking `byobu`. This is a known
WSL DrvFs limitation - `getcwd()` can intermittently fail for processes
whose cwd is on `/mnt/c/...`, which is exactly bash's own
"shell-init: error retrieving current directory: getcwd: cannot access
parent directories" warning. `tmux ls` confirmed there was only ever a
single real session/server (not 3 stacked ones) - the "layers" were
nested shell-init retry attempts from the SAME broken-cwd condition, not
a config/theme bug. Ruled out repo-side auto-launch-in-bashrc as a cause
too (grepped - nothing in dots invokes byobu automatically from shell
startup, only the niri scratchpad script, keybinding-gated).

**Fix:** `modules/suites/tui-apps.nix` now takes `dotsLocal` as a module
arg and, gated on `dotsLocal.isWsl` (not just `cfg.byobu`), wraps `byobu`
in a bash function that checks `builtin pwd` first - if the shell's own
cwd is currently unreadable, `cd "$HOME"` (native WSL Linux filesystem,
never `/mnt/c`) before `command byobu "$@"`. Non-WSL hosts are entirely
unaffected (`lib.optionalString dotsLocal.isWsl` - empty string
otherwise).

**Validated:** `nix build .#homeConfigurations.default.activationPackage`
rebuilt cleanly; confirmed (via `nix path-info
.#homeConfigurations.default.config.home.file.".bashrc".source`) the
guard function renders correctly into the real built `~/.bashrc` on this
WSL host, and `bash -n` on that built file confirms valid syntax.

## 2026-08-01: Real root cause of the byobu nested-relaunch/theme-cycling bug

The WSL `getcwd()` guard above was a real, valid fix for a *different*
bug, but it did **not** fix the user's main complaint: byobu still
"relaunched" itself 2-3 times on exit, each time with a different theme
(green default -> green default again -> finally the real solarpunk
theme, as a `bash -l`), requiring multiple Ctrl-D's to actually quit -
even from a completely fresh WSL-native `$HOME` directory (ruling out
the getcwd theory as the explanation for *this* symptom). Two earlier
attempted fixes in this saga (`byobu-reset` helper, adding `pkgs.tmux`
explicitly since nixpkgs's `byobu` doesn't depend on it) were both
legitimate, worthwhile changes but insufficient - the user correctly
called this out and asked for an actual execution trace instead of more
guessing.

**Root cause (confirmed via a `set -x`-instrumented `pty.fork()` trace of
byobu's real installed nixpkgs source, run against a fully isolated
`$HOME`/`$TMUX_TMPDIR`/socket - never the real `$HOME`):**
`modules/suites/tui-apps.nix` wrote `~/.byobu/backend` with the literal
content `"tmux\n"`. Byobu's own `lib/byobu/include/dirs` (sourced from
`include/common`, itself sourced by `.byobu`, `.byobu-janitor`, etc.)
does `. "$BYOBU_CONFIG_DIR/backend"` - i.e. it `.`-**sources this file as
a shell script**, not merely reads a value out of it. Byobu's own
generator for this file (`.byobu-janitor`) writes
`BYOBU_BACKEND=$BYOBU_BACKEND` (a variable *assignment*) - our file
instead contained the bare word `tmux`, which, when sourced, is not an
assignment at all but a **command invocation**: sourcing the file
literally executes `tmux` (attaching to/creating a session) from deep
inside byobu's own startup script, every single time that script runs.
Since byobu's startup path sources `backend` more than once across its
own launch sequence (directly in `.byobu`, and again inside
`byobu-janitor`, and again in any nested re-entry), each sourcing spawned
another nested tmux invocation - explaining both the "several nested
layers" symptom and the theme cycling (each nested invocation started
without the full byobu env/config context the outermost one has, so it
rendered with tmux's bare default green status line first, only
resolving to the correct solarpunk `.tmux.conf` theme on whichever layer
happened to be the outermost/most-fully-initialized one). This is the
exact same class of bug as the already-documented, already-fixed
`statusrc` incident a few entries up ("bare words got executed as
commands") - just in a different byobu config file, with a much worse
symptom (silently launching nested sessions) instead of a loud "command
not found" error, which is why it went unnoticed for longer.

**Fix:** changed `home.file.".byobu/backend"`'s `text` from `"tmux\n"` to
`"BYOBU_BACKEND=tmux\n"`, matching the format byobu's own janitor
generates and expects when sourcing this file.

**Validated:** re-ran the same isolated-`$HOME`/isolated-`$TMUX_TMPDIR`
`pty.fork()` trace harness used to diagnose this (never touching the
real `$HOME` or default tmux socket, per the user's standing
constraint), copying the corrected `backend` content plus the real
deployed `.tmux.conf`. Confirmed: (1) the solarpunk theme now renders
immediately on first launch (no more green-default-first flash), (2)
sending a single `exit` now causes the child process to actually
terminate (`waitpid` returns a real exit status) with **no** further
session/theme relaunch and **no** additional Ctrl-D's required, and (3)
`tmux list-sessions` polled at 50ms intervals throughout shows only the
one real session plus byobu's own normal, instantly-self-terminating
`new-session -d byobu-janitor` housekeeping session (harmless, expected,
unrelated to this bug). Also rebuilt
`nix build .#homeConfigurations.default.activationPackage --override-input
dots-local git+file://$HOME/dots-local --no-link --no-write-lock-file`
cleanly.

**Lesson for future config files sourced (not just read) by byobu (or
any tool that `.`-sources a config file as shell): the content must
always be a valid shell command/assignment, never a bare token or word -
a bare word that happens to resolve to an executable on `$PATH` (like
`tmux`) is a particularly dangerous silent-failure mode, since it runs
successfully instead of erroring.**

### 2026-07-31 — `byobu` reverted from alien/paru to plain nixpkgs package

Earlier this window `byobu` was routed through `alien.mkEntry` (AUR-only
on Arch/CachyOS, since pacman's official repos don't carry it - confirmed
via Arch's package search JSON API returning zero results). User then
pointed out nixpkgs packages `byobu` directly
(search.nixos.org/packages?query=byobu) and asked why an AUR/paru build
was preferred over just using the working nix package - followed by "No
nix only" to also drop the (valid, official-archive) Debian `apt` spec,
i.e. use the nixpkgs package unconditionally on every distro.

**Rationale:** the alien-package system exists for cases where a native
package genuinely works *better* (system integration, faster updates,
native deps, distro-tuned builds - see OVERVIEW.md's "Why Alien
Packages?"), not as a blanket default. For a plain CLI tool like byobu
with no GUI/desktop-integration angle, there's no such benefit - an
AUR/paru build adds real cost (compile time, trust surface) for zero
gain over the already-working nixpkgs derivation.

**Fix:** removed the `byobu` alien spec entirely from both
`modules/suites/tui-apps.cachyos-packages.nix` (was `paru = [ "byobu" ]`)
and `modules/suites/tui-apps.debian-packages.nix` (was `apt = [ "byobu" ]`
- even though that one was a legitimate official-archive package, not an
AUR-style concern). `mkEntry`/`hasAlien` in `modules/core/alien-packages.nix`
falls back to the plain `pkgs.byobu` nix package on every distro now that
no `<feature>.<distro>-packages.nix` file defines a `byobu` spec. Added
comments in both distro-packages files documenting why byobu is
deliberately absent, so a future contributor doesn't "helpfully" re-add
it.

**Validated:** `nix build .#homeConfigurations.default.activationPackage
--override-input dots-local "git+file://$HOME/dots-local" --no-link
--no-write-lock-file` - confirmed `byobu-6.15` fetched straight from
`cache.nixos.org` (not built via alien/paru path) after the cachyos spec
removal; re-ran clean after the debian spec removal too.

### 2026-08-01 — Real root cause of "byobu nests/cycles through wrongly-themed sessions" found: stale tmux sessions, not a config bug

After the WSL `getcwd()` fix, user reported byobu still "loops": launch ->
green theme -> exit -> auto-reenters green theme -> exit -> auto-reenters
solarpunk theme -> exit -> finally exits for real. Traced through byobu's
actual installed source (`$BYOBU_PREFIX/bin/.byobu`, via the nixpkgs
`byobu` derivation, not guesswork) rather than speculating:

```
sessions=$($BYOBU_BACKEND list-sessions 2>/dev/null) || true
...
case "$sessions" in
  *\(*\)*) exec byobu-select-session ;;   # attach to an EXISTING session
  *) exec tmux ... $DEFAULT_WINDOW ;;      # only creates fresh if NONE exist
esac
```

Plain `byobu` (no args) only ever creates a new session if the (plain,
default-socket) tmux server has zero sessions - otherwise it always
attaches to an existing one via `byobu-select-session`, cycling through
them if more than one exists and the current one ends. Combined with the
fact that tmux only *applies* `set -g <style>` options at the moment a
session is created (never retroactively to a session already running on
a still-alive server), every earlier `byobu` launch across this whole
debugging saga (before the theme existed, mid-iteration, and finally
after the solarpunk theme landed) left its own session sitting on the
server, each permanently rendering whatever config was live when IT was
created. Nothing was ever killing that tmux server between iterations
(never touched by me - out of scope per the "never touch real $HOME"
constraint), so 3 stale sessions had silently accumulated by the time of
the report, and `byobu-select-session` cycled through all 3 in creation
order (oldest/green -> oldest/green -> newest/solarpunk) on repeated
exits - not a "nested shells"/config bug at all.

**Fix:** since silently killing the tmux server on every `apply-dots`
activation would risk destroying unrelated real work in other sessions,
added an explicit, opt-in `byobu-reset` command instead (prompts for
confirmation, then `tmux kill-server`) - registered in the `dots-tools`
registry (`suites.tui-apps.byobu`). One-time fix for the user: run
`byobu-reset` once to clear the 3 accumulated stale sessions; from then
on, a clean `apply-dots` + `byobu-reset` after any future theme/config
tweak guarantees the very next `byobu` launch picks up the change.

**Validated:** `nix build` clean; `nix eval
.#homeConfigurations.default.config.dots.tools` confirms the new
`byobu-reset` entry renders with the expected synopsis/feature fields.

### 2026-08-01 — nixpkgs `byobu` doesn't bundle `tmux` - was silently using paru/system tmux

Caught after the previous fix: nixpkgs's `byobu` derivation does not
depend on `tmux` at all (confirmed via `nix-store -q --requisites` on the
built closure - no tmux path present) - it just execs whatever `tmux` it
finds on `$PATH` at runtime. So switching `byobu` itself to the nixpkgs
package (see the earlier "byobu reverted from alien/paru to plain
nixpkgs package" entry) left `tmux` silently falling back to the
paru/system-installed binary, defeating that decision's whole point for
this suite.

**Fix:** added `pkgs.tmux` to `tui-apps.nix`'s `appSet` under the same
`cfg.byobu` toggle (tmux is only ever used here as byobu's backend). No
alien spec exists for `tmux` anywhere in the repo (checked both
`*.cachyos-packages.nix` and `*.debian-packages.nix`), so `mkEntry` uses
the nix package on every distro.

**Validated:** `nix build` clean; `nix eval
.#homeConfigurations.default.config.home.packages` confirms
`tmux-3.7b` (nixpkgs) is now in the closure.

## 2026-08-01: Removed `noti` (per-platform notify-send wiring not worth it)

Investigated making `noti` (nixpkgs' `noti` = `codeberg.org/roble/noti`,
not the older `variadico/noti`) route to `wsl-notify-send.exe`/Windows
toast on this WSL2 host by default, alongside its existing dbus-based
behavior on Wayland hosts. Read its actual source
(`service/freedesktop/freedesktop.go`): on Linux, `noti`'s `-b`/banner
backend talks **directly to D-Bus** (`org.freedesktop.Notifications`) -
there is no `exec.Command("notify-send", ...)` anywhere in the codebase,
so there's no "just point it at a different notify-send binary" knob.
`wsl-notify-send.exe` is a standalone CLI, not a D-Bus service, so it
can't transparently answer that D-Bus call either - making this work
would require either a background D-Bus-to-`wsl-notify-send.exe` bridge
daemon (a new persistent service, non-trivial to write/maintain) or
reimplementing enough of `noti`'s process-wrapping semantics in a
WSL-specific wrapper. Given the tool was a "nice to have" convenience
(not load-bearing anywhere - `grep` confirmed zero other references in
`modules/`), decided it isn't worth either cost. Removed `noti` entirely
from `modules/core/default.nix`'s package list rather than half-fixing
it. `pkgs.libnotify`'s `notify-send` (used directly, e.g.
`modules/features/power-toggle.nix`) is unaffected - that call bypasses
`noti` entirely and works fine wherever a real notification daemon is
listening (e.g. niri/Wayland).

## 2026-07-27: byobu/tmux reachable in `nixoff` shells; `tv`; `dots-ports`

Three small, related additions in one session:

1. **`core.alwaysOnPathDirs`** (new option, `modules/core/default.nix` -
   declared there rather than `modules/core/nixon.nix`, because
   `nixon.nix` is intentionally excluded from `flake.nix`'s
   `baseModules`/gutter-eval module set, so an option only declared
   there is invisible to any `baseModules` member that tries to set it -
   confirmed via the "option does not exist" error hit mid-implementation
   until the option was moved). Lets any module register a specific
   nix-store `bin/` dir that should stay on `$PATH` in EVERY shell,
   including a fully-stripped `nixoff` shell - `modules/core/nixon.nix`'s
   `.bashrc-dots` consumes it (as a real bash array, `dir=( "a" "b" )`,
   NOT `for x in ( "a" "b" )` - the latter is a syntax error, caught via
   an isolated `env -i` runtime test). Wired up for `byobu`/`tmux` in
   `modules/suites/tui-apps.nix`, since both are nix-only packages (no
   alien spec exists for either) that would otherwise vanish entirely
   in `nixoff`. Gated on membership in `appSet.packages` (already
   alien-filtered) rather than calling `alien.hasAlien` a second time
   directly inside the option value - the latter hit a module-system
   evaluation-order issue specific to that call site (`nix eval`
   confirmed: identical `alien.hasAlien` calls succeed fine when driving
   `alien.mkEntry` inside `appSet`, but fail with "attribute 'hasAlien'
   missing" when called again directly from `core.alwaysOnPathDirs`'s
   own value) - not fully root-caused, but the `appSet.packages`
   membership check sidesteps it cleanly and is arguably more directly
   correct anyway (it's checking "is the nix package actually the one in
   `home.packages`", which is exactly what matters here).
   See `architecture.md` section 12 rule 6 for the existing nixon
   PATH-audit rule this falls under.

2. **`television` (`tv`)** - added to `modules/core/default.nix`'s
   `home.packages` (nixpkgs' `pkgs.television`, provides the `tv`
   binary). No alien spec needed/exists; plain nix package like
   `ripgrep`/`fd`/etc.

3. **`dots-ports`** - new always-installed command (`modules/core/
   scripts.nix`, registered in the `dots.tools` registry per
   `architecture.md` section 12's new rule 7 below) that lists every
   currently listening TCP/UDP socket via `ss -tulnp` (needs `iproute2`,
   now also added to `home.packages`), showing the bind interface
   (classified loopback / ALL interfaces / specific address), owning
   process+PID, and - if the process is a nix-store binary - the owning
   package (parsed from `/proc/<pid>/exe`'s store path). Sockets owned by
   other users can't be attributed without root (`ss -p`'s own
   limitation) - flagged with a `sudo dots-ports` hint instead of being
   silently dropped. Added `architecture.md` section 12 rule 7
   formalizing that every `dots-*` command needs a matching
   `dots.tools` registry entry, since this is exactly the kind of thing
   that's easy to add and forget to register (or rename and forget to
   re-register).

**Validated:** `nix build` clean for all three; `dots-ports` in
particular was smoke-tested against the real built binary (not just
`nix build` succeeding) - resolved its `.drv`'s actual output path and
ran it directly against this machine's real listening sockets, with and
without a filter argument, confirming column output and filtering both
work as intended. The `nixoff` PATH fix was verified with an isolated
`env -i HOME=/tmp/... bash` run (never touching the real `$HOME`),
confirming `byobu`/`tmux` resolve on `$PATH` while no other nix
user-profile tooling does.

## 2026-08-01: Shared Taskwarrior + Memory MCP servers (opencode/agency), via mcp-proxy not supergateway

A user-supplied "Gemini playbook" proposed deploying `supergateway` (npm)
as a systemd --user service to front Taskwarrior/Memory MCP servers over
SSE, shared between opencode and Microsoft's `agency`/GitHub Copilot CLI.
Reviewed rather than executed verbatim (per house rule: present a plan
before implementing anything design-affecting), and rejected in favor of
a different tool after concrete verification:

1. **`supergateway` was rejected.** Its full CLI arg parser (read directly
   from `src/index.ts`) has no `--host`/`--bind`/`--address` option at
   all, and its `stdioToSse.ts` calls `app.listen(port)` with no host
   argument - Node's default is to bind ALL interfaces, unconditionally.
   Confirmed this is a known, still-**open** upstream issue
   (`supercorp-ai/supergateway#125`, "Security: Bind to localhost only,
   not all interfaces"), not something a flag was missed for. The
   playbook's `--apiKey`/auth-token flag also doesn't exist in the real
   CLI (hallucinated) - the real auth flags are `--oauth2Bearer`/
   `--header`, moot anyway once the tool itself was rejected.

2. **Replaced with `pkgs.mcp-proxy`** (nixpkgs-packaged, Python,
   `sparfenyuk/mcp-proxy` upstream - NOT `stephenlacy/mcp-proxy`, the Rust
   one, which isn't in nixpkgs). Its `--host` flag defaults to
   `127.0.0.1` and it supports `--named-server-config <json>` to host
   multiple stdio MCP servers under one port at `/servers/<name>/sse` -
   one proxy instance serves both `taskwarrior` and `memory`. No auth
   token is used at all: since the proxy is loopback-only by
   construction, a bearer secret would add complexity (generation,
   storage outside the nix store, rotation) without closing any real
   attack surface.

3. **Implementation** (`modules/suites/ai-apps.nix`, all under the
   existing `suites.ai-apps` cfg, not a new top-level feature - keeps it
   co-configured with graphify/opencode as one file):
   - `systemd.user.services.mcp-proxy` (declarative Home Manager unit,
     matching `modules/features/task-sync.nix`'s precedent) -
     `ExecStart` references `${pkgs.mcp-proxy}` directly; `Environment
     PATH` is pinned to `${pkgs.nodejs}`/`${pkgs.taskwarrior3}` nix-store
     paths (for `npx` and the `task` binary `mcp-server-taskwarrior`
     shells out to), not the caller's/session's `$PATH`.
   - The backend MCP servers themselves (`mcp-server-taskwarrior`,
     `@modelcontextprotocol/server-memory`) are NOT in nixpkgs - run via
     `npx -y ...` at runtime, same accepted precedent as `setup-pi`'s
     isolated-npm-prefix install. Only the network-exposed proxy layer
     needed to be pinned/reproducible; the stdio backends don't listen on
     anything themselves.
   - `suites.ai-apps.mcpServices.enable` defaults to
     `suites.ai-apps.opencode`'s value ("enabled when opencode is
     installed", per explicit user direction) - opencode's config
     (`home.file .config/opencode/opencode.json`) always gets `mcp.
     taskwarrior`/`mcp.memory` remote (SSE) entries added when enabled.
   - Agency/Copilot registration is a **separate, manual** step via a
     new `setup-agency-mcp` script (mirroring `setup-graphify`'s
     install/update/remove shape) - explicitly requested by the user
     ("if agency support would work easier with a setup script, do it").
     It shells out to `copilot mcp add --transport sse <name> <url>` /
     `copilot mcp remove <name>` (the CLI's own sanctioned mechanism -
     confirmed via `copilot mcp add --help`), never hand-edits
     `~/.copilot/mcp-config.json` directly, since that file also holds
     live copilot-managed runtime state (tokens, trusted folders,
     session history) that must never be blindly overwritten. It's a
     clean no-op (exit 0) when `copilot` isn't on `$PATH`, since neither
     `copilot` nor `agency` are nix packages in this repo.
   - Agency itself was confirmed (via the user, and independently via
     `agency`'s own `copilot`/`cp` subcommand execing the real `copilot`
     binary) to be a thin wrapper around GitHub Copilot CLI that reads/
     writes the exact same `~/.copilot/mcp-config.json` - there is
     nothing Agency-specific left to configure once the Copilot CLI side
     is registered.

**Validated end-to-end on the real machine** (not just `nix build`):
activated via `apply-dots`, confirmed `systemctl --user status mcp-proxy`
came up with both `npx`-spawned backends running, `ss -tlnp` showed
`127.0.0.1:8765` only (never `0.0.0.0`), `curl` against
`/servers/taskwarrior/sse` returned `200 OK`, `dots-ports` correctly
surfaced the listening socket, and `setup-agency-mcp install`/`remove`
both round-tripped cleanly against the real `copilot mcp list` (including
re-running `install` twice to confirm idempotency via `copilot mcp get`
before re-adding).

**Filesystem search boundary reaffirmed during this task**: an attempted
broad `find ~ -maxdepth 3 -iname "*agency*"` search was rejected by the
user ("You DO NOT GET to search my whole filesystem!") - going forward,
only inspect specific user-named paths or a tool's own introspection
commands (e.g. `agency config list`, `copilot mcp --help`), never
speculative recursive `$HOME` searches.

## 2026-08-01: `features.notify` - cross-platform notification CLI (supersedes the abandoned `noti` wiring)

Built `features.notify` (`modules/features/notify.nix` +
`modules/features/notify/{notify.sh,toast.ps1}`), a real installed
`notify` binary (via `pkgs.writeShellScriptBin`, unlike
`features.clipboard`'s sourced bash functions - notifications are
equally useful from cron/scripts/non-bash shells). Follows the exact
`clipboard`/`opener` convention: backend resolved once from the shared
`config.core.platformBackend` (`modules/core/platform.nix`), bulk logic
lives in a static shellcheck-able `.sh` file, only a thin Nix-generated
variable preamble is inlined.

Backends: `wayland`/`x11` -> `notify-send` (libnotify, added to
`home.packages` only on those backends); `wsl` -> a Windows toast via a
`System.Windows.Forms.NotifyIcon` balloon tip, invoked through
`powershell.exe`/`pwsh.exe`; `macos` -> `osascript` (added for parity
with clipboard/opener even though not explicitly requested - not yet
confirmed wanted by the user). Feature set: `TITLE` (required),
`MESSAGE` (optional), `-u/--urgency low|normal|critical`, `-i/--icon
PATH`, `-t/--timeout MS`, `-a/--app-name NAME`.

This directly resolves the WSL-side gap left open by the
2026-08-01 "Removed `noti`" entry above - rather than trying to bridge
D-Bus `notify-send` calls to `wsl-notify-send.exe`, `features.notify`
sidesteps the problem entirely with its own backend-dispatching CLI, so
scripts/features that want a notification now call `notify` directly
instead of `notify-send`/`noti`.

Two implementation pitfalls found and fixed during validation:
1. **WSL `powershell.exe`/`pwsh.exe` resolution must not rely on bare
   name lookup** - that depends on WSL's `[interop] appendWindowsPath`
   setting (`/etc/wsl.conf`), which isn't guaranteed on every machine.
   Fixed per explicit user correction ("You are in a WSL2 box! Get it
   from /mnt/c") to a fallback chain: `pwsh.exe` via `$PATH` (opportunistic)
   -> fixed `/mnt/c/Program Files/PowerShell/7/pwsh.exe` -> guaranteed
   `/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe` ->
   bare `powershell.exe` as last resort. The `/mnt/c` drvfs mount is far
   more fundamental to WSL2 than PATH interop.
2. **Nix operator precedence bug**: `pkgs.writeShellScriptBin "notify"
   ''...'' + builtins.readFile ./notify.sh` binds `+` to the whole
   *derivation* (function application already closed), not to the text
   arg - silently produces a `home.packages` entry that's a *string*, not
   a package, only caught by `nix build`'s "is not of type `package`"
   error. Needed explicit parens: `writeShellScriptBin "notify" (''...''
   + builtins.readFile ./notify.sh)`. Worth grep'ing for this exact
   anti-pattern (`writeShellScriptBin ... '' + builtins.readFile`)
   elsewhere before assuming any prior string-concatenation-into-a-Nix-
   function-call is safe.

Title/message are base64-encoded bash-side and decoded inside
`toast.ps1` - avoids all PowerShell shell-escaping/injection concerns
for arbitrary user text (quotes, backticks, `$`, etc.) entirely, at the
cost of a slightly less readable script argument list.

**Investigated and abandoned**: making the WSL toast display `$AppName`
instead of `powershell.exe`/`pwsh.exe` as its Action Center source.
Tried registering a per-`$AppName` AUMID under
`HKCU:\Software\Classes\AppUserModelId\<aumid>` plus
`SetCurrentProcessExplicitAppUserModelID` via P/Invoke before creating
the `NotifyIcon` - live-tested on the real machine, confirmed this does
**not** work for legacy `NotifyIcon`/`Shell_NotifyIcon`-based balloon
toasts (Action Center still attributed it to PowerShell). Reliably
overriding the source requires a fully packaged/shortcut-registered app
identity (a persistent `.lnk` with an AUMID property in the Start Menu,
or the modern packaged `ToastNotificationManager` API) - explicitly
judged not worth that added complexity for a "nice to have" cosmetic
detail; `$AppName` is still shown as the tray icon's hover tooltip text.
Don't re-attempt the lightweight registry-only AUMID trick for this -
it's a dead end for this NotifyIcon-based implementation.

`modules/composition.nix`'s universal-imports comment block (previously
only mentioning `opener`/`clipboard`) was extended to include
`notify.nix`, since `modules/rules.nix` now also references
`features.notify.enable` in both its `isWsl` rule and its
`!isWsl && compositor != null` rule - same "must be declared regardless
of active context" reasoning as the existing two.

## 2026-08-01: `features.agent-instructions` - one shared instructions doc mirrored to every agentic coding tool

Built `features.agent-instructions` (default-enabled, universal import in
`composition.nix`) to answer "I need a general way to ship instructions
to each agentic coding tool" - a single canonical Markdown source,
rendered out to every tool's own global-instructions convention rather
than maintaining N separate files by hand:

- `modules/features/agent-instructions/base.md` - the shared, versioned
  (committed in `dots`) baseline content.
- `modules/local/schema.nix`'s new `agentInstructionsExtra` (`types.lines`,
  default `""`) - a private, personal addendum from `dots-local`,
  appended after the shared base under its own "## Personal addendum"
  heading when non-empty.
- `modules/features/agent-instructions.nix` concatenates the two once
  (`renderedInstructions`) and writes the identical result to:
  - `~/.copilot/copilot-instructions.md` (GitHub Copilot CLI's own
    documented global path - confirmed via the CLI's own `/env`-adjacent
    "Copilot respects instructions from these locations" listing).
  - `~/.config/opencode/AGENTS.md` (opencode's global path; opencode only
    falls back to `~/.claude/CLAUDE.md` when this one is absent, so
    writing this file directly is sufficient for opencode specifically).
  - `~/.claude/CLAUDE.md` and `~/.gemini/GEMINI.md` - written proactively
    for Claude Code/Gemini CLI even though neither is currently
    installed on this machine, so the feature's "every agentic tool"
    promise holds if either is added later without needing a config
    change.

Content drafted per explicit user direction, currently covering: get
explicit review/approval before `git commit`; get explicit
confirmation before every `git push` (a prior approval doesn't carry
over); never scan/search large parts of the disk (especially $HOME)
without asking first, especially before writing; use the shared
`server-memory` MCP for durable cross-session knowledge; use the shared
`taskwarrior` MCP tagging every task with `agent:<agent-name>
session:<session-id>`; tag `+attention` for anything needing the human's
own action/decision.

**Validated live**: `nix build` succeeded, `apply-dots` activated
cleanly, all four target paths confirmed as real Home Manager symlinks
into the Nix store with byte-identical rendered content (`diff` between
the copilot and opencode paths matched).

Follows the same "one canonical source, mirrored per-consumer" shape as
`features.notify`/`features.clipboard`'s backend-resolution pattern, and
the same `dots` (shared, versioned) + `dots-local` (private, personal)
split already used for e.g. `dotsLocal.shell.initExtra`.

## 2026-08-03: `vk` migrated from Quarto to MyST (`mystmd`) + Pandoc/Typst; Tolaria removed

Replaced `vk`'s entire Quarto-backed rendering pipeline with MyST as the
sole Markdown parser/site/document renderer, keeping Pandoc + Lua only
as a narrow, focused preprocessing step for `taskwarrior` directive
blocks - not the AI-suggested `pandoc -f markdown+myst_spec` approach,
which turned out to be infeasible: **no released Pandoc (including
current upstream) has a `myst_spec` reader**. User signed off on the
corrected architecture (MyST renders everything; Pandoc/Lua only
touches `taskwarrior` blocks) before implementation began.

**Canonical Taskwarrior syntax** (a supported MyST directive, not the
originally-suggested `::taskwarrior[...]` inline-role form):

```markdown
:::{taskwarrior} Active GQL Tasks
:project: gql-spec
:status: pending
:tags: database,gql
:limit: 5

Optional fallback text.
:::
```

**Repository-level packaging** (`flake.nix`/`flake.lock`/`dtp-tools.nix`):
removed `nixpkgs-quarto-pin` input/overlay entirely (surgically, from
`flake.lock` too - unrelated pre-existing dependency bumps left
untouched); replaced `suites.dtp-tools.quarto` with a default-enabled
`suites.dtp-tools.mystmd` (`pkgs.mystmd`) alongside the pre-existing
Pandoc/Typst entries. Also removed **Tolaria** (a GUI AppImage, unrelated
to the doc pipeline but bundled into this same cleanup at user request -
"didn't earn its keep") from `contexts/priv/appimages/manifest.nix` and
its GUI cross-default in `modules/features/appimages.nix`.

**Taskwarrior preprocessing layer** (new):
`modules/features/vk/scripts/taskwarrior_preprocess.py` finds complete
`:::{taskwarrior} ...:::` blocks in a Markdown file and rewrites *only*
those to Pandoc-native fenced `Div` syntax, piping each through
`pandoc --lua-filter=taskwarrior.lua`; every other line (any other MyST
directive/role) passes through byte-identical. The filter
(`modules/features/vk/filters/taskwarrior.lua`) queries `task export`
via `pandoc.pipe`'s argv array (never a shell string - confirmed
injection-proof live with an adversarial `project="demo; touch
/tmp/PWNED"` attribute), and renders results as a real `pandoc.Table` via
`pandoc.SimpleTable(...)` + `pandoc.utils.from_simple_table(...)` (the
naive `pandoc.Table(...)`/`pandoc.TableBody(...)` constructors aren't
directly callable in Pandoc 3.7.0.2's Lua API). Falls back gracefully
(to the directive's own body, or a generated note) on missing `task`,
query failure, malformed JSON, or an empty result.

**`vk.sh` rewrite** (`modules/features/vk.nix` / `modules/features/vk/vk.sh`):
- `_quarto.yml` → `myst.yml` (book-theme site, folder-preserving URLs,
  explicit Materials/Records/Texts TOC sections via `pattern` globs).
- Wikilinks (`[[file.md|Title]]`) → native Markdown links
  (`[Title](file.md)`) in generated category indexes; `wikilinks.lua`
  removed (MyST doesn't support Pandoc AST filters or that syntax).
- Quarto's `{{< include main.md >}}` → MyST's native `{include}`
  directive.
- New **disposable per-vault staging tree** (`stage_vault()`): copies
  ordinary files unchanged, routes only taskwarrior-tainted `.md` files
  through the Python preprocessor + Lua filter first; every write is
  `cmp -s`-guarded (no spurious mtime bumps, so MyST's own incremental
  build cache still helps).
- New frontmatter on authored notes: stable `id`
  (`category-type-slug`), `tags` (derived from category+type),
  alongside existing `title`/`type`/`date`. `exports:` stays opt-in.
- New **`vk export [vault] [file] --format pdf|typst`** command: forces
  a Typst export via `myst build --ci --force --typst`, then locates the
  produced PDF/`.typ` bundle by **newest-file-since-a-timestamp-mark**
  rather than by expected basename - MyST silently slugifies output
  filenames (`with_tasks.md` → `with-tasks.pdf`), so a naive
  `find -name "${BASE}.pdf"` glob misses the real output (**a real bug
  caught and fixed during live testing**, not a hypothetical).
- **`vk watch` no longer uses `dufs`.** Live-tested finding: `myst build
  --html --watch` does **not** actually watch/rebuild on change - MyST
  itself prints "Site content will not be watched and updated; use
  'myst start' instead" - so the old `dufs`-fronting-a-directory design
  (which also raced dufs' own start against a `_build/html` directory
  that might not exist yet) was replaced with MyST's own dev server
  (`myst start --keep-host --port $PORT --server-port $((PORT+1))`).
  Also live-confirmed that `--headless` mode (content-server only)
  serves **stale** content after an edit even though the rebuild
  genuinely happens on disk - only the full two-server mode (app server
  + content server) propagates live-reloaded content correctly. `HOST`
  (an env var, not a CLI flag) is what actually controls bind address,
  and is silently forced back to `localhost` unless `--keep-host` is
  also passed - loopback-by-default, same contract as dufs elsewhere in
  `vk`. A lightweight 1s-poll background loop re-runs `stage_vault()`
  during `watch` so edits to the *real* note (not MyST's own staged
  copy, which is what its watcher actually sees) still show up live.
- `vk build`/`vk serve-all` still use plain `myst build --html` (a real,
  natural-exit static build, confirmed live via `time (...)` - resolved
  the open question from planning about whether it hangs like a server;
  it doesn't, absent `--watch`) plus `dufs` for static serving -
  unaffected by the `watch`-specific bug above.

**Live migration**: `$HOME/Vaults` (root hub + the single `az` vault)
converted in place - `_quarto.yml`/`wikilinks.lua`/`_extensions/
taskwarrior`/`.quarto/`/`_site/`/`index_files/` removed, `myst.yml`
written, wikilinks and the Quarto include shortcode converted, note
frontmatter normalized (`id`/`tags` added, existing `title`/`type`/`date`
preserved) - all **left uncommitted** in `az`'s own git repo for manual
review; the root `Vaults/` directory itself was never a git repo, so
there's nothing to commit/review there beyond the files on disk.

**Validated**: `nix flake check` + full
`homeConfigurations.default.activationPackage` build (twice - once after
the packaging cleanup, again after the full `vk.sh` rewrite); `shellcheck`
clean (only pre-existing info-level `SC2016`/`SC2153` notices); live
smoke tests of every subcommand (`new`, `note`'s `write_note`, `rename`,
`build`, `watch`'s new `myst start`-based live-reload - confirmed an edit
to a real note appears in the served page within seconds, `export` in
both `pdf` and `typst` formats, `serve-all`'s root-hub build + per-vault
symlinking, served end-to-end through `dufs`) against a disposable
fixture vault, then a real build of the migrated `az` vault itself
(all pages built 200, including filenames containing spaces, the
Taskwarrior table, and the `main.md` include). Confirmed `watch`
(MyST's own dev server) and `build`/`serve-all` (`dufs`) both still bind
`127.0.0.1` by default. `dots-ports` needed no code change to see either
- it's a generic, live `ss`-based listening-socket enumerator with no
per-app hardcoding.

### 2026-08-03: fixed `vk serve-all` navigation crash (missing per-vault `BASE_URL`)

Live usage after the migration surfaced a bug the original validation
pass missed (it only `curl`'d a fixture vault's root, never clicked a
hub → vault link in an actual browser): navigating from the `serve-all`
hub page into a vault (e.g. `az`) threw `TypeError: Cannot read
properties of undefined (reading 'handle')` in MyST's bundled React
Router client code.

**Root cause**: each vault is built as its own fully independent MyST
site (own `myst build --html`, assuming it will be served from `/`), and
`serve_all_rebuild()` just symlinks that output under
`_build/html/<vault-name>/` so `dufs` can serve every vault from one
static root. Without telling MyST it will actually be served from
`/<vault-name>/`, every asset/route href it emits stays absolute-rooted
(`/build/entry.client-HASH.js`, `/build/_shared/chunk-*.js`, ...).
Reproduced directly: fetching `/<vault>/build/entry.client-HASH.js`
resolved to the **hub's own** client bundle (different build, different
route manifest hash) instead of the vault's - the hub's JS then tried to
hydrate/route against the vault's page content, and its route-matches
array (`useMatches()`-style hook, confirmed by grepping the exact
`chunk-AQ2CODAG.js` bytes from the user's stack trace) contained an
entry with no corresponding loaded route module, so `.handle` read
`undefined`.

**Fix**: MyST has no `--base-url` build flag but does honor a `BASE_URL`
**environment variable** at build time (confirmed live: with
`BASE_URL=/demo`, every emitted href becomes `/demo/build/...`).
`myst_build()` in `vk.sh` now takes an explicit base-url as its 2nd
positional arg - `""` for a standalone build (`vk build`/`vk watch`,
served from `/`) or `"/<vault-name>"` when `serve_all_rebuild()` builds
a vault for the shared hub. The chosen base-url is recorded in a
`.vk-staging/_build/.base_url` marker file; `vault_needs_build()` now
takes the same expected base-url and forces a rebuild on mismatch (not
just on a stale mtime) - necessary because a vault previously built
standalone (or vice versa) has baked-in asset paths that are silently
wrong for the other context, and a plain mtime check would never catch
that since no *source* file changed.

Validated live end-to-end (not just `curl`, this time): copied the real
`az` vault into a scratch dir, ran `serve-all`, and confirmed
`/az/build/entry.client-*.js` now resolves to the vault's own bundle
(200, matching hash referenced by `/az/`'s own `index.html`) rather than
colliding with the hub's `/build/...` path, while a plain standalone
`vk build az` still emits root-relative (`/build/...`) hrefs as before.

**Learning captured for future multi-site-composition work**: never
assume a client-rendered SPA's static build output is relocatable by
symlink/reverse-proxy alone - check for a base-path build-time
environment variable/config option before assuming path-nesting "just
works", and validate by actually following the emitted bundle hrefs at
the real serving path, not just confirming the top-level page loads.

### 2026-08-03: fixed unrendered category-listing links (unencoded spaces in link destinations)

Reported live: notes with a space in their filename (e.g. "Agentic
Coding Tools.md") showed up in a category listing page (`texts/index.md`
etc.) as literal unrendered text - `[Agentic Coding Tools](Agentic
Coding Tools.md)` - instead of a clickable link. Root cause:
`regen_category_index()` built each link's destination directly from
`basename "$f"`, and a bare (non-`<...>`-wrapped) CommonMark/MyST link
destination containing a literal space is invalid syntax - it gets
parsed as plain text, not a link. Confirmed via the built page's own
AST (`_build/html/index-N.json`'s `mdast`): before the fix the note's
entry was a bare `text` node containing the raw `[Title](file.md)`
string; after the fix it's a proper `link` node with a resolved `url`.

**Fix**: added a small `url_encode_path()` helper (percent-encodes
space/`#`/`?` - the characters that would otherwise break or
misdirect a bare link destination - while leaving `/` path separators
alone) and ran every generated link destination through it: category
listings (`regen_category_index()`), the serve-all hub's per-vault
links, and its global-page links - all three build a link destination
directly from a filename/vault name, so all three had the same latent
bug even though only the category-listing case had been hit in
practice so far.

**Investigated but NOT a bug**: the user also reported `serve-all`'s
`/az/index-1`-style category pages (MyST auto-numbers colliding
`index` slugs from `materials/index.md`/`records/index.md`/
`texts/index.md` all sharing the base name `index`) as slow to load.
Traced this as far as: (a) every asset actually referenced by the
page's HTML shell resolves in single-digit milliseconds locally, (b)
the ~100+ `NNNN.thebe-core.min.js` chunk files present in every MyST
book-theme build (Jupyter/Thebe in-browser code execution runtime -
unneeded for a plain-notes Zettelkasten) are not referenced anywhere in
the initial page shell or its route JSON, so they're not being eagerly
fetched, and (c) `site.thebe: false` is rejected by this pinned mystmd
1.9.1's config schema ("cannot include reserved key thebe") - a known
mystmd regression reverted only in 1.10.1 (changelog: "Revert thebe
#2903"), which nixpkgs hasn't picked up yet as of this writing. Could
not reproduce actual slowness against the local static build in this
session; most likely explanation is the inherent ~10-25s `myst build
--html` time per vault during `serve-all`'s startup/rebuild-on-change
window (already noted in the original migration's learnings entry), not
a distinct bug. Also checked while investigating: the per-page
prev/next footer navigation metadata in `index.json` (`footer.navigation
.{prev,next}.url`) stays root-relative (e.g. `/page2`) even with
`BASE_URL` set at build time - but the *rendered* sidebar/TOC `<a href>`
tags are correctly prefixed either way, so this is presumed to be
handled transparently by the client router's own `basename` config
(consistent with `serve-all` working end-to-end in the live BASE_URL
fix validated earlier today) rather than a live bug - flagged here in
case a future report ties back to it.

**Learning for next mystmd bump**: revisit `site.thebe: false` (or
whatever 1.10.1+'s equivalent option is) once nixpkgs's `mystmd`
package updates past 1.10.1 - it should let vk-managed vaults opt out
of bundling the unused Thebe/Jupyter runtime chunks entirely, trimming
every vault's `_build/html` output significantly.

## 2026-08-03: `serve-all` "not found on first/second load" is WSL2 localhost-forwarding lag, not a vk bug

Follow-up on the same-day `index-1` slowness report: the user clarified
the actual symptom is a literal "not found" on the first one or two
page loads right after `vk serve-all` starts, requiring a reload -
not just perceived slowness.

Re-investigated with a controlled cold start: wiped `az`'s and the
root's `_build`/`.vk-staging`, launched a fresh `vk serve-all` on a
scratch port, waited for the exact "Listening on" log line, then
curled the vault path five times in a tight loop immediately after -
all five returned `200` in ~2ms, every time. Also re-tested directly
against the user's own long-running `serve-all` process (started well
after the BASE_URL/link-encoding fixes were deployed) with the same
result: consistently `200`, no reproducible server-side 404 at any
point after "Listening on" prints.

Root cause is therefore almost certainly **WSL2's localhost-forwarding
relay**, not `vk`/`dufs`/MyST: this box uses WSL2 NAT networking
(confirmed via `/etc/wsl.conf`, no `networkingMode=mirrored`), where
Windows-side access to `127.0.0.1:<port>` is relayed into the WSL VM by
a per-port `wslrelay.exe` process spawned on demand. That relay has a
well-known startup race - when a socket has *just* started listening
inside WSL, the very first connection attempt(s) from the Windows side
can arrive before the relay has finished wiring up, failing or timing
out, while a reload a moment later succeeds once the relay has caught
up. This matches the reported pattern exactly (first/second load fails,
then works) and is invisible to any test run from inside WSL itself
(curl from the Linux side bypasses the relay entirely), which is why
this session's repeated in-VM curl tests never reproduced it.

This is a Windows/WSL2 networking behavior outside `vk`'s control, not
a fixable code bug. Practical mitigations (not implemented, since they
are environment/user choices rather than repo changes):
- Wait a couple of seconds after `vk serve-all` prints "Listening on"
  before loading the page in the Windows browser.
- Switch WSL2 to mirrored networking mode (`networkingMode=mirrored`
  in `%UserProfile%\.wslconfig`, Windows 11 22H2+) - this removes the
  relay/NAT layer entirely, eliminating the race.

## 2026-08-04: vk enhancement session decisions

- **Cross-vault relative-link rewriting on rename/move**: since all vk
  vaults are always immediate sibling subdirectories of one
  `$VAULTS_DIR` (confirmed via `vk.sh`'s `list_vaults()`), a relative
  link from vault A to a note/asset in vault B (e.g.
  `../other-vault/materials/note.md`) is valid and must be kept correct
  across a rename/move. `note_rename.py` was generalized to do all
  matching/rewriting in absolute-filesystem-path space internally (via
  `os.path.normpath`), scanning *every* sibling vault's `.md` files, but
  always writes back a relative path (`os.path.relpath` between two
  absolute paths) - so no `$HOME`/absolute path ever leaks into vault
  content or generated URLs.
- **Rename/Move generalized to any file, not just notes**: `.md` files
  go through `_move_note()` (preserves `id`, adds an alias entry for the
  old path); any other file (image, asset) is a plain `shutil.move()`.
  Both paths share the same link-rewriting pass, including image embeds
  and `{doc}` roles - conceptually a single "file move" operation.
  Wired into `vk note`'s menu as "Rename/Move File", with the file
  picker broadened to include `assets/`.
- **Bibentry import uses native MyST/Pandoc citations**: pasting a
  BibTeX entry now (1) parses its citekey, (2) rejects it if that key
  already exists in the vault's `references.bib`, (3) appends the raw
  entry to `references.bib` (created on first use if missing - older
  vaults predate `vk new` seeding an empty one), and (4) inserts a
  native `[@citekey]` citation as the note's primary content, instead of
  the old hand-formatted citation string. `vk new` now seeds an empty
  `references.bib` per vault.
- **`vk check [vault|all] [--external]`**: new command that stages a
  vault, runs `myst build --ci --strict --html` (+`--check-links` under
  `--external`), then runs `vault_check.py`'s static/offline checks
  (frontmatter shape, links, assets, directives, Graphviz DOT),
  aggregating pass/fail per vault (and overall, for `all`) with correct
  exit codes. Must never disturb a vault's existing `_build` cache (see
  learnings.md for the backup/restore fix and why it's needed).
