{
  description = "Lean 4 project scaffolded via mk-lean";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in {
      # Only elan/git/uv are provided here - the actual Lean toolchain
      # itself is managed by elan via this project's own lean-toolchain
      # file (see mk-lean/update-lean's toolchain-sync logic), not by
      # Nix. This flake exists purely so anyone (even without dots'
      # home-manager setup) can `direnv allow`/`nix develop` and get a
      # working `lake`/`elan` and the Lean MCP launcher on PATH. `uv`
      # provides `uvx`, which `.github/mcp.json`/`opencode.json` use to
      # run `lean-lsp-mcp` without a separate install step.
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [ pkgs.elan pkgs.git pkgs.uv ];
        };
      });
    };
}
