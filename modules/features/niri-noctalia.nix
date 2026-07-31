{ config, pkgs, inputs, lib, alien, dotsLocal, ... }: 

let
  coreLib = import ../core/lib.nix { inherit lib; };
  cfg = config.features.niri-noctalia;
  # Font family names this desktop expects to be available - wired into
  # features.fonts.required below. terminalFont ("IosevkaTerm NFM" = the
  # Nerd Font Mono variant of Iosevka Term) is already satisfied by
  # features.fonts.base's default nerd-fonts.iosevka-term package - no
  # extra contribution needed, kept here purely as documentation of the
  # dependency. uiFont ("Inter") is NOT covered by fonts.base by default,
  # so it's actually contributed to features.fonts.required below
  # (fonts.nix's fontconfig.defaultFonts already lists "Inter" as the
  # preferred sansSerif font - without this, that preference silently
  # falls through to the next entry since no package actually providing
  # "Inter" is installed otherwise).
  terminalFont = "IosevkaTerm NFM";
  uiFont = "Inter";
  
  # Determine if we're using alien packages
  useAlienNiri = alien.has "niri";
  useAlienNoctalia = alien.has "noctalia-shell";
  
  # Get noctalia package/binary path
  # For alien: use 'qs -c noctalia-shell' (noctalia-qs package provides 'qs' binary)
  # For nix: use the full path to noctalia-shell binary
  noctaliaPkg = if useAlienNoctalia then "noctalia-shell" else inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default;
  noctaliaBin = if useAlienNoctalia then "qs -c noctalia-shell" else "${noctaliaPkg}/bin/noctalia-shell";
  
  # Get niri package (use regular niri to avoid tuning conflicts). Only
  # referenced in the non-alien branch at the ExecStart site below.
  niriPkg = pkgs.niri;
