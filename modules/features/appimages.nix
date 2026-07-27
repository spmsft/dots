{ config, lib, pkgs, dotsLocal, ... }:
let
  coreLib = import ../core/lib.nix { inherit lib; };
  cfg = config.features.appimages;

  # Load shared manifests (contexts/common, contexts/<context>)
  loadSharedManifests = { context }: 
    let
      commonPath = ../../contexts/common/appimages/manifest.nix;
      contextPath = ../../contexts/${context}/appimages/manifest.nix;
      
      commonExists = builtins.pathExists commonPath;
      contextExists = builtins.pathExists contextPath;
      
      commonApps = if commonExists then import commonPath else {};
      contextApps = if contextExists then import contextPath else {};
      
      merged = commonApps // contextApps;
    in
      merged;

  # Load host-local appimages from dots-local flake output (schema-typed,
  # defaults to {} - no `or` fallback needed). Every field in the
  # dotsLocal.appimages submodule defaults to `null` when not explicitly
  # set (see schema.nix's comment on why) - strip those out here so the
  # `recursiveUpdate` merge below only overrides fields dots-local
  # ACTUALLY specified, not every option the submodule materializes with
  # its default `null`. Without this, a partial override like
  # `{ tuta.enable = true; }` would incorrectly also reset tuta's
  # file/command/desktopName/categories back to null on top of the
  # catalog's real values, since a schema-validated submodule always has
  # every declared key present (just null-valued if unset) - `//`/
  # `recursiveUpdate` can't tell "explicitly set to null" apart from
  # "never mentioned, defaulted to null" once that's happened.
  hostLocalApps = lib.mapAttrs
    (_: entry: lib.filterAttrs (_: v: v != null) entry)
    dotsLocal.appimages;

  # Check if app should be enabled
  isEnabled = name: app:
    let
      manifestEnabled = app.enable or true;
      moduleOverride = cfg.apps.${name}.enable or null;
    in
      if moduleOverride != null then moduleOverride
      else manifestEnabled;

  # Create wrapper for shared (store-backed) AppImage
  #
  # NOTE on `(app.field or null) != null` below rather than `app.field or
  # default`: `app` can come from either dotsLocal.appimages (schema-typed,
  # where desktopName/categories ALWAYS exist as attrs - possibly with
  # their default null/[] value) or a raw imported shared manifest (not
  # schema-validated, where the attr may genuinely be missing). A plain
  # `or` only helps when the attribute is absent, not when it's present
  # with a null/empty value, so this explicit check is needed to handle
  # both origins correctly.
  mkSharedWrapper = name: app:
    let
      command = app.command or name;
      desktopName = if (app.desktopName or null) != null then app.desktopName else name;
      categories = if (app.categories or []) != [] then app.categories else [ "Utility" ];
      icon = app.icon or (lib.toLower command);
      
      wrapper = pkgs.writeShellScriptBin command ''
        exec ${app.src} "$@"
      '';
      
      desktopEntry = pkgs.makeDesktopItem {
        name = command;
        inherit desktopName icon;
        genericName = desktopName;
        exec = "${command} %U";
        inherit categories;
        comment = "${desktopName} (AppImage)";
      };
    in
      pkgs.symlinkJoin {
        name = "${command}-wrapped";
        paths = [ wrapper desktopEntry ];
      };

  # Create wrapper for host-local (runtime) AppImage
  # (see mkSharedWrapper's comment above for why desktopName/categories use
  # an explicit null/empty check instead of a plain `or`)
  mkHostLocalWrapper = name: app:
    let
      command = app.command or name;
      desktopName = if (app.desktopName or null) != null then app.desktopName else name;
      categories = if (app.categories or []) != [] then app.categories else [ "Utility" ];
      icon = app.icon or (lib.toLower command);
      filePattern = app.file;  # e.g., "Steam-*.AppImage" or "Steam.AppImage"
      
      wrapper = pkgs.writeShellScriptBin command ''
        APPDIR="${cfg.localDir}"
        
        # Find all files matching the pattern and count them
        MATCHING_FILES=$(find "$APPDIR" -maxdepth 1 -name "${filePattern}" -type f 2>/dev/null)
        FILE_COUNT=$(echo "$MATCHING_FILES" | grep -c '^' || echo "0")
        
        if [[ "$FILE_COUNT" -eq 0 ]]; then
          echo "ERROR: No AppImage found matching '${filePattern}' in $APPDIR" >&2
          echo "Place the AppImage file there and ensure it matches the pattern" >&2
          exit 1
        fi
        
        if [[ "$FILE_COUNT" -gt 1 ]]; then
          echo "ERROR: Multiple AppImages found matching '${filePattern}' in $APPDIR" >&2
          echo "Please keep only one version. Found:" >&2
          echo "$MATCHING_FILES" | sed 's/^/  /' >&2
          exit 1
        fi
        
        # Exactly one match - use it
        TARGET=$(echo "$MATCHING_FILES" | head -1)
        
        if [[ ! -x "$TARGET" ]]; then
          echo "ERROR: AppImage is not executable: $TARGET" >&2
          echo "Run: chmod +x '$TARGET'" >&2
          exit 1
        fi
        
        exec "$TARGET" "$@"
      '';
      
      desktopEntry = pkgs.makeDesktopItem {
        name = command;
        inherit desktopName icon;
        genericName = desktopName;
        exec = "${command} %U";
        inherit categories;
        comment = "${desktopName} (AppImage)";
      };
    in
      pkgs.symlinkJoin {
        name = "${command}-wrapped";
        paths = [ wrapper desktopEntry ];
      };

  # Determine which wrapper to use based on app definition
  mkWrappedApp = name: app:
    if app ? file then mkHostLocalWrapper name app
    else if app ? src then mkSharedWrapper name app
    else null;

  # Load and merge all apps. `lib.recursiveUpdate` rather than `//` is
  # important here: dots-local's entries are usually *partial overrides*
  # of an app already fully defined in the shared catalog (e.g.
  # `{ tuta.enable = true; }` to enable a cataloged app without
  # redefining its file/command/desktopName/categories) - `//` would
  # replace the WHOLE app entry per name, silently dropping every field
  # dots-local's partial entry didn't also set. `recursiveUpdate` merges
  # field-by-field instead, so only the fields dots-local actually
  # specifies get overridden.
  sharedApps = loadSharedManifests { context = dotsLocal.context; };
  allApps = lib.recursiveUpdate sharedApps hostLocalApps;
  
  # Filter enabled and create packages
  enabledApps = lib.filterAttrs isEnabled allApps;
  wrappedPackages = lib.filter (x: x != null) (lib.mapAttrsToList mkWrappedApp enabledApps);
