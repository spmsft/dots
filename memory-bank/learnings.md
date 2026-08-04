# Learnings

Running log of gotchas, Nix quirks, and things discovered while executing.
Append as you go — newest at the bottom.

---

### 2026-07-18 — Initial inventory findings
- `psutils` (in `modules/core/default.nix`) is **PostScript document
  utilities** (psnup/psselect), not process utilities — confirmed via
  `nix eval .#homeConfigurations.priv.pkgs.psutils.meta.description`. The
  inline comment ("psutils # psutils") is unhelpful and likely reflects a
  misunderstanding at the time it was added.
- `t3` is actually **"next generation tee with colorized output streams and
  precise time stamping"** — confirmed via the same technique. The inline
  comment ("Tree-like utility") is simply wrong; it has nothing to do with
  `tree`.
- General technique: `nix eval .#homeConfigurations.<profile>.pkgs.<name>.meta.description
  --override-input dots-local git+file://$HOME/dots-local` is a quick way to
  check what a package actually is without a full build.
- `chromaden.nix`'s `programs.ssh.matchBlocks` usage triggers a Home Manager
  deprecation warning (`Use programs.ssh.settings`) during `nix eval` — a
  live, currently-harmless warning worth fixing opportunistically in
  Phase 0.
- Two independently-implemented alien-package discovery engines already
  exist (`modules/flake/alien-package-specs.nix` vs
  `modules/core/alien-packages.nix`) — confirmed both scan
  `modules/**/*.<distro>-packages.nix` with near-identical code, a real
  duplication (not just superficially similar).
- Confirmed via `git branch -a`/`git remote -v` in `dots`: two remotes exist
  today (`origin` = `boggle/dots`, `other` = `spmsft/dots`), single shared
  `main` branch, with history showing an explicit merge-conflict resolution
  between them (`ai-apps.cachyos-packages.nix`) — concrete evidence of the
  pain point motivating this whole project.
- `dots-local` (private repo) is a separate git repo (not a branch of
  `dots`), currently on `master`, no extra remotes configured locally.

### 2026-07-18 — Actual current shell-bootstrap mechanics (corrected)
Initially assumed `nixon.nix` directly force-writes the real
`~/.bashrc`/`~/.profile` with no separation from the pure Nix output. Wrong
— investigating the live system (`ls -la ~/.bashrc*`, reading `nixon.nix` in
full) showed the real current state:
- `~/.bashrc-nix` / `~/.profile-nix` — pure gutter-eval HM output
  (`home.file.".bashrc-nix".source = bashrcDerivation;` etc.) — **already**
  a separate, correctly-named file. This is why the user already has a
  `.bashrc-nix` and a new phase-6 suffix had to avoid colliding with it.