in {
  # Import nix modules (always import, but conditionally enable)
  imports = [ inputs.niri.homeModules.niri inputs.noctalia.homeModules.default ];

  options.features.niri-noctalia = {
    enable = coreLib.mkDefaultDisabledOption "Enable niri + noctalia desktop environment";
    
    terminal = lib.mkOption {
      type = lib.types.str;
      default = "ghostty";
      description = "Terminal emulator command to use (must be on PATH)";
    };

    terminalAppId = lib.mkOption {
      type = lib.types.str;
      default = "com.mitchellh.ghostty";
      description = "App ID of the terminal emulator for window tracking";
    };

    terminalScratchpadSuffix = lib.mkOption {
      type = lib.types.str;
      default = "scratchpad";
      description = "Suffix appended to app-id for scratchpad windows";
    };

    renderDrmDevice = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Path to DRM render device for niri debug configuration (e.g., /dev/dri/by-path/...)";
    };

    configText = lib.mkOption {
      type = lib.types.str;
      default = ''
        // --- NIRI STARTUP ---

        // Noctalia (GTK/quickshell)
        spawn-sh-at-startup "${noctaliaBin}"

        // User Apps
        spawn-at-startup "keepassxc"
        spawn-at-startup "nm-applet" "--indicator"
        // spawn-at-startup "${cfg.terminal}"
      
        // Initialization
        spawn-sh-at-startup "niri msg action focus-workspace hidden && niri msg action focus-workspace 1"
      
        input {
          keyboard {
            xkb {
              layout "us,de"
            }
          }
          touchpad {
            tap
            natural-scroll
            accel-speed 0.2
            scroll-method "two-finger"
          }
          focus-follows-mouse
          warp-mouse-to-focus
        }

        debug {
            honor-xdg-activation-with-invalid-serial
            ${lib.optionalString (cfg.renderDrmDevice != null) ''render-drm-device "${cfg.renderDrmDevice}"''}
        }      
      
        layout {
          gaps 16
          struts { left 0; right 0; top 0; bottom 0; }
          center-focused-column "never"
          default-column-width { proportion 0.5; }
          
          focus-ring {
            width 1
            active-gradient from="#7aa2f7" to="#bb9af7" angle=45
            inactive-color "#414868"
          }

          border { off; }

          shadow {
            on
            softness 30
            spread 2
            offset x=0 y=4
            color "rgba(0, 0, 0, 0.5)"
            inactive-color "rgba(0, 0, 0, 0.3)"
          }

          preset-column-widths {
            proportion 0.25
            proportion 0.33
            proportion 0.5
            proportion 0.66
            proportion 0.75
          }
        }

        animations {
          window-open { duration-ms 250; curve "ease-out-quad"; }
          window-close { duration-ms 250; curve "ease-out-expo"; }
          horizontal-view-movement { spring damping-ratio=0.8 stiffness=350 epsilon=0.0001; }
          workspace-switch { spring damping-ratio=1.0 stiffness=450 epsilon=0.0001; }
          window-movement { spring damping-ratio=1.0 stiffness=600 epsilon=0.0001; }
          window-resize { spring damping-ratio=1.0 stiffness=500 epsilon=0.0001; }
        }

        hotkey-overlay {
          skip-at-startup
        }
                 
        overview {
          zoom 0.42
          backdrop-color "rgba(0, 0, 0, 0.5)"
        }

        layer-rule {
          match namespace="^launcher$"
          baba-is-float true
        }
      
        layer-rule {
          match namespace="^ghostty-scratchpad.*"
          baba-is-float true          
        }   
         
        layer-rule {
          match namespace="^noctalia-.*"
        }   
           
        layer-rule {
          match namespace=".*"
          geometry-corner-radius 12
          shadow { on; }
        }

        window-rule {
          geometry-corner-radius 12
          clip-to-geometry true      
        }

        window-rule {
          match app-id="launcher"
          default-window-height { proportion 0.4; }
        }

        window-rule {
          match app-id="^com\\.mitchellh\\.ghostty\\.scratchpad$"
          open-floating true
          block-out-from "screen-capture"
          default-column-width { proportion 0.8; }
          default-window-height { proportion 0.6; }
        }
      
        window-rule {
          match is-floating=true
          shadow {
            on
            softness 60
            spread 10
            offset x=0 y=12
            color "rgba(0, 0, 0, 0.66)"
          }
        }

        window-rule {
          match is-active=false
          opacity 0.9
          border {
            on
            width 1
            active-color "rgba(122, 162, 247, 0.3)"
          }
        }
      
        window-rule {
          match is-active=true
          border {
            on
            width 2
            active-color "#7aa2f7"
          }
        }

        window-rule {
          match app-id="com.mitchellh.ghostty"
          draw-border-with-background false
        }

        window-rule {
          match app-id="^org.keepassxc.KeePassXC$"
          open-on-workspace "pass"
          open-maximized false
          block-out-from "screen-capture"
        }
      
        binds {
          "Mod+Comma" { spawn "sh" "-c" "${noctaliaBin} ipc call plugin:keybind-cheatsheet toggle"; }
          "Mod+Shift+Comma" { show-hotkey-overlay; }
          
          "Mod+Return" { spawn "sh" "-c" "env NIXON=1 ${cfg.terminal} -e bash -l"; }
          "Mod+Alt+Return" { spawn "${cfg.terminal}"; }
          
          "Mod+Shift+Return" { spawn "sh" "-c" "env NIXON=1 $HOME/.nix-profile/bin/terminal-in-current-column -e bash -l"; }
          "Mod+Shift+Alt+Return" { spawn "$HOME/.nix-profile/bin/terminal-in-current-column"; }
          
          "Mod+Grave" { spawn "$HOME/.nix-profile/bin/terminal-scratchpad-toggle"; }
          
          "Mod+Shift+C" { spawn "sh" "-l" "-c" "niri msg action center-column"; }
          "Mod+D" { spawn "sh" "-c" "${noctaliaBin} ipc call launcher toggle"; }          
          "Mod+S" { spawn "sh" "-c" "${noctaliaBin} ipc call controlCenter toggle"; }
          "Mod+M" { spawn "sh" "-c" "wdisplays"; }
          "Mod+Q" { close-window; }
          "Mod+Shift+E" { quit; }

          "Mod+H" { focus-column-or-monitor-left; }
          "Mod+L" { focus-column-or-monitor-right; }
          "Mod+J" { focus-workspace-down; }
          "Mod+K" { focus-workspace-up; }
             
          "Mod+Shift+H" { move-column-left-or-to-monitor-left; }
          "Mod+Shift+L" { move-column-right-or-to-monitor-right; }
          "Mod+Shift+J" { move-window-to-workspace-down; }
          "Mod+Shift+K" { move-window-to-workspace-up; }
             
          "Mod+Alt+J" { focus-window-or-monitor-down; }
          "Mod+Alt+K" { focus-window-or-monitor-up; }
             
          "Mod+Ctrl+J" { move-window-down; }
          "Mod+Ctrl+K" { move-window-up; }
                 
          "Mod+Tab" { toggle-overview; }
          "Mod+F" { maximize-column; }
          "Mod+Shift+F" { fullscreen-window; }
          "Mod+C" { center-column; }
          "Mod+V" { toggle-window-floating; }
          "Mod+Space" { switch-layout "next"; }
          "Mod+BracketLeft" { consume-or-expel-window-left; }
          "Mod+BracketRight" { consume-or-expel-window-right; }
          "Mod+Ctrl+P" { screenshot-screen; }
          "Mod+Alt+P" { screenshot-window; }

          "XF86AudioRaiseVolume" { spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "0.02+"; }
          "XF86AudioLowerVolume" { spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "0.02-"; }
          "XF86AudioMute" { spawn "wpctl" "set-mute" "@DEFAULT_AUDIO_SINK@" "toggle"; }
          "XF86MonBrightnessUp" { spawn "brightnessctl" "set" "10%+"; }
          "XF86MonBrightnessDown" { spawn "brightnessctl" "set" "10%-"; }

          "Mod+R" { switch-preset-column-width; }
          "Mod+Minus" { set-column-width "-10%"; }
          "Mod+Equal" { set-column-width "+10%"; }
          "Mod+Shift+Minus" { set-window-height "-10%"; }
          "Mod+Shift+Equal" { set-window-height "+10%"; }

          "Mod+1" { focus-workspace 1; }
          "Mod+2" { focus-workspace 2; }
          "Mod+3" { focus-workspace 3; }
          "Mod+4" { focus-workspace 4; }
          "Mod+Shift+1" { spawn "sh" "-c" "niri msg action move-window-to-workspace 1 && niri msg action focus-workspace 1"; }
          "Mod+Shift+2" { spawn "sh" "-c" "niri msg action move-window-to-workspace 2 && niri msg action focus-workspace 2"; }
          "Mod+Shift+3" { spawn "sh" "-c" "niri msg action move-window-to-workspace 3 && niri msg action focus-workspace 3"; }
          "Mod+Shift+4" { spawn "sh" "-c" "niri msg action move-window-to-workspace 4 && niri msg action focus-workspace 4"; }
                  
          "Mod+Alt+1" { focus-monitor "0"; }
          "Mod+Alt+2" { focus-monitor "1"; }
          "Mod+Alt+3" { focus-monitor "2"; }
          "Mod+Alt+4" { focus-monitor "3"; }
        
          "Mod+Alt+Shift+1" { move-column-to-monitor "0"; }
          "Mod+Alt+Shift+2" { move-column-to-monitor "1"; }          
          "Mod+Alt+Shift+3" { move-column-to-monitor "2"; }          
          "Mod+Alt+Shift+4" { move-column-to-monitor "3"; }    
          
          "Mod+WheelScrollDown"      { focus-column-right; }
          "Mod+WheelScrollUp"        { focus-column-left; }
          "Mod+Ctrl+WheelScrollDown" { move-column-right; }
          "Mod+Ctrl+WheelScrollUp"   { move-column-left; }  
          
          "Mod+Alt+H" { focus-monitor-left; }
          "Mod+Alt+L" { focus-monitor-right; }

          "Mod+Alt+Shift+H" { spawn "sh" "-c" "niri msg action move-column-to-monitor-left && niri msg action focus-monitor-left"; }
          "Mod+Alt+Shift+L" { spawn "sh" "-c" "niri msg action move-column-to-monitor-right && niri msg action focus-monitor-right"; }
           
          "Mod+N" { spawn "sh" "-c" "${noctaliaBin} ipc call plugin:notifications toggle"; }
          "Mod+0" { spawn "sh" "-c" "${noctaliaBin} ipc call plugin:power-menu toggle"; } 
        }
      '';
      description = "Niri configuration (KDL format)";
    };
  };

  config = lib.mkMerge [
    {
      # Noctalia's user-editable settings (colors, layout, plugin
      # config) live under ~/.config/noctalia - if this feature is
      # enabled, that config needs to actually be synced somewhere or
      # it's at risk of getting lost (e.g. on a fresh `apply-dots` on a
      # new machine, or if the runtime dir is ever wiped). Deliberately
      # NOT auto-enabling the "noctalia" syncable just because this
      # feature is on: syncables must be enabled manually (see
      # modules/core/syncables.nix and SYNC.md) so that temporarily
      # disabling this feature (e.g. testing a different compositor)
      # never silently disables syncing of config you still want kept.
      assertions = [
        {
          assertion = !cfg.enable || builtins.elem "noctalia" dotsLocal.sync.enable;
          message = ''
            features.niri-noctalia is enabled, but the "noctalia" syncable
            is not in dotsLocal.sync.enable. Noctalia's user-editable
            settings (colors.json, settings.json, plugin config under
            ~/.config/noctalia) won't be tracked/synced without it.
            Add "noctalia" to sync.enable in your dots-local/flake.nix
            (see modules/core/syncables.nix for what it tracks).
          '';
        }
      ];
    }
    (lib.mkIf cfg.enable {
    # Declare alien packages as enabled (both are always enabled when feature is on)
    alienPackages.enabledPackages = [ "niri" "noctalia-shell" ];

    # Contribute the UI font this desktop actually needs to the shared
    # features.fonts.required extension point (see the terminalFont/uiFont
    # comment above for the full explanation).
    features.fonts.required = [ pkgs.inter ];

    # Systemd service files - use correct niri binary
    home.file.".config/systemd/user/niri.service".text = ''
      [Unit]
      Description=A scrollable-tiling Wayland compositor
      BindsTo=graphical-session.target
      Before=graphical-session.target
      Wants=graphical-session-pre.target
      After=graphical-session-pre.target

      Wants=xdg-desktop-autostart.target
      Before=xdg-desktop-autostart.target

      [Service]
      Slice=session.slice
      Type=notify
      ExecStart=${if useAlienNiri then "/usr/bin/niri" else "${niriPkg}/bin/niri"} --session

      [Install]
      WantedBy=default.target
    '';
    
    home.file.".config/systemd/user/niri-shutdown.target".text = ''
      [Unit]
      Description=Shutdown Niri
      DefaultDependencies=false
      After=graphical-session.target
    '';

    # Always write niri config directly (never use programs.niri)
    home.file.".config/niri/config.kdl" = {
      text = cfg.configText;
    };

    # Helper scripts - the bulk of each script's logic lives in a real,
    # static, shellcheck-able file under ./niri-noctalia/. Each Nix-string
    # preamble below resolves the Nix-level values (cfg.*/pkgs.* package
    # paths) into plain shell variables that the static script references.
    home.packages = [
      (pkgs.writeShellScriptBin "terminal-in-current-column" (''
        #!/bin/sh
        set -eu

        term="${cfg.terminal}"
        appid="${cfg.terminalAppId}"
        py="${pkgs.python3}/bin/python3"

      '' + builtins.readFile ./niri-noctalia/terminal-in-current-column.sh))

      (pkgs.writeShellScriptBin "terminal-scratchpad-toggle" (''
        #!/bin/sh
        set -eu

        term="${cfg.terminal}"
        appid="${cfg.terminalAppId}"
        scratch_suffix="${cfg.terminalScratchpadSuffix}"
        scratch_app_id="${cfg.terminalAppId}.${cfg.terminalScratchpadSuffix}"
        byobu="${pkgs.byobu}/bin/byobu"
        py="${pkgs.python3}/bin/python3"
        session_name="scratchpad"

      '' + builtins.readFile ./niri-noctalia/terminal-scratchpad-toggle.sh))

      (pkgs.writeShellScriptBin "start-xwayland-satellite" (''
        #!/bin/sh
        set -eu

        XWAYLAND_SATELLITE_BIN="${pkgs.xwayland-satellite}/bin/xwayland-satellite"
        XLSCLIENTS_BIN="${pkgs.xlsclients}/bin/xlsclients"

      '' + builtins.readFile ./niri-noctalia/start-xwayland-satellite.sh))

      (pkgs.writeShellScriptBin "wait-for-x11" (''
        #!/bin/sh
        set -eu

        XLSCLIENTS_BIN="${pkgs.xlsclients}/bin/xlsclients"

      '' + builtins.readFile ./niri-noctalia/wait-for-x11.sh))
    ];

    dots.tools = [
      {
        name = "terminal-in-current-column";
        synopsis = "Open/focus a terminal in niri's currently focused column.";
        feature = "features.niri-noctalia";
      }
      {
        name = "terminal-scratchpad-toggle";
        synopsis = "Toggle a dedicated dropdown/scratchpad terminal (byobu session) in niri.";
        feature = "features.niri-noctalia";
      }
      {
        name = "start-xwayland-satellite";
        synopsis = "Start xwayland-satellite for running X11 apps under niri.";
        feature = "features.niri-noctalia";
      }
      {
        name = "wait-for-x11";
        synopsis = "Block until an X11 server (xwayland-satellite) is ready.";
        feature = "features.niri-noctalia";
      }
    ];

    # GTK/Qt theming - commented out, not niri/noctalia specific
    # gtk = {
    #   enable = true;
    #   theme = {
    #     name = "Adwaita-dark";
    #     package = pkgs.gnome-themes-extra;
    #   };
    #   gtk3.extraConfig.gtk-application-prefer-dark-theme = 1;
    #   gtk4.extraConfig.gtk-application-prefer-dark-theme = 1;
    # };

    # qt = {
    #   enable = true;
    #   platformTheme.name = "gtk";
    #   style.name = "adwaita-dark";
    # };
    
    # home.sessionVariables = {
    #   GTK_THEME = "Adwaita-dark";
    # };

    # Launch script - uses niri-session with systemd service
    # Use this when running from a display manager (SDDM, GDM, etc.)
    home.file.".local/bin/niri-launch-systemd" = {
      executable = true;
      text = ''
        #!/bin/sh
        ${if useAlienNiri then "exec niri-session" else "exec nixexec niri-session"} "$@"
      '';
    };
    
    # Direct launch script - runs niri directly without systemd service
    # Use this from TTY (multi-user.target) - bypasses Type=notify deadlock
    home.file.".local/bin/niri-launch-direct" = {
      executable = true;
      text = ''
        #!/bin/sh
        # Run niri directly without systemd service (bypasses Type=notify deadlock)
        
        # Import minimal environment
        export XDG_SESSION_TYPE=wayland
        export XDG_CURRENT_DESKTOP=niri
        
        # Update D-Bus
        if command -v dbus-update-activation-environment >/dev/null 2>&1; then
            dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE 2>/dev/null || true
        fi
        
        # Run niri directly with optional debug logging
        if [ "$1" = "--debug" ]; then
            shift
            exec niri --session 2>&1 | tee /tmp/niri-direct.log
        else
            exec niri --session "$@"
        fi
      '';
    };
    })
  ];
}
