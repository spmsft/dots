# Formal schema for `dots-local`'s flake output, evaluated via
# `lib.evalModules` in flake.nix (see flake.nix's `dotsLocal` binding).
#
# Every option here has a description and (where sensible) a default, so
# `dots-local/flake.nix` only needs to override what's actually specific to
# that machine/identity - anything left unset falls back to a documented,
# safe default.
#
# DESIGN NOTE: existing fields deliberately keep their flat names/shape
# (host, distro, march, realname, ...) rather than a fully-nested
# identity.*/machine.*/system.* design, to avoid requiring a rewrite of the
# live dots-local/flake.nix. Axis fields (gpu, isWsl, location, tags,
# shell.*, extraModules, extraOverlays) feed rules.nix and
# beyond.

{ lib, ... }:

let
  inherit (lib) mkOption types;
in {
  options = {
    # --- Core identity (required - no generic default makes sense) ---
    username = mkOption {
      type = types.str;
      description = ''
        Unix username on this machine. Required - used for
        `home.username` (flake.nix) and hardcoded paths in a few features
        (e.g. dev-tools.nix's .nixd.json).
      '';
    };

    homeDirectory = mkOption {
      type = types.str;
      description = ''
        Absolute path to the user's home directory. Required - used for
        `home.homeDirectory` (flake.nix).
      '';
    };

    realname = mkOption {
      type = types.str;
      description = "Real name for git commits (programs.git.settings.user.name). Required.";
    };

    realmail = mkOption {
      type = types.str;
      description = "Email for git commits (programs.git.settings.user.email). Required.";
    };

    # --- Machine / system axes ---
    system = mkOption {
      type = types.str;
      default = "x86_64-linux";
      description = "Nix system string (target platform triple).";
    };

    host = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Hostname. Informational/display use (e.g. shown by
        modules/core/dots-local.nix's activation info) - machine-specific
        behavior itself is driven by the other axis fields below
        (`machine.*`, `gpu`, `compositor`, ...), not by `host` directly.
      '';
    };

    context = mkOption {
      type = types.str;
      default = "priv";
      description = ''Which dots context to use (e.g. "priv", "work"). Selects the modules/contexts/<context>.nix bundle.'';
    };

    distro = mkOption {
      type = types.str;
      default = "unknown";
      description = ''
        Linux distro identifier, selects the alien-package backend
        (`*.<distro>-packages.nix` spec suffix). Known values: cachyos,
        opensuse, azurelinux3, azurelinux4, debian.
      '';
    };

    isWsl = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether this machine is running under WSL. Orthogonal to `distro`
        (e.g. a Debian distro running inside WSL is `distro = "debian";
        isWsl = true;`). Consumed by rules.nix's `isWsl` rule.
      '';
    };

    uid = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Unix UID. Currently unused by dots itself (kept for potential
        future use / dots-local's own convenience) - see
        memory-bank/open-questions.md.
      '';
    };

    gid = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Unix GID. Currently unused by dots itself, same status as `uid`
        above.
      '';
    };

    march = mkOption {
      type = types.str;
      default = "native";
      description = ''
        CPU microarchitecture (e.g. "znver5", "skylake", "alderlake") used
        by the tuning system's default flag tables. NOTE: the `-opt`
        profile builds currently hardcode "znver5" directly in flake.nix
        rather than reading this value - see memory-bank/open-questions.md.
      '';
    };

    barch = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Baseline microarchitecture level (e.g. "x86_64-v3"). NOTE: not
        currently consumed anywhere in dots (see march's note above about
        the -opt profile). Kept for forward-compat.
      '';
    };

    gpu = mkOption {
      type = types.nullOr (types.enum [ "nvidia" "amd" "intel" ]);
      default = null;
      description = ''
        GPU vendor present on this machine, if any. Consumed by
        rules.nix: gpu == "nvidia" pulls in the llama-cpp
        feature and the ai-apps "pi" toggle by default.
      '';
    };

    compositor = mkOption {
      type = types.nullOr (types.enum [ "niri" ]);
      default = null;
      description = ''
        Which Wayland compositor/desktop this machine uses, if any.
        Consumed by rules.nix to enable features.niri-noctalia
        and default its terminal/renderDrmDevice options from
        `machine.terminal`/`machine.renderDrmDevice`. Null means no
        compositor-managed desktop (e.g. a CLI-only or WSL machine).
      '';
    };

    machine = mkOption {
      default = { };
      description = ''
        Per-machine hardware/peripheral config, consumed by generic
        (not host-specific) feature modules. Anything NOT covered by a
        field here and too bespoke to generalize (e.g. exact
        CUDA/llama.cpp cmakeFlags for one particular GPU) belongs in
        `extraModules` instead.
      '';
      type = types.submodule {
        options = {
          sshIdentityFile = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = ''
              SSH identity file for this host's default `Host *` block
              (e.g. "~/.ssh/id_github_<host>"). Null skips setting one -
              consumed by features/network.nix.
            '';
          };

          sshAddKeysToAgent = mkOption {
            type = types.str;
            default = "yes";
            description = ''
              Value for ssh's `AddKeysToAgent` setting in the default
              `Host *` block - only applied when `sshIdentityFile` is
              also set (consumed by features/network.nix). Accepts any
              value ssh_config itself allows: "yes", "no", "ask"
              (prompt every time before adding), "confirm" (prompt before
              each use of an already-added key), or a duration like
              "10m"/"1h" (auto-remove after that long).
            '';
          };

          terminal = mkOption {
            type = types.str;
            default = "ghostty";
            description = ''
              Terminal emulator command, used as the default for
              features.niri-noctalia.terminal (only meaningful when
              `compositor == "niri"`).
            '';
          };

          renderDrmDevice = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = ''
              DRM render node for niri (e.g. "/dev/dri/render_amd"). Null
              lets niri auto-detect. Only meaningful when
              `compositor == "niri"`.
            '';
          };

          display = mkOption {
            default = null;
            description = ''
              Display config for the power-toggle eco/perf script
              (features/power-toggle.nix). Null disables that feature
              entirely (no power-toggle.sh installed).
            '';
            type = types.nullOr (types.submodule {
              options = {
                output = mkOption {
                  type = types.str;
                  description = ''wlr-randr output name (e.g. "eDP-1").'';
                };
                ecoMode = mkOption {
                  description = "Display settings applied in eco mode.";
                  type = types.submodule {
                    options = {
                      resolution = mkOption { type = types.str; description = "e.g. \"1920x1200\"."; };
                      refreshRate = mkOption { type = types.str; default = "60.000"; description = "Refresh rate in Hz (as wlr-randr expects, e.g. \"60.000\")."; };
                      brightness = mkOption { type = types.str; default = "30%"; description = "brightnessctl set value."; };
                    };
                  };
                };
                perfMode = mkOption {
                  description = "Display settings applied in performance mode.";
                  type = types.submodule {
                    options = {
                      resolution = mkOption { type = types.str; description = "e.g. \"1920x1200\"."; };
                      refreshRate = mkOption { type = types.str; default = "120.000"; description = "Refresh rate in Hz."; };
                    };
                  };
                };
              };
            });
          };
        };
      };
    };

    # --- Desktop / GUI ---
    enableGuiDefaults = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether to enable GUI-related suites/features by default
        (gui-apps, pim-apps superproductivity, etc).
      '';
    };

    graphicalBackend = mkOption {
      type = types.enum [ "none" "wayland" "x11" "wsl" "macos" ];
      default = "none";
      description = ''
        Desktop/platform backend, used by features.opener/
        features.clipboard and (in future) other platform-aware features.
        Only actually consulted when `compositor` is non-null (see
        modules/core/platform.nix) - "none" is the correct default for a
        CLI-only machine with no graphical desktop at all, rather than
        defaulting to "wayland" as if every machine had one.
        `config.core.enableGuiDefaults` (modules/core/platform.nix) is
        also forced off whenever this is "none", regardless of
        `enableGuiDefaults`'s own value - a machine with no graphical
        backend shouldn't get GUI apps installed. Enum-typed, so an
        invalid value is rejected at eval time with a clear error.
      '';
    };

    nixonDefault = mkOption {
      type = types.bool;
      default = false;
      description = "Default value of $NIXON (1=nix-managed shell, 0=native host shell) on a fresh login.";
    };

    # --- Location / freeform tags (new axes, inert for now) ---
    location = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Freeform physical/network "situation" tag (e.g. "home", "parents",
        "travel", "office"). Not yet consumed by any module - reserved for
        future location-aware features (VPN/proxy/DNS, etc).
      '';
    };

    tags = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        Open-ended list of capability/context tags for anything not yet
        modeled as a first-class option here.
      '';
    };

    # --- Butterfish / local LLM endpoint ---
    butterfishEndpoint = mkOption {
      type = types.str;
      default = "http://127.0.0.1:5001/v1";
      description = "Butterfish's OpenAI-compatible endpoint URL (e.g. a local llama.cpp server).";
    };

    butterfishApiKey = mkOption {
      type = types.str;
      default = "talk-to-me";
      description = "API key sent to the butterfish endpoint (often meaningless for local servers).";
    };

    butterfishModel = mkOption {
      type = types.str;
      default = "default";
      description = "Model name to request from the butterfish endpoint.";
    };

    # --- AppImages ---
    appimagesDir = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Directory to look for host-local AppImages in. If null,
        features.appimages falls back to
        "''${config.home.homeDirectory}/Applications/AppImages".
      '';
    };

    appimages = mkOption {
      type = types.attrsOf (types.submodule {
        # freeformType keeps this lenient - dots-local's own appimages.nix
        # may have extra/misspelled keys (e.g. a stray `dektopName` typo
        # exists there today); we validate the known fields without
        # rejecting the whole entry over an unrecognized one.
        freeformType = types.attrsOf types.anything;
        options = {
          # file/command are nullable (rather than required) because
          # dots-local's entries are often just an *override* of a subset
          # of fields for an app already fully defined in dots's shared
          # catalog (contexts/<context>/appimages/manifest.nix) - e.g.
          # `{ tuta.enable = true; }` to enable a catalog app, or
          # `{ tuta.file = "..."; }` to override just the file pattern.
          # modules/features/appimages.nix deep-merges (per-field, not a
          # whole-entry replace) dotsLocal.appimages on top of the shared
          # catalog, so file/command only need to be set here for a
          # genuinely new, not-yet-cataloged app.
          file = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Glob pattern matching exactly one AppImage file.";
          };
          command = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Wrapper command name to install on PATH.";
          };
          desktopName = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Display name for the .desktop entry.";
          };
          categories = mkOption {
            type = types.nullOr (types.listOf types.str);
            default = null;
            description = "XDG desktop categories.";
          };
          enable = mkOption {
            # NOTE: `nullOr bool` (not a plain `bool` with a default),
            # deliberately - modules/features/appimages.nix strips every
            # null-valued field from a dots-local entry before merging it
            # onto dots's shared catalog (see its comment for why), so
            # that a partial override like `{ tuta.enable = true; }`
            # doesn't accidentally reset every OTHER field of a cataloged
            # app back to a schema default. If `enable` used a real
            # `default = true;` here instead of `null`, that default
            # would be indistinguishable from an actual user override and
            # would incorrectly stomp the catalog's own `enable = false;`
            # on every partial-override entry, even ones not touching
            # `enable` at all.
            type = types.nullOr types.bool;
            default = null;
            description = ''
              Whether to install this AppImage wrapper. `null` (the
              default) means "don't override - use whatever the merged
              entry already resolves to" (the shared catalog's own
              `enable`, or `true` if this is a brand new, not-cataloged
              app with no `enable` set anywhere).
            '';
          };
        };
      });
      default = { };
      description = ''
        Per-machine AppImage enable/override entries, merged (per-field)
        on top of dots's shared catalog
        (contexts/<context>/appimages/manifest.nix) - see OVERVIEW.md's
        AppImages section. Only needs `file`/`command`/etc for apps not
        already in the shared catalog; for cataloged apps, a bare
        `{ appname.enable = true; }` is enough.
      '';
    };

    # --- Tuning ---
    tune = mkOption {
      default = { };
      description = "Per-language/mode compiler flag overrides for the package-tuning system.";
      type = types.submodule {
        options.flags = mkOption {
          type = types.attrsOf (types.attrsOf types.str);
          default = { };
          description = ''
            Override table: flags.<lang>.<mode> = "compiler flags string".
            Anything left unset falls back to the built-in defaults in
            modules/core/tune-defaults.nix.
          '';
        };
      };
    };

    # --- Taskwarrior / TaskChampion sync ---
    taskSync = mkOption {
      default = { };
      description = ''
        Taskwarrior/TaskChampion sync configuration, consumed by
        modules/features/task-sync.nix. Entirely inert by default: no
        `~/.taskrc` sync block is ever written unless BOTH a server URL
        (explicit `url`, or implied by `autoSpawnServer`) AND `credential`
        are set - see each field's own description below.
      '';
      type = types.submodule {
        options = {
          autoSpawnServer = mkOption {
            type = types.bool;
            default = false;
            description = ''
              Whether to run a local `taskchampion-sync-server` on this
              machine as a systemd user service (auto-started via
              `default.target`, so it comes up automatically on login -
              no shell-startup hook needed). When true and `url` is left
              null, the client-side `sync.server.url` written to
              `~/.taskrc` defaults to `http://127.0.0.1:<port>`
              (loopback, since the client and server are the same
              machine here) regardless of `interface`.
            '';
          };

          interface = mkOption {
            type = types.str;
            default = "127.0.0.1";
            description = ''
              Bind address for the auto-spawned `taskchampion-sync-server`
              (only meaningful when `autoSpawnServer` is true). Leave at
              the loopback default for a single-machine setup; set to
              "0.0.0.0" (or a specific interface address) to accept sync
              connections from other machines on the network.
            '';
          };

          port = mkOption {
            type = types.port;
            default = 9999;
            description = ''
              Port for the auto-spawned `taskchampion-sync-server`, and
              the port assumed by the computed default `url` (see
              `autoSpawnServer`'s description) when `url` is left null.
            '';
          };

          url = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = ''
              Taskwarrior's `sync.server.url`. Null means "compute a
              default from `autoSpawnServer`/`port` if this machine hosts
              its own server, else leave sync unconfigured" - set this
              explicitly to point at a server running on a *different*
              machine (e.g. `"http://otherhost:9999"`).
            '';
          };

          credential = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = ''
              Shared Taskwarrior `sync.encryption_secret` - the actual
              end-to-end encryption credential. Must be byte-identical on
              every device syncing against the same server. Null (the
              default) means no `~/.taskrc` sync block is written at all,
              even if `url`/`autoSpawnServer` are set. Stored in plaintext
              here (same tradeoff as `butterfishApiKey` above - this repo
              has no secrets-encryption layer) - `setup.sh` pre-generates
              a random value into the template's commented-out example so
              you don't have to invent a secure secret by hand, and both
              `setup.sh` and `modules/core/dots-local.nix` keep this
              directory's permissions at 0700 to at least limit plaintext
              exposure to other local users on the same machine.
            '';
          };

          syncInterval = mkOption {
            type = types.str;
            default = "never";
            description = ''
              How often to run `task sync` automatically via a systemd
              user timer, as a systemd time span (e.g. "15m", "1h"), or
              the literal string "never" (the default) to install no
              timer at all - `task sync` can always still be run
              manually regardless of this setting.
            '';
          };
        };
      };
    };

    # --- Sync ---
    sync = mkOption {
      default = { };
      description = "Settings-sync configuration (see SYNC.md).";
      type = types.submodule {
        options.enable = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = ''
            Names of dots-defined "syncables" (see
            modules/core/syncables.nix) to activate for this machine -
            e.g. `[ "noctalia" ]`. Each name resolves to a full
            pattern/type/on_new/ignore definition kept in `dots` itself,
            so machines don't need to copy-paste the same sync pattern
            into every dots-local. Read directly by sync.sh (which
            resolves names against the registry when generating
            sync-config.json) AND usable from Home Manager modules (e.g.
            a feature asserting one of its required syncables is
            enabled) since it's a real schema field, not just a raw
            flake output.
          '';
        };

        options.tracked = mkOption {
          default = [ ];
          description = ''
            Ad-hoc tracked file patterns not worth registering as a
            named syncable (one-off, machine-specific things) - full
            definitions given here directly, same shape as a syncables.nix
            entry. Merged alongside whatever `enable` resolves to.
          '';
          type = types.listOf (types.submodule {
            options = {
              pattern = mkOption {
                type = types.str;
                description = "Glob pattern for files to track.";
              };
              type = mkOption {
                type = types.enum [ "home" "root" ];
                default = "home";
                description = "Whether pattern is relative to ~ (home) or / (root).";
              };
              on_new = mkOption {
                type = types.enum [ "prompt" "auto" "ignore" ];
                default = "prompt";
                description = "How to handle newly-discovered files matching this pattern.";
              };
              ignore = mkOption {
                type = types.listOf types.str;
                default = [ ];
                description = "Additional ignore sub-patterns (supports ! negation).";
              };
            };
          });
        };
      };
    };

    # --- Easy shell customization (new - low-ceremony path, see
    # architecture.md section 1a) ---
    shell = mkOption {
      default = { };
      description = "Easy shell customization from dots-local, merged into programs.bash.*";
      type = types.submodule {
        options = {
          sessionVariables = mkOption {
            type = types.attrsOf types.str;
            default = { };
            description = "Extra environment variables, merged into programs.bash.sessionVariables.";
          };
          shellAliases = mkOption {
            type = types.attrsOf types.str;
            default = { };
            description = "Extra shell aliases, merged into programs.bash.shellAliases.";
          };
          initExtra = mkOption {
            type = types.lines;
            default = "";
            description = "Extra bash snippet, appended to programs.bash.initExtra.";
          };
        };
      };
    };

    # --- Escape hatches for highly-specialized/bespoke needs (new, see
    # architecture.md section 1b) ---
    extraModules = mkOption {
      type = types.listOf types.path;
      default = [ ];
      description = ''
        Extra Home Manager module files supplied by dots-local itself, for
        machine-specific needs too bespoke to generalize into a shared dots
        feature (keeps `dots` itself free of one-off host state).
      '';
    };

    extraOverlays = mkOption {
      type = types.listOf types.anything;
      default = [ ];
      description = ''
        Extra nixpkgs overlays supplied by dots-local itself, for
        machine-specific packages/overrides too bespoke to generalize.
        Each entry should be an overlay function (`final: prev: { ... }`).
      '';
    };
  };
}
