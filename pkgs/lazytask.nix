# Not in nixpkgs (checked as of 2026-07 - no `lazytask` attribute) and no
# AUR package exists either (checked via the AUR RPC search API), so no
# alien package spec is possible on any distro - built from source here
# instead (explicitly NOT a prebuilt-binary-tarball fetch, unlike e.g.
# ./quarkdown.nix - source build was specifically requested). Cargo.lock
# pins `taskchampion` (and its own transitive deps, including
# `libsqlite3-sys` with its bundled/vendored sqlite3 C source) entirely
# from crates.io - no git dependencies - so a plain buildRustPackage
# vendor works with no extra native build inputs.
#
# `patches`: upstream v0.1.0 has no way to pre-configure TaskChampion
# sync at startup - sync settings are entered by hand every session via
# the app's own Shift+S modal, and nothing reads env vars/CLI flags/
# config.toml for it (verified directly against upstream's src/app.rs,
# src/taskchampion.rs, src/config.rs, src/main.rs - see
# memory-bank/decisions.md's dated entry for the full trail). Rather
# than fork the whole tool, ./patches/lazytask-env-sync.patch adds a
# single ~15-line, purely-additive opt-in hook in `App::new()`: if
# LAZYTASK_SYNC_SERVER_URL/_CLIENT_ID/_ENCRYPTION_SECRET are all set, it
# calls the already-existing (upstream, unmodified) `configure_sync()`
# with them before the event loop starts - the exact same call the
# Shift+S modal itself makes, just triggered automatically. Silently a
# no-op if any var is unset or configure_sync rejects the values (e.g. a
# malformed client id) - never panics/exits, never logs the secret.
# modules/suites/pim-apps.nix's lazytask launcher wrapper sets these
# three vars from dotsLocal.taskSync when it wraps this package.
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

  patches = [ ./patches/lazytask-env-sync.patch ];

  cargoHash = "sha256-kgtZc1+Bmmdbv9seYTpXafZIfvqi886VyjgbP9ocTIc=";


  meta = {
    description = "Modern terminal UI for TaskChampion (Taskwarrior-compatible task storage), inspired by lazygit";
    homepage = "https://github.com/OsamaMahmood/lazytask";
    license = lib.licenses.mit;
    mainProgram = "lazytask";
    platforms = [ "x86_64-linux" ];
  };
}
