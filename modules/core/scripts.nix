# scripts.nix - Generate dots helper scripts
# Creates apply-dots, dots-sync, and update-dots commands

{ config, lib, pkgs, ... }:

{
  # Create the scripts as derivations and add to packages
  home.packages = [
    (pkgs.writeShellScriptBin "apply-dots" ''
      #!/usr/bin/env bash
      # apply-dots - Apply home-manager configuration with dots-local integration
      # Usage: apply-dots [opt] [-- <nh-args>...]
      #
      # Which context bundle you get (priv/work/...) is fully determined
      # by dots-local.flake.nix's `context` field, not a CLI argument. The
      # only CLI choice here is baseline vs. optimized build:
      #
      # Examples:
      #   apply-dots                    # homeConfigurations.default (baseline)
      #   apply-dots opt                # homeConfigurations.default-opt (optimized)
      #   apply-dots -- -b backup       # Pass -b backup to nh home switch
      #   apply-dots opt -- -b backup   # Optimized build + nh flags

      set -e

      DOTS_DIR="''${DOTS_DIR:-$HOME/dots}"
      DOTS_LOCAL_DIR="''${DOTS_LOCAL_DIR:-$HOME/dots-local}"

      source ${./scripts/common.sh}

      # Parse arguments: build variant (optional) followed by -- and nh args
      VARIANT=""
      NH_ARGS=()
      FOUND_SEP=false

      for arg in "$@"; do
        if [[ "$arg" == "--" ]]; then
          FOUND_SEP=true
          continue
        fi
        if [[ "$FOUND_SEP" == true ]]; then
          NH_ARGS+=("$arg")
        elif [[ -z "$VARIANT" && ! "$arg" =~ ^- ]]; then
          VARIANT="$arg"
        fi
      done

      # Normalize the build-variant argument to an actual flake output name.
      case "$VARIANT" in
        ""|default) FLAKE_OUTPUT="default" ;;
        opt|default-opt) FLAKE_OUTPUT="default-opt" ;;
        *)
          print_error "Unknown build variant: '$VARIANT' (expected nothing, 'opt', or 'default-opt')"
          exit 1
          ;;
      esac

      print_header "✦" "DOTS CONFIGURATION"

      # Get info from dots-local (informational only now - dots-local.context
      # selects a modules/contexts/<context>.nix bundle, not a flake output)
      HOST=$(nix eval "git+file://$DOTS_LOCAL_DIR#host" 2>/dev/null | tr -d '"' || echo "unknown")
      CONTEXT=$(nix eval "git+file://$DOTS_LOCAL_DIR#context" 2>/dev/null | tr -d '"' || echo "priv")
      SYSTEM=$(nix eval "git+file://$DOTS_LOCAL_DIR#system" 2>/dev/null | tr -d '"' || echo "x86_64-linux")
      USER=$(nix eval "git+file://$DOTS_LOCAL_DIR#username" 2>/dev/null | tr -d '"' || echo "$(whoami)")

      print_section "📋" "Settings:"
      echo -e "   ''${YELLOW}Host:''${NC}      ''${GREEN}$HOST''${NC}"
      echo -e "   ''${YELLOW}Context:''${NC}   ''${GREEN}$CONTEXT''${NC}"
      echo -e "   ''${YELLOW}Build:''${NC}     ''${GREEN}$FLAKE_OUTPUT''${NC}"
      echo -e "   ''${YELLOW}System:''${NC}    ''${GREEN}$SYSTEM''${NC}"
      echo -e "   ''${YELLOW}User:''${NC}      ''${GREEN}$USER''${NC}"
      if [[ ''${#NH_ARGS[@]} -gt 0 ]]; then
          echo -e "   ''${YELLOW}NH args:''${NC} ''${CYAN}''${NH_ARGS[*]}''${NC}"
      fi
      echo ""

      # Check sync patterns if config exists
      if [[ -f "$DOTS_LOCAL_DIR/sync-config.json" ]]; then
          print_section "📝" "Sync Patterns:"
          if command -v jq &> /dev/null; then
              count=$(jq -r '.tracked | length' "$DOTS_LOCAL_DIR/sync-config.json" 2>/dev/null || echo "0")
              if [[ "$count" -gt 0 ]]; then
                  for ((i=0; i<count; i++)); do
                      pattern=$(jq -r ".tracked[$i].pattern" "$DOTS_LOCAL_DIR/sync-config.json" 2>/dev/null)
                      type=$(jq -r ".tracked[$i].type" "$DOTS_LOCAL_DIR/sync-config.json" 2>/dev/null)
                      echo -e "   ''${PURPLE}$BULLET''${NC} ''${YELLOW}$pattern''${NC} (''${CYAN}$type''${NC})"
                  done
              else
                  echo -e "   ''${YELLOW}No patterns configured''${NC}"
              fi
          fi
          echo ""
      fi

      # Run home-manager switch
      print_section "🏠" "Running home-manager switch..."
      cd "$DOTS_DIR"

      # Create temp log file for capturing full output
      BUILD_LOG=$(mktemp /tmp/apply-dots-XXXXXX.log)

      # Build the nh command with optional extra args
      if [[ ''${#NH_ARGS[@]} -gt 0 ]]; then
          nh home switch "$DOTS_DIR" -c "$FLAKE_OUTPUT" "''${NH_ARGS[@]}" -- --override-input dots-local "git+file://$DOTS_LOCAL_DIR" 2>&1 | tee "$BUILD_LOG"
      else
          nh home switch "$DOTS_DIR" -c "$FLAKE_OUTPUT" -- --override-input dots-local "git+file://$DOTS_LOCAL_DIR" 2>&1 | tee "$BUILD_LOG"
      fi
      result=''${PIPESTATUS[0]}

      if [[ $result -ne 0 ]]; then
          echo ""
          print_error "Activation failed! Full log saved to:"
          echo -e "   ''${YELLOW}$BUILD_LOG''${NC}"
          echo ""
          echo -e "''${CYAN}You can view the full log with:''${NC}"
          echo -e "   cat \"''${YELLOW}$BUILD_LOG''${NC}\""
          echo ""
          echo -e "''${CYAN}Common fixes:''${NC}"
          echo -e "   ''${YELLOW}apply-dots -- -b backup''${NC}  # Backup conflicting files"
          echo -e "   ''${YELLOW}apply-dots -- --dry''${NC}      # Dry run (don't activate)"
          exit $result
      fi

      # Clean up log on success
      rm -f "$BUILD_LOG"

      # NOTE: sync.sh already runs automatically during the switch above,
      # via the home.activation.syncUserConfigs hook
      # (modules/core/dots-local.nix) - that hook fires on every
      # activation regardless of entry point, so it's not called again
      # here.

      # Check alien packages
      echo ""
      print_section "📦" "Checking alien packages..."
      if ! update-alien-packages --dry-run --target all 2>&1; then
          echo ""
          echo -e "''${YELLOW}Run: update-alien-packages to apply changes''${NC}"
      fi
      
      # Update desktop database for AppImages
      if command -v update-desktop-database &> /dev/null; then
          print_section "📝" "Updating desktop database..."
          update-desktop-database ~/.local/share/applications/ 2>/dev/null || true
      fi

      exit 0
    '')

    (pkgs.writeShellScriptBin "dots-sync" ''
      #!/usr/bin/env bash
      # dots-sync - Wrapper for sync.sh
      # Usage: dots-sync [options]
      # All options are passed through to sync.sh

      DOTS_DIR="''${DOTS_DIR:-$HOME/dots}"

      # Pass through to actual sync script
      exec "$DOTS_DIR/sync.sh" "$@"
    '')

    (pkgs.writeShellScriptBin "dots-local-options" ''
      #!/usr/bin/env bash
      # dots-local-options - Show every option settable in dots-local/flake.nix
      # Usage: dots-local-options [-i|--interactive] [search-term]
      #
      # Reads the option list straight from modules/local/schema.nix (via
      # the .#dotsLocalOptionsDoc flake output, generated with nixpkgs's
      # own lib.optionAttrSetToDocList - the same machinery NixOS/Home
      # Manager use for their own option docs) - so this is always exactly
      # in sync with the real schema, never a separate doc that can drift.
      #
      # Examples:
      #   dots-local-options              # show everything
      #   dots-local-options machine      # only machine.* options
      #   dots-local-options sync         # only sync.* options (enable/tracked)
      #   dots-local-options -i           # fuzzy-search/browse interactively (needs gum)
      #   dots-local-options -i machine   # interactive, pre-narrowed to machine.*

      set -e

      DOTS_DIR="''${DOTS_DIR:-$HOME/dots}"
      DOTS_LOCAL_DIR="''${DOTS_LOCAL_DIR:-$HOME/dots-local}"

      source ${./scripts/common.sh}

      INTERACTIVE=0
      FILTER=""
      for arg in "$@"; do
        case "$arg" in
          -i|--interactive) INTERACTIVE=1 ;;
          *) FILTER="$arg" ;;
        esac
      done

      print_header "📋" "dots-local options"
      if [ -n "$FILTER" ]; then
        echo -e "   ''${YELLOW}Filter:''${NC} ''${GREEN}$FILTER''${NC}"
      fi
      echo ""

      DOC_JSON=$(nix eval --json "$DOTS_DIR#dotsLocalOptionsDoc" \
        --override-input dots-local "git+file://$DOTS_LOCAL_DIR" 2>/dev/null) \
        || { print_error "Failed to evaluate .#dotsLocalOptionsDoc"; exit 1; }

      render_option() {
        # $1 = a single option's JSON object
        echo "$1" | jq -r '
          "\u001b[1;36m\(.path)\u001b[0m\n" +
          "  \u001b[1;33mtype:\u001b[0m \(.type)\n" +
          "  \u001b[1;33mdefault:\u001b[0m \(if .default == null then "(required, no default)" else .default end)\n" +
          "  " + (.description | gsub("\n"; "\n  ")) + "\n"
        '
      }

      if [ "$INTERACTIVE" -eq 1 ]; then
        if [ "$USE_GUM" -ne 1 ]; then
          print_error "Interactive mode (-i/--interactive) needs gum, which isn't on PATH."
          exit 1
        fi

        # One tab-separated "path<TAB>type<TAB>default" line per option, fed
        # to gum filter for fuzzy narrowing (path is the sortable/filterable
        # column; type+default ride along as a quick-glance preview).
        LINES=$(echo "$DOC_JSON" | jq -r --arg filter "$FILTER" '
          .[] | select($filter == "" or (.path | contains($filter))) |
          "\(.path)\t\(.type)\t\(if .default == null then "(required)" else .default end)"
        ')

        if [ -z "$LINES" ]; then
          print_error "No options match filter: $FILTER"
          exit 1
        fi

        while true; do
          SELECTED_PATH=$(echo "$LINES" | gum filter \
            --placeholder "Search dots-local options... (esc to quit)" \
            --height 20 --indicator "→" \
            --header "↑↓/type to narrow · enter to view · esc to quit" \
            | cut -f1) || break
          [ -z "$SELECTED_PATH" ] && break

          OPTION_JSON=$(echo "$DOC_JSON" | jq -c --arg path "$SELECTED_PATH" '.[] | select(.path == $path)')
          render_option "$OPTION_JSON" | gum style --border rounded --border-foreground 62 --padding "0 1"
        done
        exit 0
      fi

      echo "$DOC_JSON" | jq -r --arg filter "$FILTER" '
        .[] | select($filter == "" or (.path | contains($filter))) |
        "\u001b[1;36m\(.path)\u001b[0m\n" +
        "  \u001b[1;33mtype:\u001b[0m \(.type)\n" +
        "  \u001b[1;33mdefault:\u001b[0m \(if .default == null then "(required, no default)" else .default end)\n" +
        "  " + (.description | gsub("\n"; "\n  ")) + "\n"
      '
    '')

    (pkgs.writeShellScriptBin "dots-context-options" ''
      #!/usr/bin/env bash
      # dots-context-options - Show every features.*/suites.* toggle,
      # its type/default/description, AND this machine's actual current
      # value (companion to dots-local-options, same UX/flags).
      # Usage: dots-context-options [-i|--interactive] [search-term]
      #
      # Reads straight from the full evaluated Home Manager option tree
      # (via the .#dotsContextOptionsDoc flake output, generated with
      # nixpkgs's own lib.optionAttrSetToDocList) - always exactly in
      # sync with the real features/*.nix and suites/*.nix option
      # declarations, never a separate doc that can drift. Unlike
      # dots-local-options, "current" reflects this machine's real
      # resolved value (many of these are mkDefaults computed from
      # dotsLocal axes, e.g. core.enableGuiDefaults, so the declared
      # default text alone wouldn't tell you what's actually enabled
      # here).
      #
      # Examples:
      #   dots-context-options              # show everything
      #   dots-context-options gui-apps     # only suites.gui-apps.* options
      #   dots-context-options appimages    # only features.appimages.* options
      #   dots-context-options -i           # fuzzy-search/browse interactively (needs gum)
      #   dots-context-options -i network   # interactive, pre-narrowed to *network*

      set -e

      DOTS_DIR="''${DOTS_DIR:-$HOME/dots}"
      DOTS_LOCAL_DIR="''${DOTS_LOCAL_DIR:-$HOME/dots-local}"

      source ${./scripts/common.sh}

      INTERACTIVE=0
      FILTER=""
      for arg in "$@"; do
        case "$arg" in
          -i|--interactive) INTERACTIVE=1 ;;
          *) FILTER="$arg" ;;
        esac
      done

      print_header "🧩" "features/suites options"
      if [ -n "$FILTER" ]; then
        echo -e "   ''${YELLOW}Filter:''${NC} ''${GREEN}$FILTER''${NC}"
      fi
      echo ""

      DOC_JSON=$(nix eval --json "$DOTS_DIR#dotsContextOptionsDoc" \
        --override-input dots-local "git+file://$DOTS_LOCAL_DIR" 2>/dev/null) \
        || { print_error "Failed to evaluate .#dotsContextOptionsDoc"; exit 1; }

      render_option() {
        # $1 = a single option's JSON object
        echo "$1" | jq -r '
          "\u001b[1;36m\(.path)\u001b[0m\n" +
          "  \u001b[1;33mtype:\u001b[0m \(.type)\n" +
          "  \u001b[1;33mdefault:\u001b[0m \(if .default == null then "(required, no default)" else .default end)\n" +
          "  \u001b[1;32mcurrent:\u001b[0m \(.current) \u001b[2m(this machine)\u001b[0m\n" +
          "  " + (.description | gsub("\n"; "\n  ")) + "\n"
        '
      }

      if [ "$INTERACTIVE" -eq 1 ]; then
        if [ "$USE_GUM" -ne 1 ]; then
          print_error "Interactive mode (-i/--interactive) needs gum, which isn't on PATH."
          exit 1
        fi

        # One tab-separated "path<TAB>current<TAB>default" line per
        # option, fed to gum filter for fuzzy narrowing (path is the
        # sortable/filterable column; current+default ride along as a
        # quick-glance preview).
        LINES=$(echo "$DOC_JSON" | jq -r --arg filter "$FILTER" '
          .[] | select($filter == "" or (.path | contains($filter))) |
          "\(.path)\t\(.current)\t\(if .default == null then "(required)" else .default end)"
        ')

        if [ -z "$LINES" ]; then
          print_error "No options match filter: $FILTER"
          exit 1
        fi

        while true; do
          SELECTED_PATH=$(echo "$LINES" | gum filter \
            --placeholder "Search features/suites options... (esc to quit)" \
            --height 20 --indicator "→" \
            --header "↑↓/type to narrow · enter to view · esc to quit" \
            | cut -f1) || break
          [ -z "$SELECTED_PATH" ] && break

          OPTION_JSON=$(echo "$DOC_JSON" | jq -c --arg path "$SELECTED_PATH" '.[] | select(.path == $path)')
          render_option "$OPTION_JSON" | gum style --border rounded --border-foreground 62 --padding "0 1"
        done
        exit 0
      fi

      echo "$DOC_JSON" | jq -r --arg filter "$FILTER" '
        .[] | select($filter == "" or (.path | contains($filter))) |
        "\u001b[1;36m\(.path)\u001b[0m\n" +
        "  \u001b[1;33mtype:\u001b[0m \(.type)\n" +
        "  \u001b[1;33mdefault:\u001b[0m \(if .default == null then "(required, no default)" else .default end)\n" +
        "  \u001b[1;32mcurrent:\u001b[0m \(.current) \u001b[2m(this machine)\u001b[0m\n" +
        "  " + (.description | gsub("\n"; "\n  ")) + "\n"
      '
    '')

    (pkgs.writeShellScriptBin "dots-tools" ''
      #!/usr/bin/env bash
      # dots-tools - List every non-standard tool (hand-rolled script/
      # function installed by a feature or suite - NOT a plain packaged
      # binary already coming from a nix package or its alien equivalent)
      # that is currently active on this machine, with a one-line
      # synopsis, the feature/suite that installs it, and any dotsLocal
      # settings that affect it. Companion to dots-local-options/
      # dots-context-options for the same "dots is too big to keep in my
      # head" problem, but at the "what commands do I even have"
      # granularity instead of the option-tree granularity.
      # Usage: dots-tools [-i|--interactive] [search-term]
      #
      # Reads straight from the dots.tools registry (see
      # modules/core/tools-registry.nix and .#dotsToolsDoc flake output) -
      # every feature/suite that installs a hand-rolled command appends
      # its own entry there, right next to where it installs the command
      # itself, so this list can't drift from what's actually active.
      #
      # Unlike dots-local-options/dots-context-options's -i mode (which
      # renders full details on selection), selecting a tool here just
      # prints its bare name to stdout - so `dots-tools -i` composes
      # naturally with command substitution/shell widgets, e.g.
      # `$(dots-tools -i) --help` or bound to a key via
      # `bind -x '"\C-g\C-t": READLINE_LINE="$(dots-tools -i)"'`
      # in your own bashrc, mirroring fzf's own key-binding convention.
      #
      # Examples:
      #   dots-tools                 # list everything
      #   dots-tools vk              # only tools matching "vk"
      #   dots-tools -i              # fuzzy-pick, prints the chosen name
      #   dots-tools -i llama        # interactive, pre-narrowed

      set -e

      DOTS_DIR="''${DOTS_DIR:-$HOME/dots}"
      DOTS_LOCAL_DIR="''${DOTS_LOCAL_DIR:-$HOME/dots-local}"

      source ${./scripts/common.sh}

      INTERACTIVE=0
      FILTER=""
      for arg in "$@"; do
        case "$arg" in
          -i|--interactive) INTERACTIVE=1 ;;
          *) FILTER="$arg" ;;
        esac
      done

      DOC_JSON=$(nix eval --json "$DOTS_DIR#dotsToolsDoc" \
        --override-input dots-local "git+file://$DOTS_LOCAL_DIR" 2>/dev/null) \
        || { print_error "Failed to evaluate .#dotsToolsDoc"; exit 1; }

      if [ "$INTERACTIVE" -eq 1 ]; then
        if [ "$USE_GUM" -ne 1 ]; then
          print_error "Interactive mode (-i/--interactive) needs gum, which isn't on PATH."
          exit 1
        fi

        # One tab-separated "name<TAB>synopsis<TAB>feature" line per tool,
        # fed to gum filter for fuzzy narrowing.
        LINES=$(echo "$DOC_JSON" | jq -r --arg filter "$FILTER" '
          .[] | select($filter == "" or (.name | contains($filter)) or (.synopsis | ascii_downcase | contains($filter | ascii_downcase))) |
          "\(.name)\t\(.synopsis)\t\(.feature)"
        ')

        if [ -z "$LINES" ]; then
          print_error "No tools match filter: $FILTER"
          exit 1
        fi

        # Just the name on selection (no details block) - meant to be
        # captured via $(...) or a bash keybinding, not read by a human
        # mid-pick.
        echo "$LINES" | gum filter \
          --placeholder "Search dots tools... (esc to quit)" \
          --height 20 --indicator "→" \
          --header "↑↓/type to narrow · enter to pick name · esc to quit" \
          | cut -f1
        exit 0
      fi

      print_header "🛠️" "dots tools"
      if [ -n "$FILTER" ]; then
        echo -e "   ''${YELLOW}Filter:''${NC} ''${GREEN}$FILTER''${NC}"
      fi
      echo ""

      echo "$DOC_JSON" | jq -r --arg filter "$FILTER" '
        .[] | select($filter == "" or (.name | contains($filter)) or (.synopsis | ascii_downcase | contains($filter | ascii_downcase))) |
        "\u001b[1;36m\(.name)\u001b[0m\n" +
        "  \u001b[1;33mfeature:\u001b[0m \(.feature)\n" +
        (if (.dotsLocalSettings | length) > 0 then "  \u001b[1;35mdotsLocal:\u001b[0m \(.dotsLocalSettings | join(", "))\n" else "" end) +
        "  \(.synopsis)\n"
      '
    '')

    (pkgs.writeShellScriptBin "dots-ports" ''
      #!/usr/bin/env bash
      # dots-ports - List every currently listening TCP/UDP port on this
      # machine: which interface it's bound to (loopback-only vs ALL
      # interfaces vs a specific address - most dev servers should be
      # loopback-only), which process holds it, and, when that process
      # is a nix-store binary, which package it came from. The "what's
      # actually exposed on the network right now" counterpart to
      # `dots-tools`'s "what commands do I have" question - these are
      # deliberately unrelated registries: dots-tools is a static,
      # config-time list of hand-rolled commands (dots-ports is itself
      # one of those entries, listed below, same as every other script
      # in this file); dots-ports is a live, runtime snapshot of
      # listening sockets, not a registry of anything itself.
      #
      # Needs `ss` (iproute2, in core's home.packages) to enumerate
      # sockets. Process/package attribution for sockets owned by
      # OTHER users needs root (ss's own `-p` limitation, not something
      # this script can work around) - run via `sudo dots-ports` for a
      # complete system-wide view; without it, those entries show
      # "(permission denied - try: sudo dots-ports)" instead of a name.
      #
      # Usage: dots-ports [filter]
      #   dots-ports          # list every listening TCP/UDP socket
      #   dots-ports postgres # only entries whose process/port/interface
      #                       # text contains "postgres"

      set -uo pipefail

      source ${./scripts/common.sh}

      if ! command -v ss >/dev/null 2>&1; then
        print_error "'ss' (iproute2) not found on \$PATH - can't enumerate listening sockets."
        exit 1
      fi

      FILTER="''${1:-}"

      classify_iface() {
        case "$1" in
          127.0.0.1|::1|localhost) echo "loopback ($1)" ;;
          0.0.0.0|"*"|::)          echo "ALL interfaces ($1)" ;;
          *)                       echo "$1" ;;
        esac
      }

      # Resolves a PID to the nix package that owns its binary, via
      # /proc/<pid>/exe - a nix-store path looks like
      # /nix/store/<hash>-<name>-<version>/bin/<bin>, so stripping the
      # hash prefix leaves "<name>-<version>", a good-enough package
      # label without needing to query the store database. Anything
      # outside /nix/store (system/alien/AppImage/etc. binaries) is
      # reported as-is, tagged "(non-nix)".
      resolve_package() {
        local pid="$1" exe
        exe=$(readlink -f "/proc/$pid/exe" 2>/dev/null) || { echo "(unknown)"; return; }
        case "$exe" in
          /nix/store/*)
            local rest="''${exe#/nix/store/}"
            rest="''${rest%%/*}"
            echo "''${rest#*-}"
            ;;
          *) echo "$exe (non-nix)" ;;
        esac
      }

      print_header "🔌" "dots ports"
      if [ -n "$FILTER" ]; then
        echo -e "   ''${YELLOW}Filter:''${NC} ''${GREEN}$FILTER''${NC}"
        echo ""
      fi

      printf "%-6s %-28s %-28s %-8s %s\n" "PROTO" "INTERFACE:PORT" "PROCESS" "PID" "PACKAGE"

      ss -H -tulnp 2>/dev/null | while read -r netid state _recvq _sendq local _peer proc _rest; do
        [ "$netid" = "tcp" ] || [ "$netid" = "udp" ] || continue

        addr="''${local%:*}"
        port="''${local##*:}"
        addr="''${addr#\[}"; addr="''${addr%\]}"
        iface=$(classify_iface "$addr")

        pid=""
        pname=""
        if [[ "$proc" =~ users:\(\(\"([^\"]+)\",pid=([0-9]+) ]]; then
          pname="''${BASH_REMATCH[1]}"
          pid="''${BASH_REMATCH[2]}"
        fi

        if [ -n "$FILTER" ]; then
          case "$pname $port $iface" in
            *"$FILTER"*) ;;
            *) continue ;;
          esac
        fi

        if [ -n "$pid" ]; then
          pkg=$(resolve_package "$pid")
          procdisp="$pname ($pid)"
        else
          procdisp="(permission denied - try: sudo dots-ports)"
          pkg="-"
        fi

        printf "%-6s %-28s %-28s %-8s %s\n" "$netid" "$iface:$port" "$procdisp" "''${pid:--}" "$pkg"
      done
    '')

    (pkgs.writeShellScriptBin "update-dots" ''
      #!/usr/bin/env bash
      # update-dots - Update dots flake inputs
      # Usage: update-dots [input-name] [-- <nix-flake-update-args>...]
      #
      # Examples:
      #   update-dots                    # Update all inputs
      #   update-dots nixpkgs            # Update specific input
      #   update-dots -- --refresh       # Pass --refresh to nix flake update
      #   update-dots nixpkgs -- --refresh  # Input + extra args

      set -e

      DOTS_DIR="''${DOTS_DIR:-$HOME/dots}"
      DOTS_LOCAL_DIR="''${DOTS_LOCAL_DIR:-$HOME/dots-local}"

      source ${./scripts/common.sh}

      # Parse arguments: input name (optional) followed by -- and nix flake update args
      INPUT_NAME=""
      EXTRA_ARGS=()
      FOUND_SEP=false

      for arg in "$@"; do
        if [[ "$arg" == "--" ]]; then
          FOUND_SEP=true
          continue
        fi
        if [[ "$FOUND_SEP" == true ]]; then
          EXTRA_ARGS+=("$arg")
        elif [[ -z "$INPUT_NAME" ]]; then
          INPUT_NAME="$arg"
        fi
      done

      echo ""
      print_section "🔄" "Updating dots flake inputs..."
      echo ""

      cd "$DOTS_DIR"

      if [[ -n "$INPUT_NAME" ]]; then
          echo -e "''${YELLOW}Updating input: $INPUT_NAME''${NC}"
          if [[ ''${#EXTRA_ARGS[@]} -gt 0 ]]; then
              echo -e "''${CYAN}Extra args: ''${EXTRA_ARGS[*]}''${NC}"
              nix flake update "$INPUT_NAME" "''${EXTRA_ARGS[@]}" --override-input dots-local "git+file://$DOTS_LOCAL_DIR"
          else
              nix flake update "$INPUT_NAME" --override-input dots-local "git+file://$DOTS_LOCAL_DIR"
          fi
      else
          echo -e "''${YELLOW}Updating all inputs...''${NC}"
          if [[ ''${#EXTRA_ARGS[@]} -gt 0 ]]; then
              echo -e "''${CYAN}Extra args: ''${EXTRA_ARGS[*]}''${NC}"
              nix flake update "''${EXTRA_ARGS[@]}" --override-input dots-local "git+file://$DOTS_LOCAL_DIR"
          else
              nix flake update --override-input dots-local "git+file://$DOTS_LOCAL_DIR"
          fi
      fi

      echo ""
      if [ "$USE_GUM" -eq 1 ]; then
          gum style --foreground 42 --bold "✅ Flake inputs updated successfully!"
      else
          echo -e "''${GREEN}Flake inputs updated successfully!''${NC}"
      fi
      echo -e "''${BLUE}Run 'apply-dots' to apply the changes.''${NC}"
      echo ""
    '')

    (pkgs.writeShellScriptBin "update-appimages" ''
      #!/usr/bin/env bash
      # update-appimages - Update AppImages
      # Usage: update-appimages [app-name] [--all] [--unregistered] [--include-shared]

      DOTS_LOCAL_DIR="''${DOTS_LOCAL_DIR:-$HOME/dots-local}"
      DOTS_DIR="''${DOTS_DIR:-$HOME/dots}"

      source ${./scripts/common.sh}

      # Get context from dots-local (used below only to locate
      # contexts/$CONTEXT/appimages/ - the shared/store-backed AppImages
      # dir, unrelated to Nix's homeConfigurations output name)
      CONTEXT=$(nix eval "git+file://$DOTS_LOCAL_DIR#context" 2>/dev/null | tr -d '"' || echo "priv")
      CONTEXT="''${CONTEXT:-priv}"

      # Get localDir from Home Manager config. NOTE: "default" here is the
      # flake output name (see flake.nix) - unrelated to $CONTEXT above.
      # localDir doesn't differ between default/default-opt.
      LOCAL_DIR=$(nix eval --raw "$DOTS_DIR#homeConfigurations.default.config.features.appimages.localDir" 2>/dev/null || echo "$HOME/Applications/AppImages")

      # Parse arguments
      UPDATE_ALL=false
      UNREGISTERED=false
      INCLUDE_SHARED=false
      TARGET_APP=""

      for arg in "$@"; do
          case "$arg" in
              --all)
                  UPDATE_ALL=true
                  ;;
              --unregistered)
                  UNREGISTERED=true
                  ;;
              --include-shared)
                  INCLUDE_SHARED=true
                  ;;
              --help|-h)
                  echo "Usage: update-appimages [options] [app-name]"
                  echo ""
                  echo "Update AppImages using appimageupdatetool."
                  echo ""
                  echo "Options:"
                  echo "  --all              Update all AppImages (registered + unregistered + shared)"
                  echo "  --unregistered     Also update unregistered AppImages in localDir"
                  echo "  --include-shared   Also update shared AppImages from dots/ (modifies dots repo)"
                  echo "  --help             Show this help"
                  echo ""
                  echo "By default, only updates registered host-local AppImages."
                  echo ""
                  echo "Updates use 'appimageupdatetool -r' which removes the old file after"
                  echo "successful update. This handles versioned filenames where the new release"
                  echo "has a different version in the filename."
                  echo ""
                  echo "Examples:"
                  echo "  update-appimages              # Update registered host-local apps"
                  echo "  update-appimages steam        # Update specific app"
                  echo "  update-appimages --unregistered # Update all AppImages in \$LOCAL_DIR"
                  echo "  update-appimages --all        # Update everything"
                  exit 0
                  ;;
              -*)
                  log_error "Unknown option: $arg"
                  exit 1
                  ;;
              *)
                  if [[ -z "$TARGET_APP" ]]; then
                      TARGET_APP="$arg"
                  fi
                  ;;
          esac
      done

      echo ""
      log_info "Local directory: $LOCAL_DIR"
      log_info "Context: $CONTEXT"
      if [[ -n "$TARGET_APP" ]]; then
          log_info "Target: $TARGET_APP"
      elif [[ "$UPDATE_ALL" == "true" ]]; then
          log_info "Target: all (registered + unregistered + shared)"
      elif [[ "$UNREGISTERED" == "true" ]]; then
          log_info "Target: registered + unregistered"
      else
          log_info "Target: registered host-local apps"
      fi
      echo ""

      # Track results
      UPDATED=0
      SKIPPED=0
      FAILED=0
      
      # Track processed files to avoid duplicates
      declare -A PROCESSED_FILES

      # Function to update a single AppImage
      update_single() {
          local app_name="$1"
          local app_path="$2"
          
          echo "  $app_name: Checking for updates..."
          
          if [[ ! -f "$app_path" ]]; then
              log_warn "File not found: $app_path"
              return 1
          fi
          
          # Record if executable
          local was_exec=0
          [[ -x "$app_path" ]] && was_exec=1
          
          # Try to update
          if appimageupdatetool -r "$app_path" >/dev/null 2>&1; then
              # Restore exec bit if needed and was executable
              if [[ $was_exec -eq 1 ]] && [[ -f "$app_path" ]] && [[ ! -x "$app_path" ]]; then
                  chmod +x "$app_path"
              fi
              log_success "Updated"
              return 0
          else
              # Check if not updateable
              if appimageupdatetool --check-for-update "$app_path" 2>&1 | grep -q "No update information"; then
                  log_warn "No embedded update info"
                  return 2
              else
                  log_error "Update failed"
                  return 1
              fi
          fi
      }

      # Process registered apps
      log_info "Processing registered host-local AppImages..."
      
      # Read manifest
      REGISTERED_JSON=$(nix eval --json "git+file://$DOTS_LOCAL_DIR#appimages" 2>/dev/null)
      if [[ -z "$REGISTERED_JSON" ]]; then
          log_warn "Could not read appimages manifest from dots-local"
      else
          # Get app names
          APP_LIST=$(echo "$REGISTERED_JSON" | jq -r 'keys[]' 2>/dev/null)
          
          if [[ -z "$APP_LIST" ]]; then
              log_warn "No apps found in manifest"
          else
              # Process each app using here-string to avoid subshell
              while read -r app_name; do
                  [[ -z "$app_name" ]] && continue
                  
                  # Skip if targeting specific app
                  if [[ -n "$TARGET_APP" && "$app_name" != "$TARGET_APP" ]]; then
                      continue
                  fi
                  
                  # Get file pattern using jq with proper variable passing
                  file_pattern=$(echo "$REGISTERED_JSON" | jq -r --arg name "$app_name" '.[$name].file // empty' 2>/dev/null)
                  if [[ -z "$file_pattern" ]]; then
                      echo "  $app_name: No file pattern defined"
                      continue
                  fi
                  
                  # Find matching files
                  matches=$(find "$LOCAL_DIR" -maxdepth 1 -name "$file_pattern" -type f 2>/dev/null)
                  count=$(echo "$matches" | grep -c '^' 2>/dev/null || echo "0")
                  
                  if [[ "$count" -eq 0 ]]; then
                      echo "  $app_name: No file matching '$file_pattern'"
                      continue
                  fi
                  
                  if [[ "$count" -gt 1 ]]; then
                      log_error "Multiple files matching '$file_pattern':"
                      echo "$matches" | sed 's/^/    /'
                      echo "    Please keep only one version."
                      ((FAILED++))
                      continue
                  fi
                  
                  # Single match found
                  app_path=$(echo "$matches" | head -1)
                  app_file=$(basename "$app_path")
                  
                  # Mark as processed (by filename)
                  PROCESSED_FILES[$app_file]=1
                  
                  echo "  $app_name: Found $app_file"
                  
                  if update_single "$app_name" "$app_path"; then
                      ((UPDATED++))
                  elif [[ $? -eq 2 ]]; then
                      ((SKIPPED++))
                  else
                      ((FAILED++))
                  fi
              done <<< "$APP_LIST"
          fi
      fi

      # Process unregistered apps if requested
      if [[ "$UNREGISTERED" == "true" || "$UPDATE_ALL" == "true" ]]; then
          echo ""
          log_info "Processing unregistered AppImages..."
          
          if [[ -d "$LOCAL_DIR" ]]; then
              for app_path in "$LOCAL_DIR"/*.AppImage; do
                  [[ -f "$app_path" ]] || continue
                  
                  app_file=$(basename "$app_path")
                  
                  # Skip if already processed (check by filename)
                  if [[ -n "''${PROCESSED_FILES[$app_file]}" ]]; then
                      continue
                  fi
                  
                  app_name="''${app_file%.AppImage}"
                  
                  # Skip if targeting specific app
                  if [[ -n "$TARGET_APP" && "$app_name" != "$TARGET_APP" ]]; then
                      continue
                  fi
                  
                  echo "  $app_name: Processing (unregistered)"
                  if update_single "$app_name" "$app_path"; then
                      ((UPDATED++))
                  elif [[ $? -eq 2 ]]; then
                      ((SKIPPED++))
                  else
                      ((FAILED++))
                  fi
              done
          fi
      fi

      # Process shared apps if requested
      if [[ "$INCLUDE_SHARED" == "true" || "$UPDATE_ALL" == "true" ]]; then
          echo ""
          log_info "Processing shared AppImages from dots/..."
          
          # Common
          if [[ -d "$DOTS_DIR/contexts/common/appimages" ]]; then
              for app_path in "$DOTS_DIR/contexts/common/appimages"/*.AppImage; do
                  [[ -f "$app_path" ]] || continue
                  app_file=$(basename "$app_path")
                  app_name="''${app_file%.AppImage}"
                  
                  if [[ -n "$TARGET_APP" && "$app_name" != "$TARGET_APP" ]]; then
                      continue
                  fi
                  
                  echo "  $app_name: Processing (contexts/common)"
                  if update_single "$app_name" "$app_path"; then
                      ((UPDATED++))
                  elif [[ $? -eq 2 ]]; then
                      ((SKIPPED++))
                  else
                      ((FAILED++))
                  fi
              done
          fi

          # Context-specific
          if [[ -d "$DOTS_DIR/contexts/$CONTEXT/appimages" ]]; then
              for app_path in "$DOTS_DIR/contexts/$CONTEXT/appimages"/*.AppImage; do
                  [[ -f "$app_path" ]] || continue
                  app_file=$(basename "$app_path")
                  app_name="''${app_file%.AppImage}"
                  
                  if [[ -n "$TARGET_APP" && "$app_name" != "$TARGET_APP" ]]; then
                      continue
                  fi
                  
                  echo "  $app_name: Processing (contexts/$CONTEXT)"
                  if update_single "$app_name" "$app_path"; then
                      ((UPDATED++))
                  elif [[ $? -eq 2 ]]; then
                      ((SKIPPED++))
                  else
                      ((FAILED++))
                  fi
              done
          fi
      fi

      echo ""
      log_info "Results: $UPDATED updated, $SKIPPED not updateable, $FAILED failed"
      echo ""
      
      if [[ $UPDATED -gt 0 ]]; then
          if [[ "$INCLUDE_SHARED" == "true" || "$UPDATE_ALL" == "true" ]]; then
              log_info "Run apply-dots to activate any updated shared AppImages"
          fi
      fi
    '')
  ];

  # Ensure user-local bins are on PATH. NOTE: this used to also include
  # "$HOME/dots/bin" - that directory never actually existed (Phase 8
  # externalized scripts into per-module scripts/ subdirectories instead,
  # e.g. modules/features/viewer/v.sh, and this leftover PATH entry was
  # never cleaned up alongside it).
  home.sessionPath = [ "$HOME/.local/bin" ];

  # This file's own scripts, registered in the dots.tools registry (see
  # modules/core/tools-registry.nix) - these are always installed
  # (no cfg.enable gate in this module), so they're registered
  # unconditionally too.
  dots.tools = [
    {
      name = "apply-dots";
      synopsis = "Build+activate this Home Manager config (baseline or -opt build).";
      feature = "modules/core/scripts.nix (always installed)";
    }
    {
      name = "dots-sync";
      synopsis = "Wrapper for sync.sh - syncs handcrafted per-host configs.";
      feature = "modules/core/scripts.nix (always installed)";
    }
    {
      name = "dots-local-options";
      synopsis = "Show every option settable in dots-local/flake.nix.";
      feature = "modules/core/scripts.nix (always installed)";
    }
    {
      name = "dots-context-options";
      synopsis = "Show every features.*/suites.* toggle plus this machine's current value.";
      feature = "modules/core/scripts.nix (always installed)";
    }
    {
      name = "dots-tools";
      synopsis = "List/search non-standard tools installed by active features/suites (this command).";
      feature = "modules/core/scripts.nix (always installed)";
    }
    {
      name = "dots-ports";
      synopsis = "List currently listening TCP/UDP ports, bound interface, process, and (if nix-managed) owning package.";
      feature = "modules/core/scripts.nix (always installed)";
    }
    {
      name = "update-dots";
      synopsis = "Pull/update dots + dots-local + flake inputs.";
      feature = "modules/core/scripts.nix (always installed)";
    }
    {
      name = "update-appimages";
      synopsis = "Update per-context/shared AppImages tracked in contexts/<context>/appimages/manifest.nix.";
      feature = "modules/core/scripts.nix (always installed)";
    }
  ];
}
