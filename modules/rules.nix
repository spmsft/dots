# Declarative, pure-data dependency rules over dotsLocal axes - simple
# rules like "if AI hardware enabled, pull in AI packages", instead of
# scattering host-specific enable-flag decisions across per-host files.
#
# Each rule is `{ when = d: bool; set = d: <attrset merged into config, via
# lib.mkDefault>; }` - both `when` AND `set` are functions of `dotsLocal`
# (named `d` for brevity), since some rules need to read a dotsLocal value
# into their `set` output (e.g. `machine.terminal`), not just decide
# whether to fire. `lib.mkDefault` means these set *defaults* - an explicit
# override elsewhere (e.g. a context module, or a dotsLocal.extraModules
# file) always wins.
#
# Keep this file small and readable - it's meant to be skimmed to
# understand "what does this machine get and why", not to hold every
# possible toggle (fine-grained suite configuration still lives in
# modules/contexts/<context>.nix).
{ lib, dotsLocal }:

[
  {
    when = d: d.compositor == "niri";
    set = d: {
      features.niri-noctalia.enable = true;
      features.niri-noctalia.terminal = d.machine.terminal;
      features.niri-noctalia.renderDrmDevice = d.machine.renderDrmDevice;
    };
  }

  {
    when = d: d.gpu == "nvidia";
    set = d: {
      features.llama-cpp.enable = true;
      suites.ai-apps.enable = true;
      suites.ai-apps.pi = true;
    };
  }

  {
    when = d: d.context == "work";
    set = d: {
      suites.cloud-tools.enable = true;
    };
  }

  {
    when = d: d.isWsl;
    set = d: {
      features.opener.enable = true;
      features.clipboard.enable = true;
      features.notify.enable = true;
      features.wsl-shell-integration.enable = true;
      home.sessionVariables.WAYLAND_DISPLAY = "wayland-0";
      home.sessionVariables.DIRENV_LOG_FORMAT = "";
    };
  }

  # opener/clipboard/notify need a UI/backend to actually do anything
  # useful (xdg-open a browser, wl-copy into a Wayland clipboard,
  # notify-send a toast, ...) - only enable them by default when one is
  # actually present: a niri (currently the only supported compositor)
  # desktop, or WSL (handled by the rule above). A host with neither
  # (compositor == null, not WSL) stays CLI-only: these remain disabled,
  # matching features.network/every other suite's off-by-default
  # convention.
  # NOTE: the actual backend VALUE (wayland/x11/wsl/macos) is no longer
  # set here - all three features read the shared, derived
  # `config.core.platformBackend` instead (modules/core/platform.nix),
  # which computes the exact same value from these same dotsLocal axes.
  # This rule only needs to decide WHETHER to enable them.
  {
    when = d: !d.isWsl && d.compositor != null;
    set = d: {
      features.opener.enable = true;
      features.clipboard.enable = true;
      features.notify.enable = true;
    };
  }
]
