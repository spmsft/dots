{ config, lib, pkgs, dotsLocal, bashrcDerivation, profileDerivation, ... }:

let
  nixonDefaultStr = if dotsLocal.nixonDefault then "1" else "0";

  # Bash array literals, e.g. ( "TERM" "HOME" ... ), embedded verbatim into
  # the generated shell code below as the default env-var preserve list
  # for `nixon`/`nixoff`'s default (`-`) mode.
  nixonEnvAllowlistBash =
    "( " + (lib.concatStringsSep " " (map (v: "\"${v}\"") dotsLocal.nixonEnvAllowlist)) + " )";
  nixonPreserveVarsBash =
    "( " + (lib.concatStringsSep " " (map (v: "\"${v}\"") config.core.nixonPreserveVars)) + " )";
in

{
  options.core.nixonPreserveVars = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = ''
      Extra environment variable names `nixon`/`nixoff` should preserve
      across their default (`-`) mode re-exec, on top of
      `dotsLocal.nixonEnvAllowlist`. Intended for *modules* that need a
      specific var to survive the environment wipe (e.g. because some
      tool they configure relies on it being set in every shell) - end
      users should prefer `dotsLocal.nixonEnvAllowlist` instead. Values
      set here are merged (module-system list concatenation) with every
      other module's contributions and with `dotsLocal.nixonEnvAllowlist`
      at the point `nixon`/`nixoff` builds their preserve list.
    '';
  };

  config = {
  # .bashrc-nix / .profile-nix: pure Home Manager output (via the
  # "gutter eval" in flake.nix).
  home.file.".bashrc-nix".source = bashrcDerivation;
  home.file.".profile-nix".source = profileDerivation;

  # `programs.bash.enable = true` (set in flake.nix) makes Home Manager's
  # own built-in bash module declare `home.file.".bashrc"`/`".profile"`
  # itself, independent of anything in this file. Explicitly disabling
  # these two `home.file` entries (rather than simply not declaring our
  # own) tells HM to skip materializing them at all, leaving the real
  # dotfiles genuinely alone for the activation hook below to manage.
  home.file.".bashrc".enable = lib.mkForce false;
  home.file.".profile".enable = lib.mkForce false;

  # .profile-dots / .bashrc-dots: the hand-authored NIXON-gatekeeper hybrid
  # script. These are dots-owned files under their own name - the REAL
  # ~/.profile/~/.bashrc are left for the user, with a small idempotent
  # activation hook (below) ensuring they source these files, appended
  # only if not already present, never overwriting existing content.
  home.file.".profile-dots" = {
    text = ''
      if [ -z "''${NIXON+x}" ]; then export NIXON=${nixonDefaultStr}; fi
      if [ "$NIXON" = "1" ]; then [[ -f ~/.profile-nix ]] && . ~/.profile-nix; fi
      [[ -f ~/.bashrc-dots ]] && . ~/.bashrc-dots
    '';
  };

  home.file.".bashrc-dots" = {
    text = ''
      # Guard against running twice in the same shell process. Home
      # Manager's own generated ~/.bash_profile (via `programs.bash.enable
      # = true` in flake.nix) unconditionally sources BOTH ~/.profile AND
      # ~/.bashrc (`[[ -f ~/.profile ]] && . ~/.profile` then
      # `[[ -f ~/.bashrc ]] && . ~/.bashrc`) - and ~/.profile-dots (sourced
      # via ~/.profile's own dots-managed hook) already sources this file
      # itself at its end, so for any login shell (including the `nixon`/
      # `nixoff` aliases' `exec bash -l`) this file would otherwise be
      # sourced twice: once nested inside ~/.profile-dots, once again
      # directly via ~/.bashrc's own dots-managed hook. Without this guard,
      # every PATH mutation below (NIXON=0's `/nix`-stripping included)
      # runs twice per login shell, silently accumulating duplicate PATH
      # entries on every nixon/nixoff toggle - confirmed as the real cause
      # of repeated `~/.nix-profile/bin`/`~/.local/bin` entries observed in
      # `$PATH` after a `nixon` → `nixoff` cycle.
      if [ -n "''${_DOTS_BASHRC_DOTS_SOURCED:-}" ]; then
        return 0 2>/dev/null || true
      fi
      _DOTS_BASHRC_DOTS_SOURCED=1

      if [ -z "''${NIXON+x}" ]; then export NIXON=${nixonDefaultStr}; fi

      # --- 0. SHELL FOUNDATIONS (Universal) ---
      # Backfill HOME/USER from the passwd database if a shell somehow
      # got here with either genuinely unset (e.g. `env -i bash -l` -
      # bash itself never re-populates these two, it only falls back to
      # a passwd-db lookup internally for tilde expansion when locating
      # ~/.bash_profile etc, which is why we even got this far). This
      # matters beyond cosmetics: `_nixon_toggle` below only hands a var
      # off across its `exec -c` re-exec if it's currently *set*
      # (`''${!v+x}`), and the store-packaged `nix.sh` (sourced via
      # `.profile-nix`/`hm-session-vars.sh`) silently no-ops unless both
      # are non-empty - so an unset HOME/USER here would otherwise
      # silently propagate into every future `nixon`/`nixoff` re-exec,
      # permanently breaking nix-loading for the rest of the session
      # with no `~/.nix-profile/bin` on `$PATH` and no error message.
      if [ -z "''${HOME:-}" ]; then
        export HOME="$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6)"
      fi
      if [ -z "''${USER:-}" ]; then
        export USER="$(id -un 2>/dev/null)"
      fi

      # Fix TERM for remote/minimal environments before starting logic
      if [ -z "$TERM" ] || [ "$TERM" = "dumb" ]; then
        export TERM=xterm-256color
      fi

      # Better bash behavior
      shopt -s histappend extglob globstar checkjobs

      # Less noisy bell
      echo -n -e "\e[11;30]"
      echo -n -e "\e[10;440]"
     
      # --- 2. THE NIXON GATEKEEPER ---
      #
      # `nixon`/`nixoff` used to be plain `NIXON=<n> exec bash -l` aliases.
      # `exec` replaces the running process image but does NOT clear its
      # environment - every var the old shell had exported (all the nix-
      # injected ones: `NIX_PROFILES`, `XDG_DATA_DIRS`, `NIX_SSL_CERT_FILE`,
      # `MANPATH`, `FONTCONFIG_FILE`, `RUSTC_WRAPPER`, `FZF_DEFAULT_*`,
      # `XCURSOR_PATH`, plus the internal re-entry guards
      # `__HM_SESS_VARS_SOURCED`/`__ETC_PROFILE_NIX_SOURCED`) just carried
      # straight through - so `nixoff` never actually produced a clean
      # host environment, only a PATH that merely *looked* clean.
      #
      # The goal: `nixon`/`nixoff` should always drop you into the SAME
      # environment by default - "as if" you'd started a brand-new login
      # shell with $NIXON already set to 1 or 0 - plus dotsLocal/module-
      # registered vars, plus whatever you explicitly asked to carry over.
      # Some incidental leakage (display/session/socket vars like
      # `DISPLAY`, `SSH_AUTH_SOCK`, `WAYLAND_DISPLAY`) surviving via those
      # allowlists is fine; the important guarantee is no *nix*-specific
      # leftovers (`~/.nix-profile/bin` on `$PATH`, `NIX_PROFILES`, etc.)
      # linger into a `nixoff` shell, and nix-loading in a `nixon` shell
      # is never blocked by a stale re-entry guard surviving from before.
      #
      # `-`/`--` re-exec via `exec -c` (bash builtin: run the given
      # command with a genuinely EMPTY environment), so every toggle
      # rebuilds state from scratch via `/etc/profile` + `.profile-dots`/
      # `.bashrc-dots`, deterministically, with zero leftover cruft. `+`
      # re-execs via plain `exec` (keeps the current environment as-is).
      #
      # Preserved/explicit vars are handed off via `_PRESERVE_<NAME>`
      # shadow vars rather than the real names directly - the real names
      # get restored from these shadows at the very END of this file (see
      # "RESTORE PRESERVED/EXPLICIT VARS" below), i.e. AFTER nix-loading,
      # so they always win last no matter what `.bashrc-nix`/
      # `hm-session-vars.sh` set along the way. `NIXON` itself is the one
      # exception - it's passed straight through under its own name, since
      # `.profile-dots` needs its real value immediately, before
      # `.bashrc-dots` (and the shadow-restore step) even runs.
      #
      # See `_nixon_help` below for the full CLI (`nixon --help`/`nixoff
      # --help`).
      _nixon_help() {
        cat <<'EOF'
Usage: nixon|nixoff [VAR|VAR=value ...] [-|--|+] [COMMAND [ARG...]]

Re-exec into a fresh `bash -l` login shell with $NIXON set to 1 (nixon)
or 0 (nixoff) - by default, the SAME environment every time, "as if"
starting a brand-new login shell in that NIXON state - controlling how
much of the CURRENT shell's environment additionally survives the
re-exec (see modules/core/nixon.nix for the full rationale). Arguments
are parsed in this order - variable specs first, then an optional mode
token, then an optional command:

  VAR         preserve VAR's current value, no matter what mode follows
  VAR=value   set VAR to this explicit value, no matter what mode follows
              (always wins over anything a mode/allowlist would add,
              and over whatever nix-loading itself might set)
  -           (default) fully clean environment, then re-add
              dotsLocal.nixonEnvAllowlist + any module-registered
              core.nixonPreserveVars defaults
  --          fully clean environment - no defaults added, only
              explicit VAR/VAR=value specs survive
  +           keep the current environment as-is (plain `exec`, no `-c`)
  COMMAND     if given, run this via `bash -l -c` instead of dropping
              into an interactive shell; everything after the mode
              token (or after the last VAR spec, if no mode token is
              given) is treated as the command and its arguments.

Examples:
  nixon                          fresh env, nix loaded on top
  nixoff                         fresh env, pure host shell
  nixon -- MY_TOKEN               fully empty env except MY_TOKEN+NIXON
  nixon FOO=bar                  default env, plus FOO=bar
  nixoff + echo hi               keep everything, just run `echo hi`
  nixon -- nix run nixpkgs#hello
EOF
      }

      _nixon_toggle() {
        local target="$1" name="$2"; shift 2

        local -a preserve_vars=() explicit_assigns=() cmd=()
        local mode="-" scanning_vars=1 arg

        for arg in "$@"; do
          if [ "$scanning_vars" = 1 ]; then
            case "$arg" in
              --help|-h)
                _nixon_help
                return 0
                ;;
              -|--|+)
                mode="$arg"
                scanning_vars=0
                continue
                ;;
            esac
            if [[ "$arg" == *=* ]]; then
              explicit_assigns+=("$arg")
              continue
            elif [[ "$arg" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
              preserve_vars+=("$arg")
              continue
            fi
            # Doesn't look like a var spec or a mode token - the command
            # starts here, with the default mode ("-").
            scanning_vars=0
          fi
          cmd+=("$arg")
        done

        # Names whose CURRENT value should be captured and handed off,
        # both directly (`NAME=value`, so it's genuinely set from the
        # very start of the re-exec'd shell - needed because system-level
        # startup files like `/etc/profile.d/nix.sh` run during
        # `/etc/profile`, BEFORE `.profile-dots`/`.bashrc-dots` ever get a
        # chance to run, and some of them - `nix-daemon.sh` computing
        # `$HOME/.nix-profile` for `$PATH` chief among them - genuinely
        # need e.g. `$HOME` to already be correct at that point) and via a
        # `_PRESERVE_<NAME>` shadow var (restored at the very end of
        # `.bashrc-dots`, as a final-say safety net in case anything
        # later in the chain - nix-loading included - clobbers one of
        # them). `-` mode additionally includes dotsLocal's and every
        # module's registered preserve-var names; `--`/`+` only carry
        # over whatever the caller explicitly named.
        local -a preserve_names=()
        if [ "$mode" = "-" ]; then
          preserve_names=${nixonEnvAllowlistBash}
          preserve_names+=${nixonPreserveVarsBash}
        fi
        preserve_names+=("''${preserve_vars[@]}")

        local -a direct_assigns=("NIXON=$target") shadow_assigns=()
        local v
        for v in "''${preserve_names[@]}"; do
          if [ -n "''${!v+x}" ]; then
            direct_assigns+=("$v=''${!v}")
            shadow_assigns+=("_PRESERVE_$v=''${!v}")
          fi
        done
        # Explicit `VAR=value` specs are appended last, so they always
        # win over a same-named preserve entry - `env`/`export` (like
        # plain shell assignment) keep the last assignment when a name
        # repeats.
        local a
        for a in "''${explicit_assigns[@]}"; do
          direct_assigns+=("$a")
          shadow_assigns+=("_PRESERVE_''${a%%=*}=''${a#*=}")
        done

        if [ "$mode" = "+" ]; then
          for a in "''${direct_assigns[@]}" "''${shadow_assigns[@]}"; do
            export "$a"
          done
          if [ "''${#cmd[@]}" -eq 0 ]; then
            exec bash -l
          else
            exec bash -l -c '"$@"' _ "''${cmd[@]}"
          fi
        fi

        if [ "''${#cmd[@]}" -eq 0 ]; then
          exec -c env "''${direct_assigns[@]}" "''${shadow_assigns[@]}" bash -l
        else
          exec -c env "''${direct_assigns[@]}" "''${shadow_assigns[@]}" bash -l -c '"$@"' _ "''${cmd[@]}"
        fi
      }
      nixon() { _nixon_toggle 1 nixon "$@"; }
      nixoff() { _nixon_toggle 0 nixoff "$@"; }

      # `source-nix-daemon`/`source-profile-nix`/`source-hm-session-vars`:
      # manually (re-)run one specific piece of the nix environment setup,
      # without a full `nixon`/re-login. All three share the same shape -
      # each of the three underlying scripts guards itself against being
      # sourced twice per shell via its own internal marker variable
      # (already set the first time it ran - e.g. `/etc/profile` sets
      # `__ETC_PROFILE_NIX_SOURCED` on every login shell, `nixoff`
      # included), so that guard is explicitly cleared first to force a
      # real re-run instead of a silent no-op. Safe to call from either
      # NIXON state (in `nixon` it's just a redundant re-run of what
      # already happened at shell start).
      source-nix-daemon() {
        local script="/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
        if [ ! -e "$script" ]; then
          echo "source-nix-daemon: $script not found" >&2
          return 1
        fi
        unset __ETC_PROFILE_NIX_SOURCED
        . "$script"
      }

      # `~/.profile-nix` (pure Home Manager output) is just a thin wrapper
      # that sources `hm-session-vars.sh` from its nix-store path.
      source-profile-nix() {
        if [ ! -f ~/.profile-nix ]; then
          echo "source-profile-nix: ~/.profile-nix not found" >&2
          return 1
        fi
        unset __HM_SESS_VARS_SOURCED
        . ~/.profile-nix
      }

      # Sources `hm-session-vars.sh` directly via the `~/.nix-profile`
      # symlink (rather than `~/.profile-nix`'s nix-store path) - the same
      # entry point `.bashrc-nix` itself uses.
      source-hm-session-vars() {
        local script=~/.nix-profile/etc/profile.d/hm-session-vars.sh
        if [ ! -e "$script" ]; then
          echo "source-hm-session-vars: $script not found" >&2
          return 1
        fi
        unset __HM_SESS_VARS_SOURCED
        . "$script"
      }

      if [ "$NIXON" = "1" ]; then
        # NIX-ON MODE: Load nix environment
        #
        # The raw system Nix installation (the `nix`/`nh`/`home-manager`
        # binaries themselves) lives at /nix/var/nix/profiles/default/bin -
        # this is NOT part of the Home Manager profile (~/.nix-profile/bin
        # never contains `nix` itself, since Nix is a system-level install,
        # not a home.packages entry), so it's added here explicitly,
        # scoped to NIXON=1 only - unlike the rest of `.bashrc-nix`'s
        # additions, nothing else re-adds this one, so without it a
        # NIXON=1 shell would have no working `nix`/`nh`/`home-manager`.
        # Confirmed as the root cause of a real `nh`/`nix --version`
        # failure during `apply-dots`. This used to run unconditionally
        # (regardless of NIXON), which is exactly why `nixoff` kept
        # showing `/nix/var/nix/profiles/default/bin` on $PATH even after
        # the environment-wipe rework above - moved inside this branch to
        # fix that.
        case ":$PATH:" in
          *":/nix/var/nix/profiles/default/bin:"*) ;;
          *) export PATH="$PATH:/nix/var/nix/profiles/default/bin" ;;
        esac

        # Note: `.bashrc-nix` (pure Home Manager output, not authored by
        # this repo) unconditionally re-sources the `nix` package's own
        # `nix.sh` on its own line, in addition to `hm-session-vars.sh`
        # (which - the *first* time it runs - also sources that same
        # `nix.sh` internally). Since that direct `nix.sh` line has no
        # sourcing guard of its own, a single login shell that reaches
        # `.bashrc-nix` ends up with `$NIX_LINK/bin` (`~/.nix-profile/
        # bin`) prepended to `$PATH` twice in one go - confirmed live,
        # with no `nixon`/`nixoff` toggling involved. This is an upstream
        # Home Manager quirk baked into generated file content we don't
        # control, not something introduced or fixable here - intentionally
        # left as-is rather than papering over it with a PATH dedup pass,
        # which would hide the underlying duplication instead of fixing it.
        [[ -f ~/.bashrc-nix ]] && . ~/.bashrc-nix
      else
        # NON-NIX MODE: Pure host environment. No PATH stripping needed
        # here anymore - `nixon`/`nixoff`'s default (`-`) and `--` modes
        # already re-exec into a genuinely empty environment (`exec -c`),
        # so this branch is reached with nothing nix-related on $PATH to
        # begin with unless `+` mode (deliberately keep-everything) was
        # used, in which case leaving prior nix state alone is the
        # intended behavior for that mode.
        alias ls='ls --color=auto'
        if [ "$EUID" -eq 0 ]; then
          PS1='\[\e[31m\]\u@\h\[\e[0m\]:\[\e[32m\]\w\[\e[0m\]\$ '
        else
          PS1='\[\e[34m\]\u@\h\[\e[0m\]:\[\e[32m\]\w\[\e[0m\]\$ '
        fi
      fi

      # --- 1. DYNAMIC TOOL DISCOVERY (Generic) ---
      # Default alias setup
      alias +="sudo -E "

      # LS_COLORS Baseline
      if command -v vivid >/dev/null 2>&1; then
        export LS_COLORS="$(vivid generate tokyonight-moon)"
      elif command -v dircolors >/dev/null 2>&1; then
        eval "$(dircolors -b)"
      fi

      # Editor/Visual Setup
      for ed in hx helix nvim vim vi nano; do
        if command -v "$ed" >/dev/null 2>&1; then
          export EDITOR="$ed"
          export VISUAL="$ed"
          break
        fi
      done
    
      if ! command -v hx &> /dev/null; then  
        if command -v helix >/dev/null 2>&1; then
          alias hx="$(type -p helix)"
        fi
      fi
      
      if command -v frogmouth>/dev/null 2>&1; then
        alias fm='f() { if [ $# -eq 0 ]; then frogmouth .; else frogmouth "$@"; fi; }; f'
      fi

      # The `bf` butterfish alias is set correctly by butterfish.nix's
      # `programs.bash.shellAliases.bf`, which flows through the real Home
      # Manager bash config into .bashrc-nix - sourced above whenever
      # NIXON=1, no need to duplicate it here.

      # Pager & Previewer Logic
      export PAGER="$(type -p less)"
      export LESS="-RF"

      if command -v bat >/dev/null 2>&1; then
        alias cat="bat -pp"

        if command -v batpipe >/dev/null 2>&1; then
          eval "$(batpipe)"
        fi
        
        if command -v batman >/dev/null 2>&1; then
          alias man="batman"
        fi

        # if command -v batgrep >/dev/null 2>&1; then
        #   alias grep="batgrep"
        # fi
        
        if command -v batdiff >/dev/null 2>&1; then
          alias diff="batdiff"
          alias dt="batdiff --delta"
        fi
        
        if command -v batwatch >/dev/null 2>&1; then
          alias watch="batwatch"
        fi
      fi
            
      # 1. Global FZF Config (The "Source of Truth")
      if command -v fzf >/dev/null 2>&1; then
        export FZF_DEFAULT_OPTS="--height=40% --layout=reverse --border --preview-window='right:60%:wrap:hidden' --bind='?:toggle-preview'"
      
        # 2. Use a Function instead of an Alias to prevent "command not found" errors
        fzf() {
          if command -v bat >/dev/null 2>&1; then
            # We use 'command fzf' to call the binary directly and avoid recursion
            command fzf \
               --preview 'bat --style=numbers --color=always --line-range :500 {} 2>/dev/null || lsd --tree --color=always {} 2>/dev/null || ls -C {}' \
               --bind 'ctrl-e:execute($EDITOR {} < /dev/tty)' \
               "$@"
          else
            command fzf "$@"
          fi
        }
      
        # 3. Optimized Zoxide Interactive (zi)
        if command -v zoxide >/dev/null 2>&1; then
          zi() {
            local dir preview_cmd
                  
            # Smart previewer selection
            if command -v lsd >/dev/null 2>&1; then
              preview_cmd="lsd --tree --depth 2 --color=always {}"
            else
              preview_cmd="ls -C {}"
            fi
      
            # We use 'zoxide query -l' to get the list, then pipe to our new fzf function
            dir=$(zoxide query -l | fzf \
              --preview "$preview_cmd" \
              --preview-window="right:50%:wrap" \
              --bind 'ctrl-delete:execute(zoxide remove {})+reload(zoxide query -l)')
            
            if [[ -n "$dir" ]]; then
              cd "$dir" || return
            fi
          }
        fi
      fi
      export GLOW_STYLE="dark"
      export GLOW_WIDTH="auto"

      # --- 3. RESTORE PRESERVED/EXPLICIT VARS (must run last) ---
      # `_nixon_toggle` hands off preserved/explicit vars via
      # `_PRESERVE_<NAME>` shadow vars instead of the real names directly
      # (see "THE NIXON GATEKEEPER" above), precisely so this rewrite -
      # which runs after nix-loading above - always overwrites whatever
      # `.bashrc-nix`/`hm-session-vars.sh` set, guaranteeing preserved/
      # explicit vars win last, uniformly across `-`/`--`/`+`.
      for _dots_preserved_var in "''${!_PRESERVE_@}"; do
        export "''${_dots_preserved_var#_PRESERVE_}=''${!_dots_preserved_var}"
        unset "$_dots_preserved_var"
      done
      unset _dots_preserved_var
    '';
  };

  # nixexec: Run command in nix-enabled login shell environment
  home.file.".local/bin/nixexec" = {
    executable = true;
    text = ''
      #!/usr/bin/env NIXON=1 /bin/bash -l
      exec "$@"
    '';
  };

  # Idempotent, additive-only hook ensuring the REAL ~/.bashrc/~/.profile
  # source .bashrc-dots/.profile-dots. Appends the source line only if a
  # sentinel comment isn't already present - creates the file fresh if it
  # doesn't exist yet (first-run bootstrap), but never touches/removes any
  # other content a user has in these files. Runs after Home Manager's own
  # file linking (writeBoundary).
  home.activation.ensureDotsShellHook = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    BASHRC_SENTINEL="# dots-managed: source ~/.bashrc-dots (see ~/dots/modules/core/nixon.nix)"
    if [ ! -f "$HOME/.bashrc" ] || ! grep -qF "$BASHRC_SENTINEL" "$HOME/.bashrc" 2>/dev/null; then
      {
        echo ""
        echo "$BASHRC_SENTINEL"
        echo '[[ -f ~/.bashrc-dots ]] && . ~/.bashrc-dots'
      } >> "$HOME/.bashrc"
    fi

    PROFILE_SENTINEL="# dots-managed: source ~/.profile-dots (see ~/dots/modules/core/nixon.nix)"
    if [ ! -f "$HOME/.profile" ] || ! grep -qF "$PROFILE_SENTINEL" "$HOME/.profile" 2>/dev/null; then
      {
        echo ""
        echo "$PROFILE_SENTINEL"
        echo '[[ -f ~/.profile-dots ]] && . ~/.profile-dots'
      } >> "$HOME/.profile"
    fi
  '';
  };
}
