# Modular Nix Home Environment

A declarative, reproducible home setup for Linux workstations with per-machine optimization.

## What You Get

- **Declarative config** - Your entire environment defined in code
- **Modular features** - Enable only what you need (AI, terminal, apps, etc.)
- **Per-machine tuning** - Optimize packages for your specific CPU
- **Two contexts** - Separate work and personal configurations
- **Fast or optimized builds** - Use cache or rebuild with microarchitecture flags

## Quick Start

```bash
# 0. Prerequisite: install Nix, if not already present (see install.sh -
#    uses the Determinate Systems installer with --no-modify-profile,
#    matching this repo's own nixon/nixoff design; no shell profile
#    edits needed - setup.sh finds `nix` on its own even on a brand-new
#    terminal right after this)
./install.sh

# First time setup
./setup.sh --list  # List available distros and contexts
./setup.sh cachyos priv    # Creates ~/dots-local with your identity

# Daily workflow
apply-dots         # Apply your config (baseline, uses cache.nixos.org)
apply-dots opt     # Optimized for your CPU (slower, faster binaries)

# Manage native packages
update-alien-packages                    # Install missing native packages
update-alien-packages --action remove    # Clean up orphaned packages

# Manage AppImages
update-appimages                          # Update registered AppImages
update-appimages --all                    # Update all AppImages
```

Which context (priv/work) and machine-specific behavior (GPU, compositor,
display, etc.) you get is fully determined by `dots-local/flake.nix` -
there's no context name to pass on the command line, only the
baseline-vs-optimized build choice (see Architecture below).

## Feature System

Enable features in `modules/contexts/priv.nix` or `modules/contexts/work.nix`:

```nix
# Core environment (always enabled via common context)
features.viewer.enable = true;                 # Terminal file viewer ('v' command)
features.network.enable = true;                # SSH/GPG agents

# GUI and applications
features.opener.enable = true;                 # File opener ('o' command)
features.clipboard.enable = true;              # Clipboard manager (clipin/clipout)
features.fonts.enable = true;                  # Font configuration
# Both opener/clipboard read the shared config.core.platformBackend
# (modules/core/platform.nix, derived from dotsLocal.isWsl/compositor/
# graphicalBackend) - no per-feature backend option to set yourself.

# Application suites
suites.gui-apps.enable = true;                 # GUI applications (browser, editor, etc.)
suites.gui-apps.chromium = true;               # Specific apps
suites.tui-apps.enable = true;                 # TUI tools (btop, yazi, etc.)
suites.sixel-tools.enable = true;              # Terminal graphics (chafa, mpv)
suites.ai-apps.enable = true;                  # AI tooling (opencode, grabcontext)
suites.ai-apps.opencode = true;
suites.scanning.enable = true;                 # Document scanning tools
suites.git-tools.enable = true;                # Git tooling (delta, lazygit, etc.)
suites.dev-tools.enable = true;                # Dev tools (nixd, entr, rust, etc.)
suites.network-tools.enable = true;            # Network CLI tools (nmap, rclone, doggo, xh)

# Tuning
features.tune.enable = true;                   # Package optimization
features.tune.packages.ripgrep = {             # Tune specific packages
  enable = true; mode = "fast"; lang = "rust";
};

# AppImages
features.appimages.enable = true;              # Host-local AppImage support
```

### Available Features & Suites

**Features** (`features.<name>`) - Individual capabilities:

