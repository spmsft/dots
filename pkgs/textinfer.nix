# First-party tool (see textinfer/ for the Rust source, developed and
# vendored directly in this repo - unlike ./lazytask.nix/./quarkdown.nix
# there is no upstream to fetch from). CPU-only in-process CLI built on
# `mistralrs`/`candle`; RUSTFLAGS are intentionally NOT hardcoded here -
# they're supplied by the package-tuning system (see
# modules/flake/package-tuning.nix + ./textinfer.tune-specs.nix +
# flake.nix's tunePackagesByContext) so the same "always tuned" mechanism
# used for other from-source packages (e.g. niri, noctalia-qs) applies
# here too, instead of a one-off bespoke RUSTFLAGS setting.
#
# `aws-lc-sys` (pulled in transitively via hf-hub's `ureq` -> rustls TLS
# stack) needs `cmake` at build time to build its vendored crypto C
# sources - verified via Cargo.lock (`aws-lc-sys` depends on `cc` +
# `cmake`).
{ lib, rustPlatform, cmake, perl }:

rustPlatform.buildRustPackage {
  pname = "textinfer";
  version = "0.1.0";

  src = ./textinfer;

  cargoLock.lockFile = ./textinfer/Cargo.lock;

  nativeBuildInputs = [ cmake perl ];

  # No test suite yet (all validation so far has been manual, real-model
  # runs - not something that can run in the Nix sandbox anyway, since it
  # needs a downloaded GGUF file and real CPU inference time).
  doCheck = false;

  meta = {
    description = "CPU-only, in-process text summarization/paraphrase/translation CLI built on mistralrs/candle";
    mainProgram = "textinfer";
    platforms = [ "x86_64-linux" ];
  };
}
