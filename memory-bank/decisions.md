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