| Feature | Options | Description |
|---------|---------|-------------|
| `appimages` | `enable`, `localDir`, `apps` | Host-local AppImage integration |
| `bookokrat` | `enable` | Documentation tool |
| `butterfish` | `enable`, `baseUrl`, `apiKey`, `model`, `shell` | Shell wrapper for local/OpenAI-compatible LLMs (`bf` command) |
| `clipboard` | `enable` | Cross-platform clipboard (clipin/clipout) - backend auto-derived, see `core.platformBackend` |
| `fonts` | `enable` | Font configuration |
| `llama-cpp` | `enable`, `cmakeFlags` | llama.cpp built with CUDA + march-tuned flags |
| `network` | `enable`, `sshAgent`, `gpgAgent`, `gpgSsh` | SSH/GPG agents |
| `niri-noctalia` | `enable`, `renderDrmDevice`, `terminal` | Niri compositor with Noctalia integration |
| `nix` | `enable`, `nh`, `nvd`, `nixDiff`, `nixTree`, `nixLocate`, `deadnix`, `statix`, `manix`, `envfs`, `nixIndex`, `cachix`, `comma` | Nix tooling (helpers, linters, diffing, search) - not enabled on any host today |
| `opener` | `enable`, `alias` | Cross-platform file opener (`o` command) - backend auto-derived, see `core.platformBackend` |
| `quarkdown` | `enable` | Markdown typesetting system |
| `sd-switch` | `enable` | Aggressive systemd --user service restarts on activation |
| `tune` | `enable`, `packages` | Package optimization (see [OVERVIEW.md](OVERVIEW.md)) |
| `viewer` | `enable`, `alias`, `ripgrepAll`, `preferImageViewer`, `enableVideo`, `enableDirectoryTree`, `enableArchives`, `enableDataFormats`, `enableFzfPicker` | Terminal file viewer (`v` command) |
| `wsl-shell-integration` | `enable` | VSCode Remote-SSH + WSL2 shell integration compatibility fixes |

**Suites** (`suites.<name>`) - Bundled application groups:

| Suite | Options | Description |
|---------|---------|-------------|
| `ai-apps` | `enable`, `opencode`, `grabcontext` | AI assistants and context tools |
| `cloud-tools` | `enable`, `aws`, `azure`, `gcp`, `k8s` | Cloud CLI tools |
| `dev-tools` | `enable`, `nixd`, `entr`, `rust`, `python`, ... | Development tooling |
| `git-tools` | `enable`, `git`, `jj`, `delta`, `lazygit` | Version control tools |
| `gui-apps` | `enable`, `ghostty`, `librewolf`, `vscodium`, `keepassxc`, ... | Desktop GUI applications |
| `network-tools` | `enable`, `nmap`, `rclone`, `doggo`, `xh` | Network CLI tools |
| `pim-apps` | `enable`, `superproductivity` | Personal information management |
| `scanning` | `enable`, `simple-scan`, `gscan2pdf`, `tesseract` | Document scanning tools |
| `sixel-tools` | `enable`, `chafa`, `catimg`, `mpv`, `ytdlp` | Terminal graphics & media |
| `tui-apps` | `enable`, `btop`, `yazi`, `zellij`, `lazygit`, ... | Terminal UI applications |

## Essential Commands

Daily workflow commands (installed via Home Manager):

```bash
# Apply configuration
apply-dots                    # Baseline build (homeConfigurations.default)
apply-dots opt                # Optimized build for your CPU (default-opt)
apply-dots -- -b backup       # Pass arguments to nh home switch
apply-dots opt -- -b backup --dry  # Optimized build + nh arguments

# Update flake inputs
update-dots                   # Update all flake inputs
update-dots nixpkgs           # Update specific input
update-dots -- --refresh      # Pass arguments to nix flake update

# Sync handcrafted configs
dots-sync                     # Sync system → git (safe mode)
dots-sync -f                  # Force sync (overwrite git)
dots-sync -i                  # Generate install script (git → system)
dots-sync -n                  # Dry run (preview changes)
dots-sync -g                  # Force-regenerate sync-config.json

# Discover every option settable in dots-local/flake.nix
dots-local-options            # Show everything (path/type/default/description)
dots-local-options machine    # Filter by substring (e.g. only machine.*)
```

Three cross-platform utilities for daily workflow:

### `o` - File Opener (opener)

Opens files with the default application (xdg-open, open, wslview, etc.)

```bash
o file.pdf              # Open PDF in default viewer
o image.png             # Open image
o https://example.com   # Open URL in browser
```

Configuration:
```nix
features.opener = {
  enable = true;
  alias = "o";          # Custom alias name
};
```

