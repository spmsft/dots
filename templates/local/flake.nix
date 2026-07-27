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
      # nixonEnvAllowlist has a sensible built-in default (TERM, HOME,
      # DISPLAY/WAYLAND_DISPLAY, SSH_AUTH_SOCK, WSL interop vars, etc. -
      # see dots-local-options for the full list) covering what `nixon`/
      # `nixoff` preserve across their `exec -c` re-exec. Only needed here
      # to add machine-specific extras beyond that default:
      # nixonEnvAllowlist = [ "MY_EXTRA_VAR" ];

      # enableGuiDefaults defaults to false, and is also automatically
      # forced off whenever graphicalBackend is "none" (the default) -
      # see dots-local-options for the full description. Uncomment both
      # together once this machine actually has a graphical desktop:
      # enableGuiDefaults = true;
      # graphicalBackend = "wayland";   # or "x11"/"wsl"/"macos"

      # Lua/LuaJIT defaults for suites.dev-tools - both optional, shown
      # here at their actual defaults (lua on, luajit off) purely for
      # reference; uncomment only to override:
      # lua = {
      #   enable = true;   # suites.dev-tools.lua (pkgs.lua5_4: `lua`/`luac`)
      #   jit = false;     # suites.dev-tools.luajit (pkgs.luajit: `luajit`)
      # };

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
      #   cudaComputeCap = "89";                # only if gpu == "nvidia": enables parat's cuda build
      #   mklSupport = true;                    # CPU-only, independent of gpu: enables parat's mkl build
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
      # sync.server.client_id/sync.encryption_secret are ever written to
      # ~/.taskrc unless a server URL - explicit `url`, or implied by
      # `autoSpawnServer` - AND `clientId` AND `credential` are all set;
      # see `dots-local-options` for full details of each field). A
      # random credential and clientId were pre-generated below by
      # setup.sh so you don't need to invent them by hand the moment you
      # decide to turn this on - every device/app syncing to the same
      # task list (including e.g. lazytask, on the SAME machine) must
      # share these exact values (clientId identifies the shared task
      # list itself, not a per-device identity - see
      # modules/features/task-sync.nix's 2026-07-21 correction note).
      # taskSync = {
      #   autoSpawnServer = true;   # run taskchampion-sync-server locally via systemd --user
      #   interface = "127.0.0.1"; # or "0.0.0.0" to accept connections from other machines
      #   port = 9999;
      #   clientId = "@@TASK_SYNC_CLIENT_ID@@";
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
