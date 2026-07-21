# Agent Development Guide

This document provides architecture and development guidance for AI agents working on this repository.

## Memory Bank (read this first)

Before making any non-trivial change, **read `memory-bank/*.md`**, at minimum:

1. `memory-bank/decisions.md` — dated decision log with rationale. Do not
   re-litigate or silently contradict a logged decision; if you think one
   should change, ask the user and log the outcome.
2. `memory-bank/open-questions.md` — unresolved items that need user input
   before proceeding on the related work.
3. `memory-bank/architecture.md` section 12 ("Standing 'keep-in-sync'
   rules") — a consolidated checklist of every "if you change X, you must
   also touch Y" rule discovered so far (schema changes → template file,
   tuning defaults → per-machine overrides, new syncable-worthy config →
   `syncables.nix`, module renames → repo-wide grep, ...). Check this
   *every time*, not just when a decisions.md entry happens to jog your
   memory - this list exists specifically because that kind of drift kept
   happening silently across multiple phases before it did.
4. `memory-bank/AGENTS.md` — checklist of packages this repo pins to a
   manual upstream source snapshot (no nixpkgs attribute, so nothing
   bumps them automatically: `pkgs/lazytask.nix`, `pkgs/quarkdown.nix`,
   `modules/features/butterfish.nix`). Consult this whenever asked to
   "update" one of these tools, or periodically to check them all.

The original multi-phase re-architecture this memory bank was built for
is complete (see `project-brief.md`) - there's no longer a phased
execution tracker to consult. Ongoing work is smaller, discrete,
user-requested changes.

As you work:
- Append new entries to `memory-bank/decisions.md` for any consequential
  choice, and to `memory-bank/learnings.md` for gotchas/workarounds
  discovered along the way.
- Add anything unresolved to `memory-bank/open-questions.md` rather than
  guessing and moving on.
- See `memory-bank/architecture.md` for the full design reference.

## Repository Structure

### Two-Repo Design

The system uses a split repository design:

- **`dots/`** (this repo): Shared configuration, modules, contexts
- **`dots-local/`** (private): Per-machine identity, hardware/context axes,
  tuning flags, and any bespoke per-host modules

`dots-local` is passed as a flake input, evaluated against
`modules/local/schema.nix` (`lib.evalModules`), and the resulting
typed config is passed to every module as the `dotsLocal` specialArg (not
`inputs.dots-local` directly - that still carries raw flake-introspection
metadata alongside the actual fields).

### Directory Layout

```
dots/
├── flake.nix                 # Entry point, defines homeConfigurations.{default,default-opt}
├── modules/
│   ├── composition.nix       # Entry point - imports core + context + rules
│   ├── rules.nix              # Declarative axis-based rules (gpu, compositor, isWsl, ...)
│   ├── contexts/             # Composition bundles, selected by dotsLocal.context
│   │   ├── common.nix        # Always-imported minimal CLI baseline
│   │   ├── priv.nix          # Personal context
│   │   └── work.nix          # Work context
│   ├── local/
│   │   └── schema.nix        # Typed schema for dots-local/flake.nix
│   ├── core/                 # Core infrastructure
│   │   ├── default.nix       # Core packages and settings
│   │   ├── scripts.nix       # Command definitions (apply-dots, etc.)
│   │   ├── dots-local.nix    # dots-local integration
│   │   ├── alien-packages.nix   # Native package manager integration
│   │   ├── tune-support.nix     # Package optimization support (home-level)
│   │   └── tune-defaults.nix    # Shared compiler-flag defaults per march
│   ├── flake/                # Flake-level helpers (alien discovery, tuning overlay)
│   ├── features/             # Individual capabilities
│   └── suites/               # Bundled application groups
├── contexts/                 # Data catalogs per context (NOT Nix modules -
│                             #   distinct from modules/contexts/ above):
│                             #   contexts/<context>/sync.json (global sync
│                             #   ignores), contexts/<context>/appimages/
│                             #   manifest.nix (shared AppImage catalog)
├── settings/                 # Synced handcrafted configs (per-host)
├── etc/                      # Manual reinstall reference material (NOT wired into any
│                             #   automation - bootloader/greetd configs, wallpapers, niri
│                             #   desktop session files; copy-paste by hand when needed)
└── sync.sh                   # Config sync script
```

No per-host directory or file (`contexts/<context>/hosts/<hostname>.nix`)
exists - host-specific config is expressed via `dotsLocal` fields
(`machine.*`, `gpu`, `compositor`, `isWsl`, ...) consumed generically by
feature modules, or, for anything too bespoke to generalize, via
`dotsLocal.extraModules` (kept entirely in the private `dots-local` repo).

## Architecture

### Composition