Backend (wayland/x11/wsl/macos) is auto-derived from `dotsLocal.isWsl`/
`compositor`/`graphicalBackend` - see `config.core.platformBackend`
(`modules/core/platform.nix`), not something you set on `features.opener`
itself.

### `clipin`/`clipout` - Clipboard (clipboard)

Cross-platform clipboard commands supporting Wayland, X11, WSL, and macOS.

```bash
clipin < file.txt       # Copy file contents to clipboard
echo "text" | clipin     # Copy text to clipboard
clipout > file.txt      # Paste to file
clipout                 # Print clipboard contents
```

Configuration:
```nix
features.clipboard = {
  enable = true;
};
```

Backend is auto-derived the same way as `features.opener` above - see
`config.core.platformBackend`.

### `v` - Terminal File Viewer (viewer)

Smart file viewer that picks the right tool based on file type.

```bash
v file.md               # Render markdown with glow
v image.png             # View image in terminal (chafa/catimg, falls back to bat)
v document.pdf          # View PDF in terminal (bat)
v video.mp4             # Play video (mpv --vo=sixel)
v *.log                 # View multiple files (continuous mode)
v -c *.json | less      # Stream to less (continuous mode)
v -s binary.dat         # Strip ANSI colors
```

Flags:
- `-c` / `--continuous` - Stream to stdout (no pager)
- `-p` / `--pager` - Pause between multiple files
- `-s` / `--strip` - Strip ANSI color codes
- `-h` / `--help` - Show help

Configuration:
```nix
features.viewer = {
  enable = true;
  alias = "v";
  preferImageViewer = "chafa";  # chafa or catimg
  enableVideo = true;           # mpv --vo=sixel for video files (else metadata only)
  enableDirectoryTree = true;   # lsd --tree for directories (else flat listing)
  enableArchives = true;        # List zip/tar/7z contents (else plain bat)
  enableDataFormats = true;     # Pretty print csv/json/yaml (else plain bat)
  enableFzfPicker = true;       # Interactive picker when called with no args
  ripgrepAll = true;            # Also install ripgrep-all (rga)
};
```

**Multi-file behavior:** Multiple files default to continuous mode (streaming). Interactive tools (mpv, glow -t) only work with single files or `-p` flag.

## Alien Packages

Mix native distro packages (pacman, paru, zypper) with Nix packages for better system integration.

```bash
# Install/update native packages (defined in .cachyos-packages.nix, etc.)
update-alien-packages

# Show orphaned packages (previously installed but no longer required)
update-alien-packages --action remove

# Per-package manager
update-alien-packages --target pacman
```

Packages are tracked in `~/.local/share/dots/packages/`:
- `required/` - What dots wants now
- `installed/` - What was last installed
- `orphaned/` - Packages to review for removal

