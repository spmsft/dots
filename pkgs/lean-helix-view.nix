{ lib, rustPlatform, fetchFromGitHub }:

# Terminal-native Lean 4 infoview for Helix: an LSP proxy (transparently
# forwards to `lake serve` while watching cursor-position requests) plus
# a ratatui goal/diagnostics viewer meant to run in a separate tmux/
# zellij pane. Not packaged in nixpkgs upstream. See
# https://github.com/wyattgill9/lean-helix-view for usage - point
# `~/.config/helix/languages.toml`'s `language-server.lean` at this
# binary (`lean-helix-view proxy -- lake serve`) and run
# `lean-helix-view` itself in a side pane from the Lean project root.
rustPlatform.buildRustPackage rec {
  pname = "lean-helix-view";
  version = "unstable-2026-08-16";

  src = fetchFromGitHub {
    owner = "wyattgill9";
    repo = "lean-helix-view";
    rev = "6f86a4610075f81beec0d69b101ba584a392f2fa";
    hash = "sha256-DMxXYxIXsKnPIDtBGmWZ1/t8UQltiDu0wt+6jRoZoq4=";
  };

  cargoLock = {
    lockFile = "${src}/Cargo.lock";
    outputHashes = {
      "tree-sitter-lean-0.2.0" = "sha256-y7KpMnnv8NuUXC9EiqwwflDHMYwXtR0voLfDpdN7614=";
    };
  };

  # lean-helix-view is the workspace's user-facing binary crate
  # (crates/lean-helix-view) - lhv-lsp/lhv-wire/lhv-proxy/lhv-viewer are
  # internal library crates with no separate bin of their own.
  # Its own test suite spawns child processes and writes rolling logs to
  # $HOME - both unavailable/read-only in the Nix build sandbox, causing
  # unrelated failures there; the binary itself builds and runs fine.
  doCheck = false;

  cargoBuildFlags = [ "--package" "lean-helix-view" ];

  meta = {
    description = "Terminal-native Lean 4 infoview for Helix (LSP proxy + ratatui viewer)";
    homepage = "https://github.com/wyattgill9/lean-helix-view";
    license = lib.licenses.mit;
    mainProgram = "lean-helix-view";
    platforms = lib.platforms.unix;
  };
}
