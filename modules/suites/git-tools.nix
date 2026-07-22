{ config, lib, pkgs, alien, dotsLocal, ... }:

let
  cfg = config.suites.git-tools;
  coreLib = import ../core/lib.nix { inherit lib; };
  # `delta` is deliberately NOT in this appSet - `programs.delta.enable`
  # below already adds its package unconditionally (its `package` option
  # isn't nullable, unlike lazygit's), so listing it again here would
  # just re-duplicate it (same pattern already fixed for
  # lsd/zoxide/fzf/bat/direnv in modules/core/default.nix - see its
  # comment for the general rule).
  #
  # `lazygit` and `gh` DO have real alien specs (owned by
  # tui-apps.cachyos-packages.nix and cloud-tools.cachyos-packages.nix
  # respectively, since those suites also offer their own toggle for the
  # same tool) - routing them through `mkAppSet` here (rather than a
  # plain, non-alien-aware package list, as this file did before) makes
  # this suite correctly avoid re-installing them via Nix whenever
  # `suites.tui-apps.lazygit`/`suites.cloud-tools.github` already have
  # them alien-managed, instead of silently double/triple-installing the
  # same tool via pacman *and* two independent Nix code paths (a real,
  # confirmed-live bug on chromaden before this fix).
  #
  # `jj`/`jjui`: nixpkgs' `pkgs.jj` attribute is NOT Jujutsu
  # (https://github.com/jj-vcs/jj, the "Git alternative" this option's
  # description refers to) - it's `tidwall/jj`, an unrelated JSON Stream
  # Editor that happens to share the same short attribute name. The
  # actual Jujutsu VCS lives under `pkgs.jujutsu` (its `meta.mainProgram`
  # is still `jj`, so the CLI command stays exactly what users expect -
  # only the *nixpkgs attribute name* was wrong here, confirmed via
  # `nix eval .#homeConfigurations.default.pkgs.{jj,jujutsu}.meta.{description,homepage}`).
  # `pkgs.jjui` (a separate, correctly-named package - "TUI for Jujutsu
  # VCS", idursun/jjui) was never affected by this mixup and depends on
  # the real `jj` binary from `pkgs.jujutsu` at runtime, same as before.
  appSet = coreLib.mkAppSet {
    inherit alien;
    apps = {
      jj = { enable = cfg.jj; pkg = pkgs.jujutsu; };
      jjui = { enable = cfg.jj; pkg = pkgs.jjui; };
      lazygit = { enable = cfg.lazygit; pkg = pkgs.lazygit; };
      gh = { enable = cfg.gh; pkg = pkgs.gh; };
      gh-dash = { enable = cfg.gh-dash; pkg = pkgs.gh-dash; };
      gitCredentialManager = { enable = cfg.gitCredentialManager; pkg = pkgs.git-credential-manager; alienName = "git-credential-manager"; };
    };
  };
in
{
  options.suites.git-tools = {
    enable = coreLib.mkDefaultEnabledOption "Enable Git tools";

    # Core
    git = coreLib.mkDefaultEnabledOption "Git";
    jj = coreLib.mkDefaultEnabledOption "jj (Git alternative)";
    
    # Tools
    delta = coreLib.mkDefaultEnabledOption "delta (Git pager)";
    lazygit = coreLib.mkDefaultEnabledOption "lazygit (TUI Git client)";
    gh = coreLib.mkDefaultEnabledOption "gh (GitHub CLI)";
    gh-dash = coreLib.mkDefaultEnabledOption "gh-dash (GitHub dashboard)";
    gitCredentialManager = coreLib.mkDefaultDisabledOption "Git Credential Manager";
  };

  config = lib.mkIf cfg.enable {
    home.packages = appSet.packages;
    alienPackages.enabledPackages = appSet.alienEnabled
      ++ lib.optional cfg.git "git";

    # `git` itself is deliberately NOT routed through `appSet`/`mkAppSet`
    # (unlike lazygit/gh/gh-dash above) - it needs real HM-level config
    # below (`programs.git.settings`/`signing`/`alias`), so it must stay
    # a `programs.git` block, not a plain package. `programs.git.package`
    # (confirmed `nullOr package` via `nix eval .#homeConfigurations.
    # default.options.programs.git.package.type.name`) is nullable
    # exactly for this alien-managed case: home-manager only adds the
    # package to `home.packages` when it's non-null, so on distros with a
    # real `git` alien spec (Azure Linux 3/4 - see
    # git-tools.azurelinux{3,4}-packages.nix) `alien.mkEntry` yields
    # `null` here and native tdnf/dnf5 `git` is used instead, while the
    # `programs.git` config (user.name/email, delta integration, etc.)
    # still applies either way.
    programs.git = lib.mkIf cfg.git {
      enable = true;
      package = alien.mkEntry cfg.git "git" pkgs.git;
      signing.format = null;
      settings = {
        user = {
          name = dotsLocal.realname;
          email = dotsLocal.realmail;
        };
        # `git difft` runs a one-off diff through difftastic's structural
        # diff instead of the normal unified diff - scoped to this alias
        # only (via `-c diff.external=difft`) rather than setting
        # `diff.external` globally, so it doesn't interfere with delta's
        # pager integration (programs.delta.enableGitIntegration below),
        # which expects to receive plain unified-diff output. difftastic
        # itself (the `difft` binary) is installed unconditionally in
        # modules/core/default.nix.
        alias = {
          difft = "-c diff.external=difft diff";
        };
      };
    };

    programs.delta = lib.mkIf cfg.delta {
      enable = true;
      enableGitIntegration = true;
      options = {
        navigate = true;
        line-numbers = true;
        side-by-side = true;
      };
    };
  };
}
