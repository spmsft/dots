# dots-local identity + machine config.
#
# This is a REAL, standalone Nix file - edit it directly (it's not
# regenerated or overwritten by anything after setup.sh's initial copy).
# Run `dots-local-options` (or `nix eval --json .#dotsLocalOptionsDoc` in
# the dots repo) to see every field below, plus any not shown in this
# starter template, with its type/default/full description - generated
# live from dots/modules/local/schema.nix, so it's always accurate.
#
# `@@TOKEN@@`-style placeholders below were filled in by setup.sh from
# your answers/environment at bootstrap time - safe to hand-edit
# afterward, nothing re-templates this file.
{
  outputs = { self, ... }:
    let
      system = "@@SYSTEM@@";
      barch = "@@BARCH@@";
      march = "@@MARCH@@";
      distro = "@@DISTRO@@";
    in {
      inherit system barch march distro;
      host = "@@HOSTNAME@@";
      realname = "First Last";
      realmail = "first@last.com";
      username = "@@USERNAME@@";
      uid = "@@UID@@";
      gid = "@@GID@@";
      homeDirectory = "@@HOMEDIR@@";
      context = "@@CONTEXT@@";
      nixonDefault = false;
      # enableGuiDefaults defaults to false, and is also automatically
      # forced off whenever graphicalBackend is "none" (the default) -
      # see dots-local-options for the full description. Uncomment both
      # together once this machine actually has a graphical desktop:
      # enableGuiDefaults = true;
      # graphicalBackend = "wayland";   # or "x11"/"wsl"/"macos"

      # Hardware/context axes - all optional, uncomment and set what
      # applies to this machine (see `dots-local-options` for the full
      # list and what each one drives, via dots/modules/rules.nix).
      # gpu = "nvidia";           # or "amd" / "intel" / omit entirely
      # compositor = "niri";      # omit for a CLI-only machine
      # isWsl = true;              # if running under WSL

      # Per-machine hardware/peripheral config - all fields optional.
      # machine = {
      #   sshIdentityFile = "~/.ssh/id_github_@@HOSTNAME@@";
      #   sshAddKeysToAgent = "yes";            # "yes"/"no"/"ask"/"confirm"/a duration like "10m"
      #   terminal = "ghostty";                # only used if compositor == "niri"
      #   renderDrmDevice = null;               # let niri auto-detect, or set explicitly
      #   display = {                           # omit entirely to skip power-toggle.sh
      #     output = "eDP-1";
      #     ecoMode = { resolution = "1920x1200"; brightness = "30%"; };
      #     perfMode = { resolution = "1920x1200"; refreshRate = "120.000"; };
      #   };
      # };

      # For anything too bespoke to express as an axis above (e.g. exact
      # CUDA/compiler flags for one particular GPU) - host.nix (next to
      # this file) is where that goes, deliberately almost empty until
      # you actually need it. No need to weave the hostname into the
      # filename - one machine, one dots-local checkout, one host.nix.
      extraModules = [ ./host.nix ];

      # Butterfish / local LLM endpoint - only needed if features.butterfish
      # is enabled somewhere (off by default).
      # butterfishEndpoint = "http://127.0.0.1:5001/v1";
      # butterfishApiKey = "talk-to-me";
      # butterfishModel = "default";

      # AppImages configuration
      appimagesDir = "@@HOMEDIR@@/Applications/AppImages";
      appimages = import ./appimages.nix;

      # Tuning flags per language and mode - OPTIONAL overrides only.
      # dots itself already ships sensible defaults for every
      # lang/mode combination (see dots/modules/core/tune-defaults.nix) -
      # you only need to set tune.flags here if you want to override one
      # of those defaults for this specific machine. Example:
      # tune = {
      #   flags = {
      #     c.fast = "-Ofast -march=${march} -pipe -flto=auto -ffast-math";
      #   };
      # };

      # Taskwarrior/TaskChampion sync - off by default (no sync.server.url/
      # sync.encryption_secret are ever written to ~/.taskrc unless BOTH a
      # server URL - explicit `url`, or implied by `autoSpawnServer` - AND
      # `credential` are set; see `dots-local-options` for full details of
      # each field). A random credential was pre-generated below by
      # setup.sh so you don't need to invent a secure secret by hand the
      # moment you decide to turn this on - every device syncing to the
      # same server must share this exact value.
      # taskSync = {
      #   autoSpawnServer = true;   # run taskchampion-sync-server locally via systemd --user
      #   interface = "127.0.0.1"; # or "0.0.0.0" to accept connections from other machines
      #   port = 8080;
      #   credential = "@@TASK_SYNC_CREDENTIAL@@";
      #   syncInterval = "never";  # e.g. "15m"/"1h", or "never" to only sync manually
      # };

      # Sync configuration - track handcrafted configs that survive nix
      # rebuilds. Named syncables (defined once in dots's
      # modules/core/syncables.nix, not copy-pasted per machine) are
      # activated by name; `tracked` stays available for genuinely ad-hoc,
      # machine-specific patterns not worth registering. Uncomment and
      # customize to enable:
      # sync = {
      #   enable = [ "noctalia" ];
      #   tracked = [
      #     {
      #       pattern = ".config/some-other-app/**";
      #       type = "home";
      #       on_new = "prompt";
      #       ignore = [];
      #     }
      #   ];
      # };
    };
}