- `~/.bashrc` / `~/.profile` — **also** `home.file`-managed
  (`lib.mkForce`'d), but contain a hand-authored "NIXON gatekeeper" hybrid
  script (toggle NIXON on/off via `nixon`/`nixoff` aliases, sources
  `.bashrc-nix` conditionally when `NIXON=1`, otherwise strips `/nix` from
  PATH for a "pure host" mode). This is the file that still needs to stop
  being force-owned by Nix per the original ask.
- `~/.bashrc-core` (hyphen) is a real, non-Nix-managed file on disk
  containing `QT_QPA_PLATFORMTHEME`/`GTK_THEME` exports — but `nixon.nix`'s
  gatekeeper script sources `~/.bashrc_core` (underscore!) — a naming
  mismatch bug, confirmed via `grep`, meaning this file is currently
  silently never loaded. `~/.profile-core` (hyphen) has no such bug (the
  profile hybrid correctly references it with a hyphen), it's just that no
  such file currently exists on disk.
- Lesson: always inspect the live filesystem state before proposing a
  rename/retarget scheme for dotfiles-adjacent mechanisms — the abstract
  code-reading-only inventory missed this nuance initially.

### 2026-07-18 — laputa.nix was completely broken, not "silently non-functional"
The original inventory guessed the `features.scanning` vs `suites.scanning`
typo was "likely silently broken" on laputa. Verified via an actual `nix
eval` (using a temp copy of `dots-local` with `host = "laputa"` swapped in,
`--override-input dots-local git+file://...`) that it was in fact a **hard
eval error** ("The option `features.scanning' does not exist"), meaning
`apply-dots`/`nix eval .#homeConfigurations.priv` has never succeeded for
laputa in this form. Fixing that one typo uncovered a second, worse bug:
`profiles/priv/home.nix` unconditionally sets `suites.ai-apps.*` for every
priv host, but `modules/suites/ai-apps.nix` was only imported by
`chromaden.nix` and `triomino.nix` individually, not at the profile level —
so laputa also failed with "The option `suites.ai-apps' does not exist"
right after the scanning fix. Fixed by importing `ai-apps.nix` at the
profile level (`profiles/priv/home.nix`) and removing the now-redundant
per-host imports from chromaden.nix/triomino.nix. A third bug surfaced
after that: `network.nix` sets `programs.ssh.extraConfig` +
`enableDefaultConfig = false`, which (in the current Home Manager version)
asserts that `programs.ssh.settings."*"` must be declared — chromaden and
triomino both declare an ssh identity block (via the now-deprecated
`matchBlocks."*"`) but laputa had no `programs.ssh` block at all. Added one
(`~/.ssh/id_github_laputa`, matching the established per-host convention)
using the modern `programs.ssh.settings."*"` key (PascalCase:
`IdentityFile`/`AddKeysToAgent`), and took the opportunity to migrate
chromaden.nix/triomino.nix off the deprecated `matchBlocks` to the same
`settings` form while fixing their copy-pasted "Laputa Machine
Configuration" header comments.
- **Technique note:** to test a specific host's config without touching the
  real `dots-local`, copy it to a scratch dir
  (`cp -r ~/dots-local /tmp/opencode/dots-local-<host>-test`), sed the
  `host = "...";` line, commit (it's a git flake input, needs a commit to be
  read), then `nix eval .#homeConfigurations.priv.config.home.username
  --override-input dots-local git+file:///tmp/opencode/dots-local-<host>-test`.
  Cheap and safe way to validate all three hosts without a live switch.
- **Implication for Phase 2 (composition redesign):** this whole class of
  bug (a host silently missing an import that another part of the config
  assumes is present) is exactly what the axis/rule-driven composition
  model is meant to eliminate — worth using as a concrete before/after
  example when documenting the migration.

### 2026-07-18 — CRITICAL: untracked new files are invisible to `nix eval`/flakes
When creating `modules/features/llama-cpp.cachyos-packages.nix` (a brand
new file, via the `write` tool), every `nix eval`/`nix build` I ran against
it appeared to succeed and "validate" the fix - but the file was **git
untracked** (`git status` showed `??`), and Nix flakes evaluated from a
local git working tree only see **git-tracked (or at least staged) files**.
Untracked files are silently invisible to the evaluation, with no
warning/error - the fold over discovered spec files just acts as if the new
file doesn't exist, and any package names that used to be defined in the
old location (which I'd already removed those entries from) simply
vanish from `rawAlienSpecs` entirely. Concretely this meant `cuda-llama`,
`vulkan-llama`, `gcc15`, `gcc15-libs` were **not being tracked as required
by anything** for a period - worse than the original bug (where at least
`cuda-llama`/`vulkan-llama` worked, just missing `gcc15`/`gcc15-libs`) -
despite every eval/build I ran claiming success, because none of those
checks would ever exercise the "does this file get discovered" path in a
way that surfaces the gap (a missing key just silently contributes zero
packages, no error).
- **Root cause confirmed** by writing a standalone probe script
  (`nix eval --file` against a plain filesystem path, bypassing flakes'
  git-tracking entirely) which DID find the file/keys correctly - proving
  the discovery logic itself was fine and the issue was purely
  flakes-vs-git-tracking.
- **Fix:** `git add` the new file. After staging, `nix eval
  '.#homeConfigurations.priv.config.home.file."...".text'` correctly showed
  `cuda`/`gcc15`/`gcc15-libs`/`vulkan-*` in the required set.
- **Standing operating procedure for the rest of this project:** run
  `git add <newfile>` **immediately** after creating any new file with the
  `write` tool, before considering any `nix eval`/`nix build` against it a
  real validation. This will come up repeatedly in later phases (schema.nix,
  composition.nix, rules.nix, template.nix, externalized
  scripts in Phase 8, etc.) - each is a new file and each needs this same
  discipline. Consider running `git add -A` (or targeted `git add`) as a
  standard first step whenever a phase's work includes new files, before
  any validation step.
- Silver lining: this doesn't affect *modifications* to already-tracked
  files (only brand-new untracked files are invisible), so most of Phase
  0's other fixes were validated correctly.

### 2026-07-18 — Phase 1 (dots-local schema) implementation gotchas
Several real Nix/evalModules quirks surfaced while wiring up
`modules/local/schema.nix` into `flake.nix`:

1. **A flake input can't be passed bare into `lib.evalModules`'s `modules`
   list.** `inputs.dots-local` isn't just the plain data attrset dots-local's
   `outputs` function returns - Nix attaches hidden introspection/metadata
   attributes to it (`_type = "flake"`, `inputs`, `outPath`, `outputs`,
   `rev`, `sourceInfo`, `lastModified`, ...). Passed directly, evalModules
   errors with "Expected a module, but found a value of type 'flake'."
   Fixed by wrapping as `{ config = dotsLocalData; }` (making the intent
   explicit) AND stripping the metadata attrs first via
   `builtins.removeAttrs` (otherwise each metadata attr fails independently
   as "The option `_type'/`outPath'/etc does not exist", since evalModules
   validates every config key against declared options).
2. **Dirty git state adds MORE metadata attrs.** When `dots-local` itself
   has uncommitted changes, Nix additionally attaches `dirtyRev` and
   `dirtyShortRev` - discovered when fixing an unrelated typo in the real
   `dots-local/appimages.nix` (`dektopName` -> `desktopName`) without
   committing it first, which immediately broke the eval with "The option
   `dirtyRev' does not exist." Both clean and dirty states needed handling
   since editing dots-local without committing is explicitly a supported,
   expected workflow (per AGENTS.md's Nix Evaluation section).
3. **`option or default` only helps for a *missing* attribute, not a
   *present-but-null* one - and schema-validated submodules make previously
   "missing" fields always-present.** `modules/features/appimages.nix`'s
   `mkSharedWrapper`/`mkHostLocalWrapper` used `app.desktopName or name` and
   `app.categories or [ "Utility" ]` to provide fallbacks. Once
   `dotsLocal.appimages` became a schema-typed submodule (with
   `desktopName` defaulting to `null` and `categories` defaulting to `[]`),
   those keys are now ALWAYS present on every entry - so `or` never
   triggers anymore, and a `null`/`[]` value flows straight through into
   `pkgs.makeDesktopItem`, causing "cannot coerce null to a string: null"
   deep inside the `home-manager-generation` derivation's build (NOT caught
   by a plain `nix eval .#homeConfigurations.priv.config.home.username` -
   only surfaced when building the full `activationPackage`, since that's
   what actually forces evaluation of the desktop-item derivations). Fixed
   with an explicit `if (app.field or null) != null then app.field else
   default` pattern, which correctly handles both origins (schema-typed
   host-local apps AND raw, non-schema-validated shared-manifest imports
   that might genuinely be missing the key).
   - **Process lesson**: `nix eval .#homeConfigurations.<x>.config.home.username`
     (or similar shallow attribute reads) is a fast sanity check but does
     NOT force evaluation of most derivations (packages, activation
     scripts, desktop items, etc.) - it only proves the *module system*
     resolves without error. A full `nix build
     .#homeConfigurations.<x>.config.home.activationPackage` (and/or
     `config.home.path`) is necessary to catch errors that only manifest
     when derivations are actually forced. Use both: cheap eval first for
     fast iteration, full build before considering a phase done.
4. **The exact same `dots-local.march` "znver5" vs "native" default
   inconsistency flagged during the original inventory was real and is now
   fixed** - see decisions.md. Also fixed a related, previously-undiscovered
   bug in the same area: the `-opt` profile build hardcoded
   `gcc.arch = "znver5"` directly in `flake.nix`, ignoring
   `dotsLocal.march` entirely (would have silently built for the wrong
   microarchitecture on any non-znver5 machine using `apply-dots <profile>-opt`).

### 2026-07-18 — Phase 2 (composition layer) implementation gotchas
1. **A rule's `when` predicate being a function of `dotsLocal` does NOT
   mean its `set` output automatically is too.** First draft of
   `rules.nix` had `{ when = d: ...; set = { ... d.machine.terminal ... }; }`
   - `set` here is evaluated once when the list is constructed, with `d`
   completely out of scope (only `when`'s lambda parameter is named `d`).
   Got "undefined variable 'd'" immediately on eval. Fixed by making `set`
   a function too (`set = d: {...};`), called as `rule.set dotsLocal` in
   `composition.nix`'s fold.
2. **`lib.mkDefault` applied to an entire nested attrset does NOT give
   correct per-leaf priority semantics.** `lib.mkDefault { features.foo.bar
   = true; features.foo.baz = "x"; }` wraps the WHOLE tree as a single
   low-priority definition rather than tagging each leaf - the module
   system's priority resolution operates per final option path, not per
   "chunk of config a module happened to return." Needed a small recursive
   `deepMkDefault` helper (walks nested attrsets, applies `lib.mkDefault`
   only at non-attrset leaves, skipping anything already tagged with a
   module-system `_type` to avoid double-wrapping/corrupting an existing
   override annotation) to make rules.nix's `set` attrsets
   behave as real per-option defaults.
3. **Every feature module a per-host file used to import must become a
   *universal* import once that host file is retired.** Composition-rules.nix
   referencing `features.llama-cpp.enable` etc. as an *option* isn't enough
   if the module declaring that option was only ever imported by the
   specific host file being deleted - "The option `features.llama-cpp' does
   not exist" (a real eval error, not a silent no-op) resulted until
   `niri-noctalia.nix`/`llama-cpp.nix`/`butterfish.nix`/`sd-switch.nix`/
   `scanning.nix` were added to `composition.nix`'s universal imports list
   (matching the existing convention every other feature file already
   uses: import unconditionally, gate everything behind the module's own
   `enable` option).
4. **Validation technique for hosts this session can't directly reach**
   (laputa, triomino - separate private dots-local repos on other
   machines): built synthetic `dots-local` copies in scratch directories
   mimicking exactly what each real machine's dots-local would need to
   contain post-migration (same technique as Phase 0's host-swap testing,
   extended to include the new axis fields), ran full `nix eval` +
   `nix build .../activationPackage` against each, and spot-checked
   resolved config values against the original host file's intent
   (e.g. confirmed triomino's `piPackages` resolves to the same 13-entry
   list via inheritance from `contexts/priv.nix`, without needing to
   duplicate it - fixing a previously-flagged bug as a side effect).
   This is eval/build-level confidence only, not a substitute for an
   actual live `apply-dots` on those machines - documented clearly in
   `host-migration-phase2.md` as still-required follow-up.
6. **Renaming flake outputs breaks the currently-installed wrapper script
   that references the old name, until one manual bootstrap switch fixes
   it.** After committing the `priv`/`work`/`priv-opt`/`work-opt` ->
   `default`/`default-opt` rename, running the (still old, not yet
   regenerated) installed `apply-dots` failed with "Explicitly specified
   home-manager configuration not found:
   .../dots#homeConfigurations.priv" - expected, since `apply-dots` itself
   is a Home Manager-managed package that only gets regenerated by a
   successful switch, and the currently-installed one still built its
   flake-output name from `dots-local`'s `profile` field (the old
   convention). Fixed with one direct, manual invocation bypassing the
   wrapper: `nh home switch ~/dots -c default -- --override-input
   dots-local git+file://$HOME/dots-local`. Confirmed after the fact that
   the resulting generation's store path matched byte-for-byte what had
   already been validated via `nix build` during the phase - strong
   confirmation the eval/build validation this session relies on
   (necessarily, since it can't run `apply-dots` itself against the live
   system) really does predict the live outcome exactly.
7. **A cosmetic warning can look alarming out of context - always verify
   with hard evidence, not just reassurance, when a user flags something as
   "seriously worried."** The `noctalia-qs` "has an override for a
   non-existent input" warning printed again during the live switch,
   prompting a direct worry about lost inputs/overlays. Rather than just
   repeating "it's fine, we discussed this," re-verified from scratch:
   `git log -p` showing the exact override line unchanged across the
   session's entire commit history, `nix flake metadata` showing all 10
   inputs still locked, and `nix eval` spot-checks of every
   overlay-provided package (snippets-ls/bookokrat/quarkdown/quarto/pandoc/
   niri) resolving correctly. Found and disclosed one genuine (but
   pre-existing, unrelated to this session) discrepancy along the way:
   `pandoc` resolves to `3.7.0.2`, not the `3.1.11.1` the flake's own
   comment claims - confirmed via `git log -p` that the overlay code
   itself is byte-identical to before this session touched anything, so
   the comment was already stale/inaccurate beforehand.

9. **A rules.nix rule referencing an option makes that
   option's module a hard, universal dependency - discovered a real gap
   this way.** Testing with `profile = "work"` + `isWsl = true` for the
   first time (previously every synthetic test used `profile = "priv"`)
   surfaced "The option `features.clipboard' does not exist" /
   "The option `suites.ai-apps' does not exist" - `rules.nix`'s
   `isWsl` rule references `features.opener`/`features.clipboard`, and the
   `gpu == "nvidia"` rule references `suites.ai-apps`, but those modules
   were only imported by `contexts/priv.nix`, not universally. A `lib.mkIf`
   with a `false` condition still requires the option path to be *declared*
   somewhere (module imported) - it just doesn't set a value; NixOS/HM's
   module system validates declared-vs-defined independently of whether a
   conditional actually fires. Fixed by moving `opener.nix`/`clipboard.nix`/
   `ai-apps.nix` to `composition.nix`'s universal imports list (same
   pattern as niri-noctalia/llama-cpp/cloud-tools), keeping their
   `enable`/config assignments in `contexts/priv.nix` (context-specific)
   while making the underlying options always declared. General lesson:
   any option rules.nix references must have its declaring
   module universally imported - a good thing to audit whenever a new rule
   is added, and a strong argument for testing every context (not just the
   one that happens to be live-checkpointed) with synthetic dots-local
   copies before considering a phase done.