`modules/composition.nix` always imports the common baseline plus exactly
one `modules/contexts/<dotsLocal.context>.nix` bundle (`priv` or `work`),
then folds `modules/rules.nix`'s declarative axis-based rules
on top as *defaults* (an explicit setting anywhere else always wins). A
handful of feature/suite modules (niri-noctalia, llama-cpp, butterfish,
sd-switch, opener, clipboard, scanning, cloud-tools, ai-apps, fonts,
wsl-shell-integration, power-toggle) are imported universally rather than
per-context, since `rules.nix` or another universal module may
need to set their options regardless of which context is active.

### Module Types

**Features** (`features.<name>`): Individual capabilities
- Can be enabled/disabled independently
- Options are config/behavior knobs for ONE cohesive thing, not a bundle
  of separate apps
- Example: `features.clipboard`, `features.viewer`, `features.network`
  (SSH/GPG agent config)

**Suites** (`suites.<name>`): Bundled application groups
- Enable multiple related, independently-toggleable packages at once
- Each option maps 1:1 to a distinct package/tool, not a behavior knob
- Example: `suites.gui-apps`, `suites.tui-apps`, `suites.git-tools`,
  `suites.dev-tools`, `suites.network-tools`

### Key Design Patterns

#### 1. mkDefault for the Common Context

The common context uses `lib.mkDefault` for all options, allowing other contexts to override:

```nix
# modules/contexts/common.nix
suites.git-tools.enable = lib.mkDefault true;
suites.git-tools.delta = lib.mkDefault true;

# modules/contexts/priv.nix (can override)
suites.git-tools.jj = true;  # Also enable jujutsu
```

#### 2. Alien Package Integration

