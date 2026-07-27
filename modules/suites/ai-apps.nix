{ config, lib, pkgs, inputs, alien, ... }:

let
  cfg = config.suites.ai-apps;
  coreLib = import ../core/lib.nix { inherit lib; };
  # `appSet` is defined further down (references `grabcontext`, the
  # derivation defined later in this same `let` block) - Nix `let` bindings
  # are mutually recursive so definition order doesn't matter.
  appSet = coreLib.mkAppSet {
    inherit alien;
    apps = {
      grabcontext = { enable = cfg.grabcontext; pkg = grabcontext; };
      opencode = { enable = cfg.opencode; pkg = pkgs.opencode; };
      copilot = { enable = cfg.copilot; pkg = pkgs.github-copilot-cli; alienName = "github-copilot-cli"; };
    };
  };

  grabcontextScript = builtins.readFile ./ai-apps/grabcontext.py;

  grabcontext = pkgs.writers.writePython3Bin "grabcontext" {
    libraries = [ pkgs.python3Packages.markitdown ];
    makeWrapperArgs = [
      "--prefix PATH : ${lib.makeBinPath [ pkgs.git pkgs.iproute2 pkgs.coreutils pkgs.lsd pkgs.glow pkgs.bat pkgs.jq pkgs.delta ]}"
    ];
} grabcontextScript;

  # setup-graphify {install|remove|update} - "update" re-pulls if the repo
  # already exists (via `git pull` first), "install" handles "already
  # cloned" gracefully without forcing a pull.
  setup-graphify = pkgs.writeShellScriptBin "setup-graphify" ''
    set -euo pipefail

    source ${../core/scripts/common.sh}

    ACTION="''${1:-install}"

    REPO_URL="https://github.com/safishamsi/graphify.git"
    REPO_DIR="$HOME/.local/share/dots/graphify"
    VENV_DIR="$REPO_DIR/.venv"
    BIN_DIR="$HOME/.local/bin"

    usage() {
      echo "Usage: setup-graphify [install|remove|update]"
      echo ""
      echo "  install  Clone+install if missing, otherwise leave as-is (default)"
      echo "  update   Pull latest + reinstall venv"
      echo "  remove   Remove the graphify install"
    }

    do_install() {
      local pull="$1"
      mkdir -p "$(dirname "$REPO_DIR")" "$BIN_DIR"

      if [ ! -d "$REPO_DIR/.git" ]; then
        log_info "Cloning graphify..."
        git clone --branch v3 --depth 1 "$REPO_URL" "$REPO_DIR"
      elif [ "$pull" -eq 1 ]; then
        log_info "Pulling latest graphify..."
        git -C "$REPO_DIR" pull
        rm -rf "$VENV_DIR"
      fi

      if [ ! -x "$VENV_DIR/bin/graphify" ]; then
        log_info "Creating venv and installing..."
        python3 -m venv "$VENV_DIR"
        "$VENV_DIR/bin/pip" install --upgrade pip
        "$VENV_DIR/bin/pip" install "$REPO_DIR"
      fi

      ln -sf "$VENV_DIR/bin/graphify" "$BIN_DIR/graphify"

      log_info "Running platform install..."
      "$BIN_DIR/graphify" install --platform opencode || true

      log_success "Install complete. Run 'graphify' to generate knowledge graphs."
    }

    do_remove() {
      log_info "Cleaning graphify install..."

      read -p "Remove $REPO_DIR? (y/N) " -n 1 -r
      echo
      if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cancelled."
        exit 0
      fi

      if [ -d "$REPO_DIR" ]; then
        log_info "Removing $REPO_DIR..."
        rm -rf "$REPO_DIR"
      fi

      if [ -L "$BIN_DIR/graphify" ]; then
        log_info "Removing symlink..."
        rm -f "$BIN_DIR/graphify"
      fi

      log_success "Clean complete."
    }

    case "$ACTION" in
      install) do_install 0 ;;
      update) do_install 1 ;;
      remove) do_remove ;;
      --help|-h) usage ;;
      *) log_error "Unknown action: $ACTION"; usage; exit 1 ;;
    esac
  '';

  pi-launcher = pkgs.writeShellScriptBin "pi" ''
    export NPM_CONFIG_PREFIX="$HOME/.local/share/pi-agent"
    export npm_config_prefix="$HOME/.local/share/pi-agent"
    export PATH="$HOME/.nix-profile/bin:$HOME/.local/share/pi-agent/bin:$PATH"
    export PI_PACKAGE_DIR="$HOME/.local/share/pi-agent/lib/node_modules/@mariozechner/pi-coding-agent"
    exec "$HOME/.local/share/pi-agent/bin/pi" "$@"
  '';

  # Consolidated install-pi/uninstall-pi -> setup-pi {install|remove|update}.
  # "update" is identical to "install" here - the original install script
  # already always does a clean rm -rf + reinstall, so there's no separate
  # "lighter" update path to preserve.
  setup-pi = pkgs.writeShellScriptBin "setup-pi" ''
    set -euo pipefail

    source ${../core/scripts/common.sh}

    ACTION="''${1:-install}"
    NPM_CONFIG_PREFIX="$HOME/.local/share/pi-agent"

    usage() {
      echo "Usage: setup-pi [install|remove|update]"
      echo ""
      echo "  install  Clean install/reinstall pi-coding-agent (default)"
      echo "  update   Same as install (always reinstalls fresh)"
      echo "  remove   Remove the pi-agent install"
    }

    do_install() {
      log_info "Preparing isolated environment at $NPM_CONFIG_PREFIX..."

      export NPM_CONFIG_PREFIX
      export PATH="$HOME/.nix-profile/bin:$NPM_CONFIG_PREFIX/bin:$PATH"

      # Clean first
      rm -rf "$NPM_CONFIG_PREFIX"
      mkdir -p "$NPM_CONFIG_PREFIX"

      log_info "Installing pi-coding-agent..."
      # Use --prefix to install to our target directory
      npm install -g --prefix "$NPM_CONFIG_PREFIX" @mariozechner/pi-coding-agent

      # Fix: copy the actual pi binary to our bin (npm installs to lib/, we need bin/)
      if [ -f "$NPM_CONFIG_PREFIX/lib/node_modules/@mariozechner/pi-coding-agent/bin/pi" ]; then
        cp "$NPM_CONFIG_PREFIX/lib/node_modules/@mariozechner/pi-coding-agent/bin/pi" "$NPM_CONFIG_PREFIX/bin/pi"
      fi

      # Install declared packages
      ${lib.optionalString (cfg.piPackages != []) ''
        log_info "Installing declared packages..."
        ${lib.concatMapStrings (pkg: ''
          echo " > Adding ${pkg}..."
          "$NPM_CONFIG_PREFIX/bin/pi" install npm:${pkg} || true
        '') cfg.piPackages}
      ''}

      log_success "Build complete."
      echo ">> To add packages: pi install npm:<package-name>"
    }

    do_remove() {
      log_info "Cleaning pi-agent install..."

      read -p "Remove $NPM_CONFIG_PREFIX? (y/N) " -n 1 -r
      echo
      if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cancelled."
        exit 0
      fi

      if [ -d "$NPM_CONFIG_PREFIX" ]; then
        log_info "Removing $NPM_CONFIG_PREFIX..."
        rm -rf "$NPM_CONFIG_PREFIX"
      fi

      log_success "Clean complete."
    }

    case "$ACTION" in
      install) do_install ;;
      update) do_install ;;
      remove) do_remove ;;
      --help|-h) usage ;;
      *) log_error "Unknown action: $ACTION"; usage; exit 1 ;;
    esac
  '';