10. **Phase 4 (`mkAppSet`) validation technique: `git stash`/`git stash pop`
    around a single `nix eval` each side, diffing the FULL resolved
    `config.home.packages` + `config.alienPackages.enabledPackages`, not
    per-suite.** Rather than running 9 separate before/after diffs (one
    per migrated file), stashed all uncommitted changes at once, captured
    the fully-original resolved package lists (sorted, JSON) for the whole
    config, popped the stash back, captured again, diffed. Two diffs total
    instead of nine, and it incidentally catches cross-suite interactions
    too (e.g. if migrating one file accidentally affected another's
    resolution via shared state). Both diffs were empty (byte-identical),
    giving full confidence across all 9 files' migrations in one step.

11. **Phase 5 (tuning unification): a real per-machine override can make a
    "risky-looking" table drift completely irrelevant in practice.**
    Before unifying `tune-support.nix`'s and `package-tuning.nix`'s
    duplicated/drifted default-flags tables, reasoned (correctly, in the
    end) that chromaden's actual usage (ripgrep/fd in rust "default"/
    "fast" mode, ghostty in c "default" mode) wouldn't be affected since
    those specific mode/lang combinations were already identical between
    the two tables - only c/c++ "fast" mode (missing `-ffast-math` in one
    copy) and go/haskell (missing entirely in one copy) actually differed.
    Empirical verification then revealed an even simpler reason those
    packages were safe: chromaden's real `dots-local/flake.nix` already
    sets an explicit `tune.flags.c.fast` override, which
    unconditionally wins over EITHER module's built-in default table via
    `dotsLocal.tune.flags.${lang}.${mode} or defaults.${lang}.${mode}` -
    so the drift between the two built-in tables was moot for this
    specific package/mode regardless. Lesson: when assessing whether a
    "shared defaults" refactor is safe, check for real per-machine
    overrides that might already be masking the drift, not just the
    apparent diff between the two default tables in isolation - and
    verify with an actual before/after `nix eval` of the resolved values,
    not just code-reading confidence.

13. **Phase 6 (shell bootstrap retarget): isolated bash-logic sandbox
    testing is a good substitute for "can I fully live-test this without
    touching the real system", but has a specific limit worth naming.**
    Tested the new `ensureDotsShellHook` activation script's actual bash
    logic (not the whole activation script) against fake `$HOME`
    directories with `HOME=/tmp/... bash -c '...'` - confirmed
    idempotency (3 repeated runs produce zero duplication), non-
    destructiveness (pre-existing `.bashrc`/`.profile` content untouched,
    source line correctly appended), and fresh-bootstrap behavior (file
    created from scratch when absent). This gives strong confidence in
    the hook's *own* logic. What it can NOT verify: whether Home Manager
    correctly unlinks the OLD, previously-force-owned `.bashrc`/`.profile`
    symlinks during the actual transition from a pre-Phase-6 generation to
    this one - that's standard HM behavior for any removed `home.file`
    declaration, but simulating it properly would require an actual
    generation transition, which only a real `apply-dots` switch provides.
    General lesson: sandbox-testing extracted logic is valuable and worth
    doing before a risky live change, but be precise about what it does
    and doesn't cover when reporting confidence to the user - don't let
    "I tested it in a sandbox" imply more coverage than it actually has.

14. **CRITICAL, learned from a real live failure: removing a `home.file`
    declaration is NOT the same as disabling it, when another module
    ALSO declares the same path.** Phase 6's first live attempt failed
    with `Permission denied` writing to `~/.bashrc`. Root cause:
    `nixon.nix` previously `lib.mkForce`'d `home.file.".bashrc"`, which
    won over Home Manager's own **built-in** `programs.bash` module
    (independent of `nixon.nix`, enabled via `programs.bash.enable =
    true`) - that HM module *also* declares `home.file.".bashrc"` itself.
    Simply *removing* `nixon.nix`'s own declaration (rather than
    disabling the option) let HM's built-in declaration become
    uncontested and reclaim the path, symlinking it back into the
    read-only Nix store - so the new activation hook's `>> $HOME/.bashrc`
    append failed with EACCES.
    - Earlier isolated sandbox tests (fake `$HOME`, just the hook's bash
      logic) could not have caught this - they never had `programs.bash`'s
      competing declaration in scope at all, since that only exists
      inside real Nix module evaluation. Real limit of "extract the logic
      and sandbox-test it": validates the logic in isolation, can't catch
      cross-module interactions that only manifest in the full module
      system.
    - **Fix**: explicit `home.file.".bashrc".enable = lib.mkForce false;`
      (and `.profile`) - not just omitting the declaration. Verified by
      building the actual `home-manager-files` derivation and confirming
      both paths are genuinely absent from its listing.
    - **General lesson**: whenever "removing" something Nix-managed that
      a *different* module might also touch, check whether omitting your
      own declaration is enough or whether you need to explicitly
      force-disable the option - especially `home.file.*`, which many
      `programs.*` wrappers independently declare. When in doubt, build
      the actual derivation and inspect its real file listing.
    - Live system was NOT left broken: HM's own file-linking had already
      succeeded before the hook step failed, so `~/.bashrc`/`~/.profile`
      still resolved to valid content the whole time (confirmed via
      `readlink -f` before making any further changes).

15. **Chromaden's power-toggle.sh script content matched byte-for-byte**
   between the old hardcoded version and the new
   `dotsLocal.machine.display`-parametrized one (checked via `nix eval
   --raw` on the generated `home.file` text) - strong confidence the
   generalization introduced zero behavior change for the one host it was
   fully validated against.

### 2026-07-18 — `update-alien-packages` orphan false-positive: `ghostty`, plus 2 more bugs found while fixing it
User reported `update-alien-packages --action remove` wanted to remove
`ghostty`, actively needed/used. Root cause: orphan detection only ever
cross-checked a package against *the same manager's* required list, never
the union of all managers. Since pacman/paru share the same underlying
installed-package DB, a package whose spec moves from one manager to
another (ghostty: `paru`→`pacman` once it hit official repos) gets
permanently stuck flagged as an orphan under the old manager forever,
even though still required and installed - `pacman -Rns` doesn't care
which manager "owns" it, so this would have genuinely uninstalled a
working package.

**Fix**: added `get_all_required()` (union of all `required/*.txt`
files), used everywhere orphan status is computed/filtered, plus a
defense-in-depth check in the removal prompt loop itself.

**Two more pre-existing bugs found while testing the fix**:
1. `get_all_required`'s first cut used plain `cat` on files that don't
   end in a trailing newline (Nix `home.file` text) - glues the last
   line of one file to the first of the next (`zellij`+`frogmouth` →
   `zellijfrogmouth`), silently dropping both names. Fixed with `awk 1`
   instead (normalizes every line to be newline-terminated).
2. `remove_packages` used `((counter++))` under `set -e` - post-
   increment's *result* is the old value, so incrementing from 0 is
   `((0))` = false = `set -e` aborts the whole script silently on the
   very first prompt, no error shown. Fixed by replacing all 5
   occurrences with `var=$((var + 1))` (plain assignment, always
   succeeds).

Verified end-to-end on the live system (not just eval): dry-run now
shows "All packages in order"; the remove flow correctly processes all
orphans in one pass; a real `update` self-healed the stale `ghostty`
entry automatically.

### 2026-07-19 — Phase 8: externalizing scripts that have real Nix interpolations
- Not every embedded script can be a straight `builtins.readFile` swap like
  grabcontext.py was. `viewer.nix`'s `v` script genuinely needs Nix-evaluated
  content baked in: several `${pkgs.X}/bin/Y` package paths, plus
  `imageViewer`/`pdfViewer`/`videoViewer` which are themselves *conditional
  Nix expressions* (picking between chafa/catimg/bat based on which sixel
  features are enabled), not just static package references.