Features check for alien (native) packages and skip Nix versions. For a
suite with more than a couple of toggles, use `modules/core/lib.nix`'s
`mkAppSet` helper instead of repeating this by hand for every option (see
OVERVIEW.md's "Using Alien Packages in Features" for a full example):

```nix
{ config, lib, pkgs, alien, ... }:

config = lib.mkIf cfg.enable {
  home.packages = builtins.filter (p: p != null) [
    (alien.mkEntry cfg.yazi "yazi" pkgs.yazi)
  ];
  
  alienPackages.enabledPackages =
    lib.optional cfg.yazi "yazi";
};
```

#### 3. Distro-Specific Package Lists

Create `<feature>.<distro>-packages.nix` for alien packages:

```nix
# modules/suites/gui-apps.cachyos-packages.nix
{
  ghostty = {
    packages = {
      pacman = [ "ghostty" ];
    };
  };
}
```

The `<feature>` filename prefix is just an organizing convention (keep
a suite/feature's specs next to its own module) - specs are looked up
purely by package name (matched against the `pkgName` a `mkAppSet`/
`alien.mkEntry` call passes), so a package can be, and often is,
consumed by more than one suite/feature.

#### 4. Gutter Evaluation

The flake uses "gutter evaluation" to capture clean Home Manager outputs:

```nix
# Gutter Eval to capture clean HM bashrc/profile
gutterEval = home-manager.lib.homeManagerConfiguration {
  pkgs = pkgs';
  modules = baseModules;
  extraSpecialArgs = { inherit inputs pkgs' alien; };
};

# Then pass to main config
extraSpecialArgs = {
  bashrcDerivation = gutterEval.config.home.file.".bashrc".source;
  profileDerivation = gutterEval.config.home.file.".profile".source;
};
```

This allows Nixon to redirect bashrc without creating conflicts.

### Script Generation

Commands like `apply-dots` are generated in `modules/core/scripts.nix` using `pkgs.writeShellScriptBin`. They are:

1. Defined as Nix expressions (with proper escaping)
2. Installed via `home.packages`
3. Available immediately after `apply-dots` succeeds

## Common Tasks

### Adding a New Feature

1. Create `modules/features/<name>.nix`
2. Follow the pattern:
   ```nix
   { config, lib, pkgs, ... }:
   
   let cfg = config.features.<name>;
   in {
     options.features.<name> = {
       enable = lib.mkEnableOption "Description";
       # Add options...
     };
     
     config = lib.mkIf cfg.enable {
       home.packages = [ ... ];
       # Configuration...
     };
   }
   ```
3. Import in the relevant context (`modules/contexts/priv.nix` or
   `work.nix`), or in `modules/composition.nix`'s universal imports if it
   needs to be reachable regardless of context (e.g. because
   `rules.nix` references it)

### Adding a New Suite

1. Create `modules/suites/<name>.nix`
2. Create `modules/suites/<name>.cachyos-packages.nix` (if needed)
3. Follow feature pattern but use `suites.<name>` namespace

### Adding Alien Package Support

1. Create `<feature>.<distro>-packages.nix` next to your feature
2. Use the **package name** as the key (matching the `pkgName` you pass
   to `alien.mkEntry`/`mkAppSet` - e.g. `pkgs.mypkg` -> key `mypkg`), NOT
   the feature name - `<feature>` in the filename is just an organizing
   convention for where to put the file, and a package name can be
   consumed by more than one suite/feature (see e.g. `lazygit`, defined
   once in `tui-apps.cachyos-packages.nix` but also used by
   `suites.git-tools.lazygit`). Each package name must have exactly one
   spec across the whole repo - defining the same name differently in
   two files is a hard build-time error (see `modules/flake/
   alien-discovery.nix`'s conflict check).
3. Define packages for relevant package managers:
   ```nix
   {
     mypkg = {
       packages = {
         pacman = [ "pkg1" "pkg2" ];
         paru = [ "aur-pkg" ];
         zypper = [ "pkg1" ];
         tdnf = [ "pkg1" ];
       };
     };
   }
   ```

### Adding a New Host

Most new machines need **no changes to `dots` at all** - just a
`dots-local/flake.nix` declaring that machine's identity and axes:

```nix
{
  outputs = { self, ... }: {
    host = "myhostname";
    # ... identity fields (see modules/local/schema.nix) ...

    # Axes that drive what gets pulled in (all optional):
    gpu = "nvidia";           # or "amd"/"intel"/omit
    compositor = "niri";      # or omit for a CLI-only machine
    isWsl = true;              # if running under WSL

    machine = {
      sshIdentityFile = "~/.ssh/id_github_myhostname";
      terminal = "/usr/bin/ghostty";       # only used if compositor == "niri"
      renderDrmDevice = null;               # let niri auto-detect, or set explicitly
      display = {                           # omit entirely to skip power-toggle.sh
        output = "eDP-1";
        ecoMode = { resolution = "1920x1200"; brightness = "30%"; };
        perfMode = { resolution = "1920x1200"; refreshRate = "120.000"; };
      };
    };
  };
}
```

For anything too bespoke to express as an axis (e.g. very specific
CUDA/compiler flags for one particular GPU), add a small module file next
to `dots-local/flake.nix` and reference it via `extraModules`:

```nix
extraModules = [ ./host-myhostname.nix ];
```

Then run `apply-dots`. Run `dots-local-options` (or
`nix eval --json .#dotsLocalOptionsDoc`) to see every available field -
generated live from `modules/local/schema.nix` via nixpkgs's own
`lib.optionAttrSetToDocList`, so it's never a separate doc to fall out of
sync with the real schema.

### Changing `modules/local/schema.nix` (adding/renaming/removing a field)

**Standing rule - always do this, every time:** whenever you add, rename,
or remove a `dotsLocal` field in `modules/local/schema.nix`, you MUST also
update `templates/local/flake.nix` (the real, standalone template
`setup.sh` copies + fills in for a brand-new machine - not a bash
heredoc, see its own header comment) and `setup.sh`'s "Next steps" echo
output, in the same change. This is the *only* onboarding path for a
genuinely new machine with no existing `dots-local` - if the template
silently falls behind the schema, new users get a config that's missing
fields they didn't know existed (or, worse, a config that fails to
evaluate at all - see the `features.network`/`programs.ssh.settings."*"`
bug in `memory-bank/learnings.md`'s 2026-07-19 entry, caused by exactly
this kind of drift). This has already happened once (the schema grew
`gpu`/`compositor`/`isWsl`/`machine.*` across Phase 2 while the template
was never updated to mention any of them) - see
`memory-bank/decisions.md`'s "setup.sh must track schema.nix" entry for
the fix and the full rationale. Also **run the fresh-setup regression
test** described there before considering the change done - a schema
change that silently breaks brand-new users is exactly the failure mode
this rule exists to prevent, and it will not show up in chromaden's own
`nix eval`/`nix build` checks (chromaden's real `dots-local` already has
every field set, masking exactly this class of bug). Since
`dots-local-options` now generates the full field reference live from
the schema, the template itself only needs to show the common/
illustrative fields (as commented-out examples) - it doesn't need to be
exhaustive.

### Nix Evaluation

- `dots-local` is passed as `path:../dots-local` in flake.nix but overridden at runtime
- During `apply-dots`, it's overridden with `git+file://$DOTS_LOCAL_DIR`
- This allows uncommitted changes in dots-local to be picked up

### Error Handling

- Build failures are captured to temp logs (`/tmp/apply-dots-*.log`)
- Activation failures show the log path and common fixes
- Use `-- -b backup` to handle file collisions

## Related Documentation

- README.md - User-facing quick start and feature reference
- OVERVIEW.md - Detailed architecture and tuning system
- SYNC.md - Config sync system documentation
- This file - Development and agent guidance
