# System Overview

This repository provides a complete, portable development environment using Nix and Home Manager.

## Environment Variables

```bash
DOTS_DIR="$HOME/dots"              # Location of dots repository
DOTS_LOCAL_DIR="$HOME/dots-local"  # Location of dots-local repository
```

Both default to `~/dots` and `~/dots-local` respectively. Override for custom installations.

## Distro Backends

`dots-local/flake.nix` sets `distro`, which selects alien package manager backends:

- `cachyos` -> `pacman`, `paru`
- `opensuse` -> `zypper`
- `azurelinux3` -> `tdnf`
- `azurelinux4` -> `dnf5` (Azure Linux 4.0 replaced tdnf with dnf5; CLI-relevant
  specs only - see `modules/*/*.azurelinux4-packages.nix`)
- `debian` -> `apt` (CLI-relevant specs only so far - see
  `modules/*/*.debian-packages.nix`)

Azure Linux 3 package mappings are intentionally conservative and only include packages verified to exist in the official Azure Linux 3 repositories.

## Cross-Platform Utilities

Three essential commands that work consistently across Linux (Wayland/X11), WSL, and macOS:

### `o` - File Opener

Opens files with the system default application.

```bash
o document.pdf          # Opens in PDF viewer
o image.png             # Opens in image viewer  
o https://example.com   # Opens in browser
```

**How it works:** Uses `xdg-open` (Linux), `open` (macOS), or `wslview` (WSL) depending on the auto-derived `config.core.platformBackend` (`modules/core/platform.nix`).

### Clipboard Commands

**`clipin`** - Copy to clipboard
```bash
cat file.txt | clipin    # Copy file contents
echo "text" | clipin     # Copy text
clipin < file.txt        # Copy from file
```

**`clipout`** - Paste from clipboard
```bash
clipout                  # Print to stdout
clipout > file.txt       # Save to file
clipout | grep text      # Pipe to command
```

**Features:**
- Cross-platform: Wayland (wl-clipboard), X11 (xclip), WSL (clip.exe), macOS (pbcopy)
- ANSI stripping: `clipin -s` removes color codes before copying
- WSL line ending handling: Converts CRLF automatically

### `v` - Smart File Viewer

Views files in the terminal with appropriate tools.

```bash
# Single file (interactive mode)
v README.md             # Renders markdown with glow
v image.png             # Shows image in terminal (chafa/catimg)
v app.log               # Syntax highlighted with bat

# Multiple files (continuous/streaming mode)
v *.md                  # Views all markdown files
v -c *.json | less      # Stream to less for manual control
v -p file1 file2        # Pause between files

# Flags
v -c file.md            # Continuous mode (no pager)
v -s binary.dat         # Strip ANSI colors
v -h                    # Show full help
```

**File Type Support:**

| Extension | Viewer | Notes |
|-----------|--------|-------|
| `.md` | `glow` | Renders to formatted text |
| Images | `chafa`/`catimg` → `bat` | Terminal graphics, falls back to bat |
| `.pdf` | `bat` | Falls back to bat (no dedicated PDF renderer) |
| `.mp4` | `mpv --vo=sixel` | Video playback in terminal, if `enableVideo` |
| `.csv` | `column` | Table formatting, if `enableDataFormats` |
| `.json` | `jq` | Pretty-printed, if `enableDataFormats` |
| `.log` | `bat` | With line numbers |
| `.diff` | `delta` | Side-by-side if available, else bat |
| Archives | `unzip`/`tar`/`7z`/`unrar` | Lists contents, if `enableArchives` |
| Directory | `lsd --tree` | Tree view, if `enableDirectoryTree` |
| Binary | `xxd` | Hex dump |

Each `enable*` option (`enableVideo`, `enableDirectoryTree`, `enableArchives`,
`enableDataFormats`, `enableFzfPicker`) falls back to plain `bat` (or a flat
`lsd` listing, for directories) when disabled, rather than erroring - see
`features.viewer`'s option descriptions.

**Mode Details:**
- **Single file** → Interactive (glow -t, bat with pager)
- **Multiple files** → Continuous streaming (no pager)
- **Video in continuous** → Shows metadata only
- **FZF picker** → When run with no arguments, if `enableFzfPicker`

---

# Tuning System

Optimize specific packages for your CPU microarchitecture.

## Why Tune?

Most Nix packages are built for generic `x86_64-linux` to work on any machine. If you have a modern CPU (Zen 3, Alder Lake, etc.), you can rebuild packages with flags like `-march=znver3` for better performance.

## Three Scopes

### Global (Overlay)
Replaces the package everywhere in your configuration.

```nix
# In flake.nix's tunePackagesByContext table, keyed by dotsLocal.context
# (not a per-context directory anymore - see modules/composition.nix)
tunePackagesByContext = {
  priv = {
    ripgrep.enable = true;
    fd.enable = true;
  };
  work = {};
};
```

**Use for:** Tools you always want optimized (ripgrep, fd, etc.)

### Local (PATH Shadowing)
Adds tuned version to PATH, shadows baseline.