- Pattern used: keep a **small** (~10 line) Nix-string preamble that resolves
  every such value into a plain shell variable (e.g.
  `BAT_BIN="${pkgs.bat}/bin/bat"`, `IMAGE_VIEWER="${imageViewer}"`), then
  string-concatenate `builtins.readFile ./somewhere/script.sh` after it:
  `pkgs.writeShellScriptBin "name" (''...preamble...'' + builtins.readFile
  ./script.sh)`. The externalized file itself becomes 100% plain,
  shellcheck-able bash referencing only the shell variables (`$BAT_BIN` etc)
  - zero Nix syntax. This cleanly separates "Nix-level wiring" (which
  package/conditional value to use) from "bash logic" (what to actually do),
  and is the right template to reuse for `clipboard.nix` and any
  niri-noctalia helper scripts that also reference `pkgs.*`/config values.
- Gotcha: watch for `''${...}` Nix-string escapes inside the script body
  that exist ONLY to stop Nix from interpreting a legitimate bash parameter
  expansion (like `${file##*.}`) as Nix interpolation. Once the body moves
  to a real standalone `.sh` file, these must be unescaped back to plain
  `${...}` — leaving the doubled `''$` in place produces invalid/wrong bash
  in the extracted file (this exact case: `local ext="''${file##*.}"` ->
  `local ext="${file##*.}"`).
- Gotcha: if the original embedded string started with its own
  `#!/usr/bin/env bash` line, and the new preamble also needs one (since
  `pkgs.writeShellScriptBin`'s first argument is just concatenated text, no
  automatic shebang), remember to delete the duplicate from the extracted
  file - the preamble's shebang. is the one that stays.
- Verification technique for "is the extracted script still behaviorally
  identical" when a byte-diff isn't trivially expected to be empty (unlike
  grabcontext's case): get each version's derivation via `nix eval
  ...--apply 'pkgs: (builtins.head (builtins.filter (p: (p.name or "") ==
  "<name>") pkgs)).drvPath' --raw`, `nix build "$DRV^*"` each one (stashing/
  unstashing the working tree in between to get the "before" version), then
  `diff -r` the two output directories. Confirms the *only* differences are
  the expected inlined-store-path-vs-shell-variable substitutions, with
  identical resolved store paths appearing on both sides. Followed up with
  actually running the new binary (`--help`, plus functional smoke tests
  exercising a couple of real code paths like JSON/CSV formatting) since a
  byte-diff alone doesn't prove the shell variables are correctly quoted/
  scoped at runtime.
- **Follow-up gotcha, hit while extracting `clipboard.nix`**: when a
  Nix-computed "command line" string itself contains an *internally
  quoted* argument (e.g. the wsl paste command: `powershell.exe -NoProfile
  -Command "Get-Clipboard -Raw"` - note "Get-Clipboard -Raw" must stay
  ONE argument), do **not** just dump it into a plain shell variable and
  reference it unquoted later. In the original embedded-Nix-string form
  this worked by accident: Nix interpolation splices the literal text
  directly into the bash source *before bash ever parses it*, so the
  quotes are genuinely syntactic quotes to bash. But once that same text
  is assigned to a bash variable (`VAR="powershell.exe ... \"Get-Clipboard
  -Raw\""`) and later expanded unquoted (`$VAR`), the quote characters are
  by then just inert data in the variable's value - bash does NOT
  re-parse them, and word-splitting on whitespace will incorrectly break
  `"Get-Clipboard` and `-Raw"` into two separate words. Fixed by using a
  real bash **array** instead of a string
  (`COPY_CMD=("powershell.exe" "-NoProfile" "-Command" "Get-Clipboard
  -Raw")`, generated from a Nix list of individually-double-quoted
  literal elements), referenced as `"${COPY_CMD[@]}"` - this preserves
  argument boundaries exactly regardless of embedded spaces, and is
  actually more robust than the original implicit-splice behavior (no
  reliance on eval-like semantics at all). General rule for any future
  Phase-8-style extraction: if a Nix-computed value represents multiple
  shell words/arguments (not just one atomic path), pass it through as a
  bash array, not a string - only use a plain string variable for truly
  atomic values (a single path, a single flag, a single word).

### 2026-07-19 — AGENTS.md's own "keep in sync each phase" instruction was never honored
AGENTS.md carried an explicit self-instruction from the start of this
re-architecture: update its Repository Structure/Architecture sections "as
each phase lands so the two [AGENTS.md and memory-bank/architecture.md]
never drift for long." In practice this never happened across any of the
9 phases - by the time the user asked for a stale-comment cleanup pass
post-live-checkpoint, AGENTS.md's actual body content (not just isolated
comments) still described the entire pre-Phase-2 system end to end:
`profiles/priv/home.nix`, `profiles/<profile>/hosts/<hostname>.nix`,
`profileDefinitions` in flake.nix, `homeConfigurations.priv`,
`apply-dots priv`, deprecated `programs.ssh.matchBlocks`. None of it had
been touched since Phase 0. Lesson: a standing "update X as you go"
instruction embedded in a doc is easy to silently defer indefinitely once
attention is on the phase's actual code changes - if this pattern
recurs (a living doc meant to track a multi-phase effort), it's worth
either (a) actually updating it at the end of every phase as promised, or
(b) being honest that it won't happen incrementally and explicitly
scheduling one consolidated pass near the end instead, rather than leaving
a disclaimer that quietly goes stale.

### 2026-07-19 — Conditionally-omitted module-system keys vs. conditionally-empty values
Found while fixing `setup.sh`'s drift from `modules/local/schema.nix` and
doing a real fresh-setup regression test (sandboxed `$HOME`, run just the
identity-generation half of `setup.sh`, then `nix eval` the result - a
technique worth reusing any time you need to check "does this work for a
genuinely new user with nothing customized yet", which is a fundamentally
different test than anything that uses chromaden's real, fully-populated
`dots-local`).

`features/network.nix` had:
```nix
settings."*" = lib.mkIf (dotsLocal.machine.sshIdentityFile != null) {
  IdentityFile = dotsLocal.machine.sshIdentityFile;
  AddKeysToAgent = "yes";
};
```
This looks like it should produce an "empty settings entry" when
`sshIdentityFile` is null, but `lib.mkIf false <anything>` doesn't
evaluate to an empty value assigned to the key - it's a special internal
marker meaning "this module doesn't contribute a definition for this
option path at all", and when NO module anywhere contributes a
definition for `settings."*"`, the key is entirely absent from the final
`config.programs.ssh.settings` attrset (not present-with-value-`{}`).
Home Manager's own `programs.ssh` module asserts `settings ? "*"` (the
key must exist) whenever `enableDefaultConfig = false` and `extraConfig`
is set - it doesn't care what's IN `settings."*"`, only that something
declared it. So `lib.mkIf` on the whole value was silently violating that
assertion whenever `sshIdentityFile` was null, which never showed up in
any real validation because chromaden's `dots-local` always sets
`sshIdentityFile` - only a truly fresh, uncustomized config exposes it.

**General lesson**: `lib.mkIf cond value` conditionally omits a
*definition* for an option path; it is NOT equivalent to "the value is
conditionally `{}`/empty" if something downstream (an assertion, another
module reading `option ? key`, etc.) cares about whether the path was
declared at all versus merely empty. When that distinction matters, build
the conditional at the plain-value level instead
(`if cond then {...} else {}`), so the option path is always assigned
*something*, keeping the key's mere presence unconditional even though
its contents vary.

### 2026-07-19 — `lib.mkIf` INSIDE a plain list literal actually works fine for `listOf`-typed options (correcting a wrong hypothesis mid-session)
While auditing for duplicate-package bugs, found `modules/core/nix-tools.nix`
and `modules/features/viewer.nix` using `home.packages = builtins.filter
(p: p != null) [ (lib.mkIf cfg.foo pkg) ... ]`. Assumed this was the same
class of bug as the `programs.ssh.settings."*"` one above (i.e. that
`lib.mkIf false pkg` evaluates to an unresolved `{ _type = "if";
condition = false; content = pkg; }` marker in plain Nix, which is never
`null`, so `filter (p: p != null)` would never actually remove it) and
started "fixing" `nix-tools.nix` to use `if cond then pkg else null`
instead (matching `modules/core/lib.nix`'s `mkAppSet` pattern).

**This was wrong — reverted, no fix was needed.** Empirically confirmed
(toggling `ripgrepAll`/`nh`/`nvd`/`nixTree` via a temporary override and
diffing `config.home.packages` before/after) that disabled entries are
correctly excluded either way, with zero leftover `_type = "if"` markers
in the final list. The reason: `types.listOf`'s "v2" merge (nixpkgs
`lib/types.nix`, search `listOf =`) does NOT just concatenate each
module's raw list value - it treats **each list element from each
definition as its own separate definition** and runs the *full*
`mergeDefinitions` machinery (mkIf/mkMerge discharge included) on every
element individually before the final list is assembled. So `lib.mkIf
cond pkg` as a bare list element of a `listOf`-typed option (like
`home.packages`) is genuinely fine, not a bug - unlike the ssh-settings
case above, which involved an *attrset-valued* option and a downstream
consumer checking mere key-presence (`?`) rather than the option's own
type-level list-merge logic.