in
{
  options.suites.ai-apps = {
    enable = coreLib.mkDefaultDisabledOption "Enable AI assistant tools";

    grabcontext = coreLib.mkDefaultEnabledOption "grabcontext (gather code context for AI) - outputs markdown";
    opencode = coreLib.mkDefaultEnabledOption "opencode (AI coding assistant)";
    copilot = coreLib.mkDefaultDisabledOption "GitHub Copilot CLI";
    # Deliberately no `default = true` here even though the suite itself
    # defaults enabled where used - pi is a heavier/more opinionated
    # terminal agent than opencode, so it stays strictly opt-in even when
    # suites.ai-apps.enable is true, unlike opencode.
    pi = coreLib.mkDefaultDisabledOption "pi (terminal coding agent - pi.dev)";
    piPackages = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      # Global curated default list (moved here from being duplicated in
      # every context that wanted `pi` support - `pi` itself still
      # defaults to false above, so this list is inert until a
      # context/host explicitly sets `suites.ai-apps.pi = true;`). Any
      # context/host can still override wholesale via `lib.mkForce` or
      # extend via `++` if truly needed.
      default = [
        "pi-btw"
        "pi-subagents"
        "context-mode"
        "@tintinweb/pi-subagents"
        "pi-mcp-adapter"
        "@plannotator/pi-extension"
        "pi-powerline-footer"
        "pi-lens"
        "@juicesharp/rpiv-ask-user-question"
        "@juicesharp/rpiv-advisor"
        "@juicesharp/rpiv-todo"
        "@samfp/pi-memory"
        "@juicesharp/rpiv-web-tools"
      ];
      description = "Pi packages to auto-install via 'pi install npm:<pkg>'. Names are npm package names.";
      example = [ "pi-web-access" "pi-btw" "@juicesharp/rpiv-todo" ];
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = appSet.packages
      ++ (lib.optional cfg.opencode setup-graphify)
      ++ (lib.optionals cfg.pi [
        pkgs.nodejs
        setup-pi
        pi-launcher
      ]);

    dots.tools =
      (lib.optional cfg.opencode {
        name = "setup-graphify";
        synopsis = "install|remove|update the graphify knowledge-graph tool (git+venv, not a nix package).";
        feature = "suites.ai-apps";
      })
      ++ (lib.optionals cfg.pi [
        {
          name = "pi";
          synopsis = "Launch the pi-coding-agent CLI (installed into an isolated npm prefix, not a nix package).";
          feature = "suites.ai-apps";
        }
        {
          name = "setup-pi";
          synopsis = "install|remove|update pi-coding-agent into its isolated npm prefix.";
          feature = "suites.ai-apps";
        }
      ]);

    # Make build/clean scripts immediately usable
    home.sessionPath = [
      "${config.home.homeDirectory}/.local/bin"
    ];

    # GitHub Copilot CLI bash alias - only wired up when the tool itself
    # is enabled. The runtime `command -v` guard is defensive: `copilot`
    # may be alien-managed (see appSet above), so the binary might come
    # from the native package manager rather than home.packages.
    programs.bash.initExtra = lib.mkIf cfg.copilot ''
      if command -v github-copilot-cli > /dev/null; then
        eval "$(github-copilot-cli alias -- bash)"
      fi
    '';

    home.file.".grabcontext" = lib.mkIf cfg.grabcontext {
      text = ''
        # Format: VAR=PATH
        NIXCFG=/etc/nixos
        HOME=''${config.home.homeDirectory}
        HOME_DOTS=''${config.home.homeDirectory}/dots
        HOME_CONF=''${config.home.homeDirectory}/.config
        HOME_LOCAL=''${config.home.homeDirectory}/.local
      '';
    };

    home.file.".config/opencode/opencode.json" = lib.mkIf cfg.opencode {
      text = builtins.toJSON {
        "$schema" = "https://opencode.ai/config.json";
        plugin = [
          "${config.home.homeDirectory}/.config/opencode/plugins/graphify.js"
        ];
      };
    };

    home.file.".config/opencode/plugins/graphify.js" = lib.mkIf cfg.opencode {
      text = ''
        // graphify OpenCode plugin
        // Injects a knowledge graph reminder before bash tool calls when the graph exists.
        import { existsSync } from "fs";
        import { join } from "path";

        export const GraphifyPlugin = async ({ directory }) => {
          let reminded = false;

          return {
            "tool.execute.before": async (input, output) => {
              if (reminded) return;
              if (!existsSync(join(directory, "graphify-out", "graph.json"))) return;

              if (input.tool === "bash") {
                output.args.command =
                  'echo "[graphify] Knowledge graph available. Read graphify-out/GRAPH_REPORT.md for god nodes and architecture context before searching files." && ' +
                  output.args.command;
                reminded = true;
              }
            },
          };
        };
      '';
    };

    home.activation.graphifyCheck = lib.mkIf cfg.opencode (lib.hm.dag.entryAfter ["writeBoundary"] ''
      GRAPHIFY_BIN="$HOME/.local/bin/graphify"
      if [ ! -x "$GRAPHIFY_BIN" ]; then
        echo "graphify not found. Run 'setup-graphify install' to install."
      else
        echo "graphify ready. Run 'graphify' to generate knowledge graphs."
      fi
    '');

    # Declare which alien packages are enabled
    alienPackages.enabledPackages = appSet.alienEnabled;
  };
}