```nix
# In modules/contexts/priv.nix (or work.nix)
features.tune.packages.bat = {
  enable = true; 
  scope = "local"; 
  mode = "fast";
};
```

**Use for:** Replacing baseline packages with tuned versions

### Wrapped (Suffix)
Creates separate binary with suffix for explicit use.

```nix
features.tune.packages.yazi = {
  enable = true; 
  scope = "wrapped"; 
  suffix = "-tuned";  # Optional, default: "-tuned"
  mode = "fast";
};
```

**Use for:** Comparing baseline vs tuned, or tools you rarely need optimized

After applying:
```bash
yazi           # Baseline version
yazi-tuned     # Optimized version
```

## Optimization Modes

| Mode | C/C++ | Rust | Use Case |
|------|-------|------|----------|
| `safe` | `-O2` | `-C opt-level=2` | Compatibility first |
| `default` | `-O3 -march=${march}` | `-C opt-level=3` | Good balance |
| `fast` | `-Ofast -ffast-math` | Aggressive opt | Maximum speed |

**Note:** `fast` mode with `-ffast-math` relaxes IEEE-754 compliance. Safe for most CLI tools, avoid for numerical/scientific code.

## Custom Flags

Override mode completely:

```nix
fd = { 
  enable = true; 
  flags = "-C target-cpu=znver3 -C opt-level=3"; 
  lang = "rust"; 
};
```

## Architecture Config

Set your CPU in `~/dots-local/flake.nix`:

```nix
{
  outputs = _: 
    let
      march = "znver3";     # Your CPU (skylake, alderlake, etc.)
      barch = "x86_64-v3";  # Baseline level (v2/v3/v4)
    in {
      inherit barch march;
      
      # Override defaults per language/mode
      tune.flags.c.fast = "-Ofast -march=${march} -ffast-math";
    };
}
```

Common `march` values: `znver3` (AMD Zen 3), `skylake`, `alderlake`, `sapphirerapids`

## Build Variants

- **`default`** - Baseline, uses cache.nixos.org + tune overlay
- **`default-opt`** - Rebuilds everything with `localSystem.gcc.arch` set
  from `dotsLocal.march`

Which context (priv/work) you get comes from `dots-local`'s `context`
field, not the flake output name - `default`/`default-opt` only choose
baseline vs. optimized. Baseline is faster to install; the optimized
variant rebuilds all packages locally (takes hours first time).

## Commands

```bash
apply-dots           # Baseline build (homeConfigurations.default)
apply-dots opt       # Fully optimized (homeConfigurations.default-opt)

update-dots          # Update flake inputs
which yazi-tuned     # Verify tuned version exists
```

## AppImages

Two modes supported: **host-local** (runtime, outside Nix store) and **shared** (Nix store).

### Host-Local AppImages (Recommended for most)

Store AppImages in `~/Applications/AppImages/` (or customize via `features.appimages.localDir`).
These run directly without importing into the Nix store.

App **definitions** (file pattern, command, desktopName, categories) live in dots's shared catalog - `contexts/<context>/appimages/manifest.nix` - so they don't need to be copy-pasted into every machine's `dots-local`:

```nix
# dots/contexts/priv/appimages/manifest.nix
{
  steam = {
    file = "Steam-*.AppImage";   # Glob pattern - must match exactly one file
    command = "steam";           # Wrapper command name
    desktopName = "Steam";
    categories = [ "Game" ];
    enable = false;              # Catalog entries default OFF - opt-in per machine
  };
}
```

`~/dots-local/appimages.nix` then only needs to **enable** the apps a given machine actually wants:
```nix
{
  steam.enable = true;
}
```

Or **override a specific field** for this machine only - merged per-field on top of the catalog entry (not a whole replace), so everything you don't mention still comes from the catalog:
```nix
{
  steam = {
    enable = true;
    file = "Steam-Different-Build-*.AppImage";  # only this field is overridden
  };
}
```

A genuinely new app not worth adding to the shared catalog can still be fully defined directly in `dots-local/appimages.nix` (needs at least `file` + `command`, same shape as a catalog entry).

Place the AppImage file and ensure it's executable:
```bash
cp ~/Downloads/Steam-1.0.0.85.AppImage ~/Applications/AppImages/
chmod +x ~/Applications/AppImages/Steam-1.0.0.85.AppImage
```

The wrapper requires exactly one file matching the pattern. It will error if:
- No file matches (you need to place the AppImage)
- Multiple files match (you have multiple versions - keep only one)
- The file is not executable (run `chmod +x`)

### Shared AppImages (Nix Store)

For AppImages that work fine from the Nix store, use shared manifests:

```nix
# In contexts/common/appimages/manifest.nix or contexts/<context>/appimages/manifest.nix
{
  cursor = {
    src = ./Cursor.AppImage;     # Nix path, imported into store
    command = "cursor";
    desktopName = "Cursor";
    categories = [ "Development" ];
  };
}
```

Shared AppImages are updated in the dots repo, then `apply-dots` re-imports them.