**Why `mkAppSet`/`alien.mkEntry` still deliberately use a plain
`if/else null` instead of `lib.mkIf`, then**: not because `lib.mkIf`
would be broken there too, but because `mkAppSet`'s `packages` output is
a *plain returned list value* (not itself assigned directly as an
option's definition in the module doing the returning) that calling
sites then splice into `home.packages` themselves - and more simply,
because it's the established, self-contained, non-module-system-
dependent idiom already in use, worth keeping consistent. It is not
evidence that `lib.mkIf`-in-a-list is unsafe.

**Process lesson**: don't generalize a confirmed bug pattern (the ssh
one) to a superficially-similar case (bare `lib.mkIf` in a list) without
empirically testing that *specific* case first - the underlying module-
system mechanics differ meaningfully between "attrset option + presence-
checking consumer" and "listOf option whose type already deep-merges
per-element". Always verify via a real before/after config diff (toggle
the flag, diff `config.home.packages`/etc.) before committing a "fix" or
writing a comment asserting a bug existed.

### 2026-07-19 — nixpkgs short attribute names can silently collide with unrelated tools
User caught: `pkgs.jj` is `tidwall/jj` (a JSON Stream Editor), not
Jujutsu (jj-vcs.dev) - the real VCS lives under `pkgs.jujutsu` instead
(same `meta.mainProgram = "jj"`, so the actual CLI command is
unaffected, only the nixpkgs *attribute* was wrong). `dots` had been
silently installing the wrong tool under `suites.git-tools.jj` since
whenever that option was introduced - see `decisions.md`'s matching
2026-07-19 entry for the full fix.

**General technique for catching this class of bug**: `nix eval
.#homeConfigurations.default.pkgs.<name>.meta.{description,homepage}
--override-input dots-local git+file://$HOME/dots-local` immediately
reveals a mismatch. Short (≤4 char) package attribute names are the
highest-risk category in a registry as large as nixpkgs - worth a quick
sanity pass whenever adding a new short-named tool, and worth an
occasional repo-wide audit (grep all `pkgs.<name>` references, batch-
check `meta.description` against what the surrounding option/comment
claims the tool is). Did exactly this sweep across every ≤4-char
`pkgs.X` reference in `dots` after finding the `jj` case - `aerc`,
`bat`, `btop`, `fd`, `fzf`, `gh`, `glow`, `imv`, `jq`, `khal`, `lsd`,
`lsix`, `mold`, `mpv`, `niri`, `nmap`, `pass`, `tuba`, `vhs`, `vlc`,
`xh`, `yazi` all confirmed correct - `jj` was the only mismatch found.