in
{
  options.features.appimages = {
    enable = coreLib.mkDefaultDisabledOption "AppImage support via simple wrapper scripts";
    
    localDir = lib.mkOption {
      type = lib.types.str;
      default =
        if dotsLocal.appimagesDir != null then dotsLocal.appimagesDir
        else "${config.home.homeDirectory}/Applications/AppImages";
      description = ''
        Directory where host-local AppImages are stored at runtime.
        These AppImages are not imported into the Nix store.
      '';
    };
    
    apps = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          enable = lib.mkOption {
            type = lib.types.nullOr lib.types.bool;
            default = null;
            description = ''
              Whether to enable this AppImage. 
              null = use manifest default (usually enabled)
              true/false = override manifest setting
            '';
          };
        };
      });
      default = {};
      description = ''
        Per-AppImage enable overrides. Set appname.enable = false to disable 
        a specific AppImage from the manifest without removing it.
      '';
      example = lib.literalExpression ''
        {
          steam.enable = false;  # Disable steam even if in manifest
        }
      '';
    };
  };

  config = lib.mkMerge [
    # AppImages are typically desktop apps not (yet) packaged for Nix/the
    # native package manager - only worth the wrapper-script/catalog-merge
    # machinery on a machine that actually has a GUI to run them on. No
    # separate dotsLocal toggle for this - it rides directly on the same
    # `core.enableGuiDefaults` axis as suites.gui-apps/suites.pim-apps
    # (which already correctly ANDs dotsLocal.enableGuiDefaults with
    # graphicalBackend != "none" - see modules/core/platform.nix). Still
    # just `mkDefault` - an explicit `features.appimages.enable = false;`
    # (or `= true;` on a CLI-only machine that still wants this) always
    # wins.
    { features.appimages.enable = lib.mkDefault config.core.enableGuiDefaults; }
    # Tolaria (priv context only) is a GUI-only app - default it on
    # whenever there's a real GUI backend, same condition as the feature's
    # own enable above, rather than leaving it opt-in-per-machine like
    # every other cataloged app (see contexts/priv/appimages/manifest.nix's
    # own comment). Still just mkDefault - dots-local can still override.
    { features.appimages.apps.tolaria.enable = lib.mkDefault config.core.enableGuiDefaults; }
    (lib.mkIf cfg.enable {
      home.packages = with pkgs; [
        appimage-run
        appimageupdate
      ] ++ wrappedPackages;

      # Each cataloged/host-local AppImage is itself a "non-standard"
      # tool by this registry's own definition (a downloaded/wrapped
      # binary, not a nix package or its alien equivalent) - registered
      # generically here rather than one entry per app, so new catalog
      # entries (contexts/*/appimages/manifest.nix, dots-local's own
      # appimages.*) show up automatically with no further edits needed.
      dots.tools = lib.mapAttrsToList
        (name: app: {
          name = app.command or name;
          synopsis = "AppImage: ${app.desktopName or name}.";
          feature = "features.appimages.apps.${name}";
        })
        enabledApps;
    })
  ];
}