### Commands

```bash
# Update registered host-local AppImages (default)
update-appimages

# Update specific app
update-appimages steam

# Update all AppImages in localDir (including unregistered)
update-appimages --unregistered

# Update everything: host-local + unregistered + shared
update-appimages --all

# Update shared AppImages in dots repo
update-appimages --include-shared
```

Exec bit is preserved during updates: if an AppImage was executable before update, it will be chmod +x after.

### Enable/Disable Individual Apps

In `modules/contexts/<context>.nix`, or `dots-local`'s `extraModules` for
something more host-specific:
```nix
features.appimages = {
  enable = true;
  apps = {
    steam.enable = false;    # Disable even if in manifest
  };
};
```

## Alien Packages (Native Package Management)

Manage native distro packages alongside Nix packages. This allows mixing Nix and native package managers (pacman, paru, zypper) for cases where native packages work better.

### Why Alien Packages?

Some packages work better when installed natively:
- **System integration** - Better desktop integration, file associations
- **Faster updates** - No need to wait for Nixpkgs
- **Native dependencies** - Some apps expect system libraries
- **Distribution-optimized** - Packages compiled for your specific distro

### How It Works

1. Define packages in `<feature>.<distro>-packages.nix` files
2. Suites/features declare which alien packages they need
3. Dots generates package lists per package manager
4. Use `update-alien-packages` to install/manage them

### Defining Alien Packages

Create a `<feature>.<distro>-packages.nix` file next to your feature:

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

The spec is looked up purely by package **name** (`ghostty` above,
matched against whatever `pkgName` a suite/feature's `mkAppSet`/
`alien.mkEntry` call passes) - the `<feature>` prefix in the filename
is just a human-organizing convention (keep a suite/feature's alien
specs next to its own module file), not something any code reads. A
package can be, and often is, consumed by more than one suite/feature
(e.g. `lazygit`'s spec lives in `tui-apps.cachyos-packages.nix` but is
also used by `suites.git-tools.lazygit`) - there's deliberately no
single "owning feature" field on a spec.

### Using Alien Packages in Features

Features check if an alien package exists and skip the Nix version. For
suites with more than a couple of toggles, use `modules/core/lib.nix`'s
`mkAppSet` helper instead of repeating the `alien.mkEntry`/
`alienPackages.enabledPackages` boilerplate by hand for every single
toggle:

```nix
{ config, lib, pkgs, alien, ... }:

let
  cfg = config.suites.tui-apps;
  coreLib = import ../core/lib.nix { inherit lib; };
  appSet = coreLib.mkAppSet {
    inherit alien;
    apps = {
      yazi = { enable = cfg.yazi; pkg = pkgs.yazi; };
      # `alienName` when the alien-spec key differs from the toggle name:
      deltachat = { enable = cfg.deltachat; pkg = pkgs.deltachat-desktop; alienName = "deltachat-desktop"; };
    };
  };
in {
  options.suites.tui-apps = {
    enable = lib.mkEnableOption "Enable interactive TUI tools";
    yazi = lib.mkEnableOption "Yazi file manager";
    deltachat = lib.mkEnableOption "Delta Chat";
  };

  config = lib.mkIf cfg.enable {
    home.packages = appSet.packages;
    alienPackages.enabledPackages = appSet.alienEnabled;
  };
}
```

For a single one-off toggle, the manual `alien.mkEntry`/
`alienPackages.enabledPackages` pattern (without `mkAppSet`) is still fine
and reads more directly:

```nix
config = lib.mkIf cfg.enable {
  home.packages = builtins.filter (p: p != null) [
    (alien.mkEntry cfg.yazi "yazi" pkgs.yazi)
  ];
  alienPackages.enabledPackages = lib.optional cfg.yazi "yazi";
};
```

### Commands

```bash
# Update: Install missing packages, detect orphans (default)
update-alien-packages
update-alien-packages --target pacman

# Install only: Skip orphan detection
update-alien-packages --action install --target pacman

# Remove orphans: Interactively remove orphaned packages
update-alien-packages --action remove --target pacman
```

### Package Tracking

Alien packages are tracked in `~/.local/share/dots/packages/`:

```
~/.local/share/dots/packages/
├── required/
│   ├── pacman.txt      # What dots wants NOW
│   └── paru.txt
├── installed/
│   ├── pacman.txt      # What was last installed
│   └── paru.txt
└── orphaned/
    ├── pacman.txt      # Packages to review for removal
    └── paru.txt
```

**Orphan Detection:** When you disable a package in dots, it's detected as an orphan. Run `update-alien-packages --action remove` to clean them up.

**Manual Removals:** If you manually remove a package, dots will detect it and offer to reinstall (with `update` or `install` action).

## Tips

- **Start small:** Tune 2-3 CLI tools you use constantly
- **Use global scope** for daily tools (ripgrep, fd)
- **Use wrapped scope** to test before committing to global
- **Custom flags** when you know exactly what you want
- **Baseline profiles** are fine for most use - optimization is diminishing returns