### 2026-07-19 — bash login vs. non-login shells source different files, and this bit the NIXON gatekeeper
Root-caused a real `apply-dots` failure (`nh`: "No output from nix
--version command") to a gap in `modules/core/nixon.nix`'s shell-mode
gatekeeper - full technical mechanics worth recording since it's a
classic, easy-to-forget bash gotcha:

- A **login shell** (`bash -l`, or a shell invoked as `-bash`, e.g. many
  TTY/SSH logins) sources `/etc/profile`, then the *first* of
  `~/.bash_profile`, `~/.bash_login`, `~/.profile` that exists (only
  one, not all three).
- A **non-login interactive shell** (the common case: a terminal
  emulator opening a new tab/window inside an already-running graphical
  session) sources only `~/.bashrc` - never `~/.profile` or any of its
  siblings, regardless of what's in them.
- `dots`'s own `~/.profile` → `.profile-dots` chain does extra setup
  (`.profile-nix` → `hm-session-vars.sh` → nixpkgs' own `nix.sh`) that
  `~/.bashrc` → `.bashrc-dots`'s chain does NOT independently replicate -
  `.bashrc-dots` only sources `.bashrc-nix` (pure Home Manager output,
  aliases only, no PATH logic) when `NIXON=1`.
- Net effect: anything that works when you explicitly run `nixon`/
  `nixoff` (both `exec bash -l` - always a login shell, always goes
  through the fuller `.profile` chain) can silently break the moment
  someone just opens a *plain new terminal* instead - which inherits
  whatever `NIXON` value the parent (systemd/PAM) environment already
  has, and goes through the thinner `.bashrc`-only chain.

**General lesson**: when testing shell-bootstrap changes, always check
behavior via a **fresh non-login interactive shell** (`bash` with no
flags, simulating "just opened a new terminal"), not just via `bash -l`
or the `nixon`/`nixoff` aliases themselves - the two code paths
genuinely diverge, and the aliases' own use of `-l` makes it easy to
accidentally only ever test the login-shell path.

### 2026-07-22 — Testing pitfall: deeply-nested `bash -lc "..."` strings can silently pre-expand `$PATH` at the wrong level

While diagnosing the `nixon`/`nixoff` PATH-leak bug (see `decisions.md`'s
matching entry), an initial 3-level repro built as a single nested
one-liner -
`bash -lc 'NIXON=1 exec bash -lc "NIXON=0 exec bash -lc \"echo \$PATH\""'`
- kept showing one leftover `~/.nix-profile/bin` entry even after both
real bugs were fixed, while a 2-level version of the exact same
transition came out clean. The apparent discrepancy was **not** a real
bug: each layer of `\"`/`\$` escaping is consumed by the *next* shell
out as it parses its own `-c` argument, so by the time the innermost
`echo $PATH` substring reaches the *middle* shell, its `\$` has already
been unescaped to a live, unescaped `$PATH` - which that middle shell
(still `NIXON=1`, dirty PATH) greedily expands while merely constructing
the argv for its own `exec`, long before the real innermost shell (the
`NIXON=0` one) ever runs. The number of backslash levels needed is
exactly `2^(depth-1)-ish` and easy to get subtly wrong, silently
capturing a stale PATH instead of testing live behavior.
**Fix/lesson**: never nest more than one level of `bash -c "..."`
string-escaping to test multi-step `exec`/env-var chains - write each
level as its own real script file (`exec bash -l /path/to/next.sh`) and
have the *innermost* script itself do the `echo $PATH`/assertion. This
eliminates all cross-level quoting ambiguity and was what finally
produced a trustworthy repro (confirming both PATH-leak fixes actually
work).


**2026-07-22**: `.bashrc-nix` (Home Manager's generated interactive
bashrc content) starts with `[[ $- == *i* ]] || return` - it does
nothing at all in a non-interactive shell. This means `bash -l
some_script.sh` (a login but non-interactive shell) never exercises it,
even though it looks like a normal login-shell test. To reliably test
`nixon`/`nixoff` behavior end-to-end, allocate a real pty via `script
-qec "bash -l" logfile < commands.txt` and feed commands through stdin,
then grep the logged output - this is the only way that's been
confirmed to actually trigger `.bashrc-nix`'s content during testing in
this environment.

**2026-07-22**: the Determinate Nix installer can install its
"Nix"/"End Nix" `nix-daemon.sh`-sourcing block in MORE than one
system file - on this host it was in BOTH `/etc/profile.d/nix.sh`
(sourced by `/etc/profile` for every login shell) AND directly at the
top of `/etc/bash.bashrc` (sourced by `/etc/profile`'s own
`test -r /etc/bash.bashrc` line, for every INTERACTIVE shell). Only
disabling the first one still leaves nix vars/PATH leaking into every
interactive shell via the second. Both run before any
`.profile-dots`/`.bashrc-dots` content ever gets a chance to, so no
amount of dots-managed scrubbing can counteract them - always `grep -rl
"nix-daemon\|/nix/var" /etc/` (or check both files directly) when
diagnosing "clean env" complaints on a Determinate-Nix host, not just
the more commonly-known `/etc/profile.d/nix.sh`.

**2026-07-22**: the Nix-store-packaged `nix.sh` (the one
`hm-session-vars.sh` sources, distinct from the system
`nix-daemon.sh`) requires BOTH `$HOME` and `$USER` non-empty to do
anything, and has NO re-entry-guard variable of its own (unlike the
system `nix-daemon.sh`, which sets `__ETC_PROFILE_NIX_SOURCED`) - so a
silent no-op (e.g. because `$HOME` hadn't been restored yet at that
point in a shell-startup chain) is invisible except as an empty
`NIX_PROFILES`/missing `~/.nix-profile/bin` on `PATH` afterward.
Anything that hands off env vars across an `exec`/re-login boundary and
needs `nix.sh`/`hm-session-vars.sh` to work correctly downstream MUST
make `$HOME`/`$USER` genuinely set from the very start (not deferred to
a "restore at the end" step) - confirmed by reproducing this exact
failure with a shadow-var-only handoff design (`_nixon_toggle` in
`modules/core/nixon.nix`), fixed by also passing preserved vars as
direct real-name assigns alongside the shadow ones.

## HOME/USER backfill needed for degenerate shell starts (env -i)

`bash -l` never re-populates `$HOME`/`$USER` itself if they're unset in
the inherited environment (e.g. `env -i bash -l`) - it only falls back
to a passwd-db lookup *internally* for tilde (`~`) expansion when
locating `~/.bash_profile` etc, so dots-managed rc files still get
sourced even with both genuinely unset. This matters beyond cosmetics:
`_nixon_toggle` (modules/core/nixon.nix) only hands a var off across its
`exec -c` re-exec if it's currently *set* (`${!v+x}` test), so an unset
`HOME`/`USER` at that point gets silently dropped from the handoff even
though both are in `dotsLocal.nixonEnvAllowlist` - and the store-packaged
`nix.sh` (sourced via `.profile-nix`) silently no-ops without both being
non-empty (see the 2026-07-22 nixon/nixoff learnings entry above), so
the failure is invisible except as a missing `~/.nix-profile/bin` on
`$PATH`. Fixed by backfilling both from `getent passwd "$(id -u)"`/
`id -un` near the very top of `.bashrc-dots`, before anything else runs,
so every subsequent `nixon`/`nixoff` toggle in that shell always has a
real value to capture and hand off.

## HOME/USER backfill needed in BOTH .profile-dots and .bashrc-dots

Follow-up to the entry above: `.profile-dots` sources `.profile-nix`
(nix.sh) BEFORE `.bashrc-dots` ever runs, so the HOME/USER backfill
living only in `.bashrc-dots` still leaves a gap on a machine with
`dotsLocal.nixonDefault = true` - its very first login shell of a
session could hit the exact same silent nix.sh no-op if HOME/USER
happen to be unset at that point, since nothing backfills them before
.profile-nix sources. Duplicated the same backfill at the top of
`.profile-dots`, before the `.profile-nix` sourcing line. Verified via
`env -i NIXON=1 bash -l` (simulating a nixonDefault=true machine's very
first shell with HOME/USER unset): NIX_PROFILES and
`~/.nix-profile/bin` now resolve correctly.

## MyST CLI gotchas discovered during the vk Quarto→MyST migration (2026-08-03)

- `myst build --html --watch` does **not** actually rebuild on file
  change - MyST itself prints "Site content will not be watched and
  updated; use 'myst start' instead" at startup. Use `myst start` for
  any live-reloading workflow; `build --html` (no `--watch`) is only for
  one-shot static exports (confirmed it *does* exit naturally on its
  own once the build completes, ~10-25s for a tiny project - it's not a
  server that hangs forever).
- `myst start --headless` (content-server only, no app server) *does*
  rebuild files on disk when they change, but serves **stale** content
  to already-open connections - only the full two-server mode (an app
  server via `--port` plus an internal content server via
  `--server-port`) actually propagates a live-reloaded page. Don't use
  `--headless` for anything that needs to show live edits.
- `myst start`'s bind address is controlled by the `HOST` **environment
  variable**, not a CLI flag - and is silently forced back to
  `localhost` unless `--keep-host` is also passed. `HOST=0.0.0.0 myst
  start --keep-host` is the only way to bind all interfaces; omit both
  for MyST's own (safe) loopback-only default.
- `myst build --typst --force <file>` slugifies the output basename
  from the source filename/title (e.g. `with_tasks.md` →
  `with-tasks.pdf`) - don't glob `_build/exports/**/${BASE}.pdf` using
  the *source* file's own basename, it will silently miss the real
  output. Find the newest `.pdf`/`.typ` file under MyST's own output
  dirs (relative to a timestamp mark taken just before the build)
  instead - reliable since `--force` triggers exactly one export per
  invocation.
- The raw `.typ` Typst source for an export lives under a
  **randomly-named** `_build/temp/myst<RANDOM>/` directory, not next to
  the PDF in `_build/exports/`; both directories also contain a copy of
  the compiled PDF.
- `pandoc.SimpleTable(caption_inlines, aligns, widths, header_cells,
  body_rows)` followed by `pandoc.utils.from_simple_table(st)` is the
  correct, version-robust Lua API path for building a real
  `pandoc.Table` AST node from a Lua filter - the naive
  `pandoc.Table(...)`/`pandoc.TableBody(...)` constructors aren't
  directly callable in Pandoc 3.7.0.2's Lua API.
- `pandoc.pipe(cmd, args_table, input)` passes args as a real argv array
  with no shell involved - this is what makes shelling out to an
  external command (e.g. `task export`) from a Lua filter immune to
  shell injection even with adversarial directive-attribute values;
  confirmed live with a `project="demo; touch /tmp/PWNED"` attack
  attempt.
- MyST's static `--html` build output is a client-rendered SPA (React
  Router/Remix-style bundle under `_build/html/build/`) whose emitted
  asset/route hrefs are **absolute-rooted from `/` by default** - simply
  symlinking that output tree under a subpath (e.g. for a shared
  multi-vault hub) is not enough; the bundle will still fetch its own JS
  from the *true* root, colliding with whatever else is mounted there.
  MyST has no `--base-url` CLI flag, but does honor a `BASE_URL`
  **environment variable** at build time - set it to the eventual
  mount path (e.g. `BASE_URL=/az`) before `myst build --html` and every
  emitted href becomes correctly prefixed. There is no way to change an
  already-built output's base path after the fact; it must be rebuilt.
- A bare (non-`<...>`-wrapped) CommonMark/MyST link destination
  containing a literal space is invalid syntax - `[Title](My Note.md)`
  parses as plain text, not a link. Any code that builds a Markdown link
  destination from a real filename must percent-encode it first (space
  at minimum; `#`/`?` too, since those are fragment/query delimiters in
  a URL) - see `url_encode_path()` in `vk.sh`.
- The pinned `mystmd` 1.9.1 (nixpkgs) always bundles the Thebe/Jupyter
  in-browser-execution runtime (~100+ `NNNN.thebe-core.min.js` chunks
  per `book-theme` build) with no way to opt out - `site.thebe: false`
  is rejected by its config schema ("cannot include reserved key
  thebe"). This was a known regression, reverted upstream in mystmd
  1.10.1 ("Revert thebe #2903") - not yet in nixpkgs as of 2026-08.
  These chunks aren't referenced by a page's initial HTML shell or its
  content JSON, so they don't appear to be eagerly fetched, but they do
  bloat every vault's `_build/html` output considerably until nixpkgs
  catches up.
- A MyST page's `index.json` `footer.navigation.{prev,next}.url` field
  stays root-relative even when the site was built with `BASE_URL` set
  - only the rendered static `<a href>` tags in the page shell get the
  base prefix. Presumed harmless (the client router's own `basename`
  should apply it at navigation time) but not independently verified -
  worth checking directly if a future bug report describes broken
  prev/next navigation specifically under a nested `BASE_URL` mount.

## vk enhancement session (2026-08-04): cross-vault rename, `vk check`, native citations

- Any command that runs `myst build` and then a Python static-analysis
  pass against the *same* `.vk-staging` tree must exclude MyST's own
  `_build/` output from that scan, exactly like vk's `explore/`
  (generated navigation) pages already were - otherwise `_build/`'s
  vendored theme `node_modules` files (READMEs, CHANGELOGs, LICENSEs,
  which are real `.md` files) get treated as vault notes, producing
  hundreds of false "duplicate id"/"label slug collision" errors. Fixed
  in `vault_check.py`/`vault_enhance.py` via a shared
  `_is_generated_path()` helper checking both prefixes.
- `label_slug` (in `vault_enhance.py`'s `Note` class) is a purely
  vk-internal computed value, not a real MyST target/anchor - MyST does
  **not** generate an implicit project-wide target from a bare filename
  when a note has no explicit `id` (confirmed: multiple id-less
  same-named files, e.g. every category's own `index.md`, build fine
  under `myst build --strict`). Any "id"-requirement or slug-collision
  check must therefore only apply to notes that actually have an
  explicit `id`, not vk's own structural pages (root/category
  `index.md`, `main.md`, `imprint.md`) - these never get a vk-managed
  `id` by design (see `_is_categorized_note()`/`STRUCTURAL_CATEGORIES`
  in `vault_check.py`).
- `vk check`'s `myst build` call must never write directly into
  `.vk-staging/_build` without backing it up first: that's the exact
  directory `myst_build()`/`vault_needs_build()` use to track a vault's
  `BASE_URL`/fingerprint via `.base_url`/`.vk_fingerprint` marker files
  for `build`/`watch`/`serve-all`. A raw, marker-blind build (as `check`
  originally did) silently overwrites a vault's *currently-served*
  nested (serve-all) build with a mismatched standalone one while
  leaving the stale markers claiming a match - serve-all then keeps
  serving the now-broken build until an unrelated source change forces
  a real rebuild. Fix: back up `_build` (`mv` to a `mktemp -d`) before
  the check's own build, then restore it afterward regardless of
  pass/fail, so `vk check` is always side-effect-free on the serving
  cache. Verified live: byte-identical `_build` tree (md5sum over every
  file) before/after running `vk check` on a vault built nested with
  `BASE_URL=/vaultname`.
- MyST auto-discovers any `*.bib` file at the project root for native
  `[@citekey]` citation resolution - no `myst.yml` `bibliography:` field
  is needed unless you want to control load order or use a remote file
  (confirmed via https://mystmd.org/guide/citations).
- `gum`'s interactive prompts require a real TTY (`/dev/tty`) - neither
  piping input nor faking a pty via `script -qc "..."` works (the latter
  hangs, since `gum`'s bubbletea TUI reads raw keystrokes, not
  line-buffered pipe data). To functionally test `vk`'s interactive
  commands end-to-end without a TTY, either manually scaffold a vault
  matching what the interactive code path would produce and invoke the
  non-interactive subcommands directly, or test the underlying
  shell/Python logic in isolation.
- `VAULTS_DIR` is baked into the built `vk` script as a literal
  `VAULTS_DIR="$HOME/Vaults"` shell assignment at Nix build time (from
  `cfg.vaultsDir`), not an overridable env var at runtime. To
  functionally test the real built binary against a scratch directory
  without touching `$HOME/Vaults`: `sed` a copy of the real built `vk`
  path, replacing only that one assignment, then `chmod +x` and run the
  patched copy - every other Nix-resolved store path (`MYST_BIN`,
  `PYTHON_BIN`, `VK_FINGERPRINT`, etc.) stays correct.
- Writing unit tests for `vault_enhance.py`'s link resolver surfaced a
  real latent bug: `_resolve_link_target()`'s candidate matching against
  `by_relpath_noext` (which is how a renamed note's alias - or any
  other note's own extensionless rel-path - is supposed to be looked
  up) never actually stripped the `.md` extension off the candidate
  before comparing, so an ordinary `[text](old-name.md)`-style link
  never matched an alias, silently breaking the "old links still
  resolve" guarantee the function's own docstring promises (only a
  literal `{doc}`-style extensionless link happened to work). Fixed by
  computing an extension-stripped candidate specifically for the
  `by_relpath_noext` comparison. Note this only affects
  `vault_enhance.py`'s own backlinks/Related-Notes navigation feature
  for links `note_rename.py` didn't rewrite live (e.g. hand-typed links
  added after a rename) - `note_rename.py` itself rewrites matching
  links directly and never depended on this alias-resolution path.
- Building the demo vault surfaced two real, previously-untested bugs:
  (1) `graphviz_preprocess.py` always emitted a staging-root-relative
  image path (`assets/graphviz/<hash>.svg`), which 404s for any note
  one category level deep (materials/records/texts - i.e. every real
  note) since MyST resolves that path relative to the note's own
  directory - every existing test used a flat `source_path="note.md"`,
  so this never surfaced until a real nested note used the directive.
  Fixed by adding a `doc_rel_dir` parameter (wired through `vk.sh` as
  `--doc-rel-dir "$(dirname "$rel")"`) so the emitted path is computed
  relative to the note's own directory via `posixpath.relpath`. (2) A
  `myst-substitutions` value beginning with `@` (e.g. `"@spmsft"`) that
  gets substituted into prose text is then parsed by MyST/Pandoc as a
  citation reference (`@key`), producing a spurious "Could not link
  citation" warning - substitution values should avoid a leading `@` (or
  any other Markdown-special leading character) if they'll be inlined
  into prose rather than code.
