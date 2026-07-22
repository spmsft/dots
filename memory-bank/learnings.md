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