See [OVERVIEW.md](OVERVIEW.md#alien-packages-native-package-management) for details on defining alien packages.

## Architecture

**Two-repo design:**
- `dots/` - Shared configuration (this repo), contains no machine-specific
  state
- `~/dots-local/` - Private identity, hardware/context axes, tuning flags
  (see `modules/local/schema.nix` for the full typed schema)

**Distro values (in `~/dots-local/flake.nix`):**
- `cachyos` -> `pacman` + `paru`
- `opensuse` -> `zypper`
- `azurelinux3` -> `tdnf`
- `azurelinux4` -> `dnf5` (Azure Linux 4.0 replaced tdnf with dnf5)
- `debian` -> `apt`

All of `azurelinux3`/`azurelinux4`/`debian` are structurally supported with
CLI-relevant, conservative/official-repos-only specs - not yet verified on
real hardware for those distros.

**Flake outputs:**
- `default` - Baseline, uses cache.nixos.org
- `default-opt` - Optimized with `localSystem.gcc.arch` set from
  `dots-local`'s `march` (rebuilds locally)

**Composition:** `modules/composition.nix` always imports the common
baseline plus a `modules/contexts/<dots-local.context>.nix` bundle (`priv`
or `work`), then applies `modules/rules.nix` - small, declarative rules
over `dots-local` axes (GPU, compositor, WSL, ...) that enable/configure
features as *defaults*. No per-host directory or file is required to
exist - host-specific config comes from `dots-local` fields (`machine.*`,
`gpu`, `compositor`, ...) or, for anything too bespoke to generalize,
`dots-local`'s `extraModules`/`extraOverlays` escape hatches.

## Environment Variables

Customize dots behavior with these environment variables:

```bash
export DOTS_DIR="$HOME/dots"           # Location of dots repository
export DOTS_LOCAL_DIR="$HOME/dots-local"  # Location of dots-local repository
```

These are automatically set if not defined. Useful for non-standard setups.

### `$NIXON` - nix-managed vs. pure host shell

Every interactive/login shell is gated by `$NIXON` (see
`modules/core/nixon.nix`):

- `NIXON=1` ("nix-on"): the full Home Manager environment is loaded
  (`~/.bashrc-nix`/`~/.profile-nix` - PATH, aliases, shell integrations
  from every enabled feature/suite).
- `NIXON=0`: a stripped-down "pure host" environment - all `/nix/store`
  paths removed from `$PATH`, keeping only the bare `nix`/`nh`/
  `home-manager` binaries reachable (via `/nix/var/nix/profiles/
  default/bin`) so you can still run `apply-dots`/`nixon` to get back.

Toggle between them at any time with the `nixon`/`nixoff` aliases (each
`exec`s a fresh login shell with `$NIXON` set accordingly). The default
for a brand-new shell (before either alias has ever been run) comes
from `dotsLocal.nixonDefault` (`true`/`false`) - set this explicitly in
your `dots-local/flake.nix` rather than relying on its schema default,
so your intended behavior is always visible in your own config rather
than implicit.

## Navigation Tips

**Module Structure:**
```
modules/
├── contexts/         # Composition bundles, selected by dots-local.context
│   ├── common.nix    # Always-imported minimal CLI baseline
│   ├── priv.nix      # Personal context
│   └── work.nix      # Work context
├── composition.nix   # Entry point - imports core + context + rules
├── rules.nix         # Declarative axis-based rules (GPU, WSL, ...)
├── local/
│   └── schema.nix    # Typed schema for dots-local/flake.nix
├── core/             # Core infrastructure
├── features/         # Individual capabilities
└── suites/           # Bundled application groups
```

## Adding a New Host

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
      sshAddKeysToAgent = "yes";            # "yes"/"no"/"ask"/"confirm"/a duration like "10m"
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

Then run `apply-dots`. Run `dots-local-options` to see every available
field (path/type/default/description), generated live from
`modules/local/schema.nix` - never a separate doc to fall out of sync.

## Troubleshooting

### Activation Failures

**File collision errors:**
```
Existing file '/home/user/.config/niri/config.kdl' would be clobbered
```

Solutions:
```bash
# Option 1: Backup conflicting files
apply-dots -- -b backup

# Option 2: Remove the conflicting file manually
mv ~/.config/niri/config.kdl ~/.config/niri/config.kdl.backup
apply-dots

# Option 3: Force overwrite (use with caution)
apply-dots -- --force
```

**Build succeeds but activation fails:**
1. Check the log path shown in the error message
2. Run activation manually to see full error:
   ```bash
   /nix/store/...-home-manager-generation/activate
   ```

### Common Issues

**Stale sync-config.json:**
```bash
dots-sync -g  # Force regenerate from flake.nix
```

**Context not found:**
Ensure `dots-local/flake.nix` has a valid `context` attribute (e.g., `context = "priv";`). Run `./setup.sh --list` to see available distros and contexts.

**Nix evaluation errors:**
```bash
# Test evaluation without building
nix eval .#homeConfigurations.default --override-input dots-local git+file://$HOME/dots-local
```

### Getting Help

- Check full build logs in `/tmp/apply-dots-*.log` on failure
- Use `--dry` flag to test without activating: `apply-dots -- --dry`
- See [OVERVIEW.md](OVERVIEW.md) for detailed architecture
- Review [SYNC.md](SYNC.md) for sync system documentation