- Found and fixed a real **upstream mystmd/book-theme CSS cascade bug**
  that made article content invisible at browser widths >=1280px (the
  Tailwind `xl` breakpoint), reported by the user as "past a certain
  window width the main content pane becomes invisible, side nav still
  works." Root cause: `.myst-primary-sidebar` (the closed mobile nav
  drawer) carries both a `hidden` class (`display: none`, meant to keep
  it closed/invisible below `xl`) and a responsive `xl:article-grid`
  utility (`display: grid`, meant for the *open* desktop rail) - at
  >=1280px the `@media (min-width:1280px)` rule's `display: grid` wins
  the cascade over the same-specificity `.hidden{display:none}` purely
  by source order, so the closed drawer renders anyway as a `position:
  fixed`, full-viewport (`w-[75vw]`/`h-screen` - meant only for the
  mobile drawer's *own* sizing, itself compiled with inverted `max-xl:`
  media-query logic, a second latent bug in the same rule cluster),
  opaque white panel sitting on top of the real content. It stays
  `pointer-events: none` at that width, though, so clicks/hit-testing
  (`elementFromPoint`) still reach the real content underneath -
  DOM/CSSOM inspection (computed styles, rects, colors, opacity) all
  looked completely correct, which is what made this so easy to
  mistake for "the vault isn't loading" rather than a paint-only bug.
  This almost certainly also explains a separate-seeming user report
  that `serve-all`'s root vault list appeared "empty" - the root hub
  page is built with the same book-theme and is subject to the exact
  same bug at the same breakpoint. Confirmed via headless-Chromium
  screenshots (both a bare `chromium --headless --screenshot` sweep and
  Playwright, against the *real* production path - a `vk build` static
  site served by `dufs`, not `vk watch`'s dev server, since the
  dev-server's own live-reload client turned out to be an unrelated red
  herring during investigation) across widths 900-1600px: broken at
  every width >=1280px, fine below it, and fixed at every width once
  patched. Fix: `vk-theme.css` appends one targeted override,
  `.myst-primary-sidebar.hidden { background: transparent !important; }`,
  after book-theme's own CSS in the cascade - deliberately not touching
  or forking `book-theme`/`mystmd` itself. **Caution**: a first attempt
  used `display: none !important` instead of stripping just the
  background - that also silenced the invisible-overlay bug, but broke
  the *legitimate* desktop left-nav rail, since the real persistent nav
  (`.myst-primary-sidebar-pointer`, shown via `xl:flex`/
  `xl:col-margin-left`) is nested **inside** this same
  `.myst-primary-sidebar` container and needs it to actually lay out
  (not `display: none`) at >=1280px in order to render at all -
  `display: none` on the parent unconditionally collapses all
  descendants regardless of their own `display` value. The
  background-only override keeps the container in normal (grid) flow
  so the nested nav rail still renders, while removing only the opaque
  fill that was painting over the article content. Re-verify this
  specific regression (screenshot sweep at width breakpoints
  1024/1279/1280/1300/1400/1536/1600 against a real `vk build` +
  `dufs`-served static site, checking **both** that article content is
  visible **and** that the desktop nav rail (`.myst-primary-sidebar-
  pointer`) still renders with nonzero width at >=1280px) if `mystmd`/
  `book-theme` is ever upgraded, in case upstream fixes or changes this
  cascade and the override becomes redundant or needs adjusting.
