# Not in nixpkgs (checked as of 2026-07 - no `lazytask` attribute) and no
# AUR package exists either (checked via the AUR RPC search API), so no
# alien package spec is possible on any distro - built from source here
# instead (explicitly NOT a prebuilt-binary-tarball fetch, unlike e.g.
# ./quarkdown.nix - source build was specifically requested). Cargo.lock
# pins `taskchampion` (and its own transitive deps, including
# `libsqlite3-sys` with its bundled/vendored sqlite3 C source) entirely
# from crates.io - no git dependencies - so a plain buildRustPackage
# vendor works with no extra native build inputs.
{ lib, rustPlatform, fetchFromGitHub }:

rustPlatform.buildRustPackage rec {
  pname = "lazytask";
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "OsamaMahmood";
    repo = "lazytask";
    rev = "v${version}";
    hash = "sha256-oY/FADDb0olkxFUuKyuCM5ZLc9sTRqPzry4zqki8fhI=";
  };

  cargoHash = "sha256-kgtZc1+Bmmdbv9seYTpXafZIfvqi886VyjgbP9ocTIc=";

  meta = {
    description = "Modern terminal UI for TaskChampion (Taskwarrior-compatible task storage), inspired by lazygit";
    homepage = "https://github.com/OsamaMahmood/lazytask";
    license = lib.licenses.mit;
    mainProgram = "lazytask";
    platforms = [ "x86_64-linux" ];
  };
}
