# dots-local integration module
# Displays configuration info and runs sync on activation for all profiles

{ config, lib, pkgs, dotsLocal, ... }:

let
  # dotsLocal.host is nullable - `or` only helps for missing attrs, not a
  # present-but-null value, so this needs an explicit check rather than
  # `dotsLocal.host or "unknown"`.
  hostOrUnknown = if dotsLocal.host != null then dotsLocal.host else "unknown";
  hostOrEmpty = if dotsLocal.host != null then dotsLocal.host else "";
in
{
  # dots-local can hold plaintext secrets (e.g. dotsLocal.taskSync.credential)
  # in its flake.nix - there's no secrets-encryption layer in this repo, so
  # the best available protection is restricting the directory to the
  # owning user only. setup.sh already chmods it to 0700 at creation time;
  # this re-asserts that on every activation too (e.g. after a `git clone`
  # of dots-local, which wouldn't preserve that bit), so it's not a
  # one-time-only guarantee. Harmless no-op if the directory doesn't exist
  # yet (chmod's error is silenced) - dots-local is optional at
  # first-checkout time on some flows.
  home.activation.protectDotsLocalPerms = lib.hm.dag.entryBefore ["writeBoundary"] ''
    DOTS_LOCAL_DIR="''${DOTS_LOCAL_DIR:-$HOME/dots-local}"
    if [ -d "$DOTS_LOCAL_DIR" ]; then
      chmod 700 "$DOTS_LOCAL_DIR" || true
    fi
  '';

  # Pretty print dots-local configuration on activation
  home.activation.printDotsLocalInfo = lib.hm.dag.entryBefore ["writeBoundary"] ''
    DOTS_DIR="''${DOTS_DIR:-$HOME/dots}"
    DOTS_LOCAL_DIR="''${DOTS_LOCAL_DIR:-$HOME/dots-local}"

    source ${./scripts/common.sh}
    
    print_header "✦" "DOTS CONFIGURATION"
    
    # Basic settings from dots-local
    print_section "📋" "Basic Settings:"
    echo -e "   ''${YELLOW}Host:''${NC}     ''${GREEN}${hostOrUnknown}''${NC}"
    echo -e "   ''${YELLOW}Context:''${NC}  ''${GREEN}${dotsLocal.context}''${NC}"
    echo -e "   ''${YELLOW}System:''${NC}   ''${GREEN}${dotsLocal.system}''${NC}"
    echo -e "   ''${YELLOW}User:''${NC}     ''${GREEN}${dotsLocal.username}''${NC}"
    echo ""
    
    # Show sync patterns if config exists
    # NOTE: sync-config.json lives in dots-local (generated from its
    # flake.nix), not in dots itself.
    if [ -f "$DOTS_LOCAL_DIR/sync-config.json" ]; then
      print_section "📝" "Sync Patterns:"
      if command -v jq &> /dev/null; then
        count=$(jq -r '.tracked | length' "$DOTS_LOCAL_DIR/sync-config.json" 2>/dev/null || echo "0")
        if [ "$count" -gt 0 ]; then
          for ((i=0; i<count; i++)); do
            pattern=$(jq -r ".tracked[$i].pattern" "$DOTS_LOCAL_DIR/sync-config.json" 2>/dev/null)
            type=$(jq -r ".tracked[$i].type" "$DOTS_LOCAL_DIR/sync-config.json" 2>/dev/null)
            on_new=$(jq -r ".tracked[$i].on_new" "$DOTS_LOCAL_DIR/sync-config.json" 2>/dev/null)
            echo -e "   ''${PURPLE}$BULLET''${NC} ''${YELLOW}$pattern''${NC} (''${CYAN}$type''${NC}, on_new: ''${CYAN}$on_new''${NC})"
          done
        else
          echo -e "   ''${YELLOW}No patterns configured''${NC}"
        fi
      else
        echo -e "   ''${YELLOW}Install jq to see patterns''${NC}"
      fi
      echo ""
    fi
    
    # Show resolved machine axes (host-specific config is expressed via
    # dotsLocal fields, shown here directly).
    if [ -n "${hostOrEmpty}" ]; then
      print_section "🔧" "Machine axes:"
      echo -e "   ''${GREEN}gpu:''${NC} ${if dotsLocal.gpu != null then dotsLocal.gpu else "none"}  ''${GREEN}compositor:''${NC} ${if dotsLocal.compositor != null then dotsLocal.compositor else "none"}  ''${GREEN}isWsl:''${NC} ${if dotsLocal.isWsl then "yes" else "no"}"
      echo ""
    fi
    
    echo -e "''${BOLD}══════════════════════════════════════════════════════════════''${NC}"
    echo ""
  '';

  # Sync handcrafted user configs on activation (applies to all profiles).
  #
  # This fires automatically on EVERY Home Manager activation (bare
  # `home-manager switch`, `nh home switch`, or via `apply-dots`), which is
  # what makes it the right place for this to live - it's the single source
  # of truth for "sync runs after every successful switch, however it was
  # triggered." `apply-dots` (modules/core/scripts.nix) does not call
  # sync.sh separately - that would be redundant with this hook, which
  # already runs during the same switch.
  home.activation.syncUserConfigs = lib.hm.dag.entryAfter ["writeBoundary"] ''
    DOTS_DIR="''${DOTS_DIR:-$HOME/dots}"
    if [ -x "$DOTS_DIR/sync.sh" ]; then
      echo ""
      if command -v gum >/dev/null 2>&1; then
        gum style --foreground 51 --bold "🔄 Syncing handcrafted user configs..."
      else
        echo -e "\033[0;36mSyncing handcrafted user configs...\033[0m"
      fi
      "$DOTS_DIR/sync.sh" || true
    fi
  '';
}