- **Follow-up to the above**: after the `background: transparent` fix,
  the user reported the nav rail was visible again but now painting
  *over* the article content with a transparent background - i.e. the
  same nav rail was genuinely mispositioned, not just masked/unmasked
  by the earlier opaque-background bug. Root cause was a **second,
  independent upstream `book-theme` CSS authoring bug**: the desktop
  nav rail (`.myst-primary-sidebar-pointer`) gets its column position
  from a `xl:col-margin-left` utility class, compiled to
  `.col-margin-left { grid-column: page / body-start }` - but `page` is
  never actually defined as a named grid line in any of book-theme's
  own `.article-grid` breakpoint templates (only `page-start`/
  `page-end` exist as named lines; `page` alone does not). Since the
  grid-column start value doesn't match any real named line, browsers
  fall back to the CSS Grid auto-placement algorithm instead of the
  intended explicit position - and auto-placement's result depends on
  the current `.article-grid` breakpoint's track layout, which differs
  at 768px/1024px/1280px/1536px. That made the rail land in the
  *correct-looking* spot at some widths (e.g. 1280-1535px) by accident
  of auto-placement, but visibly overlap the article content at others
  (e.g. >=1536px, confirmed concretely broken at exactly 1600px both on
  a fresh page load and after a live browser resize - this is **not**
  purely a resize-timing bug, despite initially looking that way when
  only 1400px/1280px fresh loads were spot-checked and looked fine).
  Confirmed via Playwright: `getComputedStyle(...).gridColumn` on the
  rail read back as the literal string `"page / body-start"`, and
  grepping the built CSS confirmed `page` (unsuffixed) is genuinely
  absent from every `.article-grid` breakpoint's `grid-template-
  columns`. Fix: another targeted `vk-theme.css` override forcing the
  correct, valid named line explicitly -
  `.myst-primary-sidebar-pointer { grid-column: page-start / body-start
  !important; }` - scoped to that one element (not the shared
  `.col-margin-left` utility class, which is also used for unrelated
  margin-note/aside elements elsewhere and must not be touched
  globally). Verified fixed via Nix rebuild + the real, actual
  `vk serve-all` process (not just a standalone `vk build`) against a
  fresh page load sweep (375-1700px) **and** a live-resize sequence
  (1600->1400->1200->1000->800->1000->1200->1400->1600 on the same
  page, matching how a user actually drags a window) - both scenarios
  now render with no overlap and the hamburger menu present <1280px.
  **This turned out to be Chromium-only validation and incomplete -
  see the follow-up entry below for what actually shipped.**

- **Follow-up (2026-08-04/05), correcting the above**: the
  `page-start / body-start` named-line fix only fixed Chromium.
  Zen browser (the user's actual daily browser, confirmed to be a
  Gecko/Firefox fork, not Chromium as originally assumed) still showed
  the rail mispositioned. Headless LibreWolf (a Gecko browser usable
  for scripted screenshot testing - `librewolf --headless --profile
  <scratch-dir> --screenshot out.png --window-size=W,H <url>`, always
  with an isolated `--profile`, never the real default profile - an
  early mistake here left a `.startup-incomplete` marker in the user's
  actual browser profile after force-killing a hung headless instance)
  reproduced the same overlap. A second attempt pinned the same
  position with *numeric* grid-line indices instead of names
  (`grid-column: 3 / 6 !important`) reasoning that numeric indices
  are spec-unambiguous - this **still did not fully fix Firefox**,
  with inconsistent results across widths. Root cause, found by
  extracting book-theme's actual compiled `.article-grid` column
  template (`grep -o '\.article-grid{[^}]*}' _build/html/build/_assets/
  app-*.css`): the grid has exactly two `1fr` tracks that absorb all
  leftover viewport width, and most of the *other* tracks in the same
  template are sized in `ch` (glyph-width) units. Chromium and Firefox
  do not resolve `ch` identically, so the leftover width handed to the
  `1fr` tracks differs by engine even when the rail's own rule only
  references fixed `rem`-based tracks - shifting its absolute pixel
  position differently per engine regardless of which line/index it's
  pinned to. **Any fix that keeps the rail as a participant in
  `.article-grid` inherits this same-engine-divergent `1fr` sizing.**

  Fix that actually resolved it: stop being a grid participant at all.
  `.myst-primary-sidebar-pointer` is now `position: fixed !important`
  (not grid-positioned), `top: 60px` (the real `.myst-top-nav` header
  height), `left: 0`, `width: 13rem`, `max-height: calc(100vh - 60px)`
  with `overflow-y: auto`. `13rem` (not a rounder `18rem`/`15rem`) was
  chosen empirically: the article title's own leftmost text column
  starts at `x=224px` in Chromium at the narrowest width the rail is
  shown at (1280px, the `xl:` breakpoint) - confirmed via
  `getBoundingClientRect()` on the real `h1` - so the rail's right edge
  must stay under that with margin to spare; wider values (18rem/288px,
  15rem/240px) both visibly overlapped the title at exactly 1280px.
  Verified clean with no overlap at 1280/1400/1536/1700/1920px in both
  a real Chromium (Playwright) and a real Firefox/Gecko (headless
  LibreWolf) session, on both the root vault index page and a deep
  article page with an expanded sidebar tree, against an isolated
  `myst build` output (not `$VAULTS_DIR` - see the next entry for why
  that distinction matters for testing methodology).

  A second, unrelated but easily-confused-for-the-same-bug symptom was
  also chased and ruled out during this: the user separately reported
  intermittent 404s/"myst error" pages ("still getting lots of not
  faults and the occasional myst error page"). Root cause found: two
  independent `vk serve-all` instances (one real, one a test scratch
  instance) were pointed at the **same** `$VAULTS_DIR` at once - each
  instance's `serve_all_rebuild()` reruns every 3 seconds and
  previously deleted every vault symlink under `_build/html` up front
  before recreating them one by one (`find ... -delete` then a `ln -s`
  loop), leaving a real window where a concurrent request saw the path
  as nonexistent and dufs served its own "folder will be created when
  a file is uploaded" placeholder. Confirmed via a 40s curl stress test
  against a single real instance (0/178 requests failed) versus the
  same test with two competing instances (roughly half failed) - **the
  flakiness was a testing-methodology artifact (never run two
  `serve-all` instances against the same `$VAULTS_DIR`), not a bug a
  normal single-instance user would hit.** The delete-then-recreate
  symlink swap was still hardened defensively regardless (atomic
  `ln -sfn` into a `.vk-tmp` name + `mv -Tf` onto the real name, so a
  name is never briefly absent even for one instance), since it was a
  latent race regardless of how visible it was in practice.

  Testing-methodology note for any future vk layout/serving work: do
  **not** point a second scratch `vk serve-all` (or any test dufs/myst
  process) at `$VAULTS_DIR` while another instance might be running -
  `VAULTS_DIR` is baked in at Nix build time (`vk.nix`'s
  `VAULTS_DIR="${cfg.vaultsDir}"`, not env-overridable), so every
  `vk serve-all` invocation on this machine targets the same real
  directory. Use a fully separate `/tmp` copy of a vault plus a direct
  `myst build --ci --html` + `python3 -m http.server` instead for CSS/
  layout iteration - it exercises the identical compiled theme output
  without any risk of two rebuild loops fighting over the same
  `_build/html` tree.

  Follow-up (2026-08-05): the user had not actually rebuilt/activated
  the `position: fixed` change before reporting it "still broken" -
  once rebuilt+activated, the rail/content overlap was confirmed fixed
  and usable. Two smaller cosmetic reports followed, both root-caused
  against a real staged build (`stage_vault`'s actual
  `assets/vk-managed.css`, not a bare `myst build` without it - the
  latter gives false negatives since the vault's own `myst.yml` never
  references the managed stylesheet directly):
  - "No hamburger menu" at desktop widths is native/expected book-theme
    behavior, not a bug: the mobile hamburger (`.myst-top-nav-menu-
    button`, inside a `block xl:hidden` wrapper) and the persistent
    desktop rail are mutually exclusive by design, swapping at the same
    1280px `xl` breakpoint - confirmed via Playwright at
    900/1100/1279/1280/1400/1920px that exactly one of the two is ever
    visible. User confirmed rail-only (no collapse control) is fine as
    designed.
  - A vertical "scrollbar/separator flash" between the rail and content
    on every page load was a real regression introduced by this fix
    itself: `.myst-primary-sidebar-pointer` natively ships its own
    `overflow-hidden` (the inner `.myst-primary-sidebar-nav` child has
    its own `overflow-y-auto` and does the actual TOC scrolling, while
    the outer rail stays clipped so the flex-pinned footer never gets
    pushed out of view) - the `position: fixed` rule's
    `overflow-y: auto !important` overrode that with a second, redundant
    scrollbar on the outer rail. Book-theme's native footer entrance
    animation (`transition-all duration-700 translate-y-6 opacity-0`,
    unrelated to this fix, present upstream regardless) briefly changes
    the rail's content height on every load, so that extra scrollbar
    appeared/disappeared/repainted during those 700ms - reads as a
    "flash". Fixed by changing that property to `overflow: hidden
    !important`, matching the native behavior exactly (verified via
    Playwright: `overflowY` computed style is `hidden` again, inner TOC
    list still scrolls independently when content exceeds
    `max-height`). Lesson: when taking an element out of grid
    participation, only override the specific properties needed
    (`position`/`top`/`left`/`grid-column`) - copying in unrelated
    properties "defensively" (like `overflow-y: auto` here, added out of
    caution about the new `max-height`) can silently fight the theme's
    own native layout in ways that only show up as a transient visual
    glitch, not a broken layout, so they're easy to miss without
    actually diffing computed styles against the unmodified element.
