# First-party tool (see paratext/ for the Rust source, developed and
# vendored directly in this repo - unlike ./lazytask.nix/./quarkdown.nix
# there is no upstream to fetch from). CPU/GPU-capable in-process CLI
# built directly on `candle` (see memory-bank/decisions.md's dated entry
# on the mistralrs->candle rewrite for rationale - mistralrs pulled in
# ~500 transitive crates for server/agentic features this tool never
# used). RUSTFLAGS are intentionally NOT hardcoded here - they're
# supplied by the package-tuning system (see
# modules/flake/package-tuning.nix + ./ai-paratext.tune-specs.nix +
# flake.nix's tunePackagesByContext) so the same "always tuned" mechanism
# used for other from-source packages (e.g. niri, noctalia-qs) applies
# here too, instead of a one-off bespoke RUSTFLAGS setting.
#
# cmake/perl are kept as native build inputs for the `ring`/rustls TLS
# stack pulled in transitively via hf-hub's `ureq` feature - some of its
# vendored crypto/assembly build scripts can need either depending on
# platform/version.
{ lib, rustPlatform, cmake, perl
, cudaSupport ? false
, cudaComputeCap ? null
, cudaPackages ? null
, mklSupport ? false
, mkl ? null
}:

let
  # cuda is only ever wired on when flake.nix's externalOverlay sees
  # dotsLocal.gpu == "nvidia" (see rules.nix's existing gpu axis
  # convention) - "build only cuda when available" per user request.
  # cudaComputeCap must ALSO be set (from dotsLocal.machine.cudaComputeCap):
  # a Nix sandbox has no physical GPU to query at build time, so
  # candle-kernels' build.rs (via the `cudaforge` crate) needs the
  # target compute capability handed to it explicitly through the
  # CUDA_COMPUTE_CAP env var below - failing loudly here (rather than
  # silently building for whatever cudaforge would guess/default to) is
  # deliberate, to avoid ever shipping a cuda binary baked for the wrong
  # architecture.
  cudaEnabled =
    if cudaSupport && cudaComputeCap == null then
      throw "pkgs/paratext.nix: cudaSupport = true requires cudaComputeCap to be set (dotsLocal.machine.cudaComputeCap) - a Nix build sandbox has no GPU to auto-detect it from."
    else cudaSupport && cudaComputeCap != null;

  # mkl is CPU-only (no GPU dependency). It DOES now link and run
  # correctly, via two fixes (see memory-bank/decisions.md's mkl entry
  # for the full investigation):
  #  1. paratext/vendor/{candle-core,candle-nn,candle-transformers} - a
  #     detached, patched copy of candle 0.9.1 (see paratext/Cargo.toml's
  #     [patch.crates-io] + vendor/*/Cargo.toml headers) with
  #     intel-mkl-src switched from upstream's hardcoded static
  #     `mkl-static-lp64-iomp` (whose bundled 2020.1 redistribution is
  #     missing the `hgemm_` symbol candle-core's mkl path calls) to
  #     `mkl-dynamic-lp64-iomp`, which links against a real system MKL
  #     (this `mkl` arg, i.e. nixpkgs' `pkgs.mkl`) instead.
  #  2. `-Wl,--no-as-needed` (via NIX_LDFLAGS below): MKL's dynamic
  #     layered libraries (mkl_intel_lp64/mkl_intel_thread/mkl_core/
  #     iomp5) cross-reference each other via weak symbols resolved
  #     through the process's global symbol table at runtime, not
  #     `DT_NEEDED` chains - libmkl_intel_lp64.so itself declares no
  #     NEEDED entry for the other three. Without --no-as-needed, the
  #     default `--as-needed` linker behavior drops mkl_intel_thread/
  #     mkl_core/iomp5 from the final binary (nothing in our own code
  #     directly references their symbols - only mkl_intel_lp64's, which
  #     re-exports the Fortran gemm entry points), leaving those three
  #     libraries unresolved at runtime.
  mklEnabled = mklSupport;

  features = lib.optional cudaEnabled "cuda" ++ lib.optional mklEnabled "mkl";
in

rustPlatform.buildRustPackage {
  pname = "paratext";
  version = "0.1.0";

  src = ./paratext;

  cargoLock.lockFile = ./paratext/Cargo.lock;

  nativeBuildInputs = [ cmake perl ]
    ++ lib.optionals cudaEnabled [ cudaPackages.cuda_nvcc ];

  buildInputs = lib.optionals cudaEnabled [
    cudaPackages.cuda_cudart
    cudaPackages.cuda_cccl
  ] ++ lib.optionals mklEnabled [ mkl ];

  buildFeatures = features;

  env = lib.optionalAttrs cudaEnabled {
    CUDA_COMPUTE_CAP = cudaComputeCap;
  } // lib.optionalAttrs mklEnabled {
    MKLROOT = "${mkl}";
    # See mklEnabled's comment above (--no-as-needed rationale). Applies
    # only to this package's own build/link, not globally.
    NIX_LDFLAGS = "--no-as-needed";
  };

  # mkl is a plain runtime shared-library dependency (dynamic linking,
  # not a Nix-wrapped propagatedBuildInputs auto-rpath case since `mkl`
  # isn't in buildInputs' usual rpath-computation set the same way glibc
  # deps are) - postFixup adds its lib dir to the binary's rpath so
  # `parat` finds libmkl_*.so/libiomp5.so at runtime without requiring
  # callers to set LD_LIBRARY_PATH themselves.
  postFixup = lib.optionalString mklEnabled ''
    patchelf --add-rpath "${mkl}/lib" "$out/bin/parat"
  '';

  # No test suite yet (all validation so far has been manual, real-model
  # runs - not something that can run in the Nix sandbox anyway, since it
  # needs a downloaded GGUF file and real CPU/GPU inference time).
  doCheck = false;

  meta = {
    description = "Local text summarization/paraphrase/translation CLI built on candle (CPU, GPU-capable via the cuda feature)";
    mainProgram = "parat";
    platforms = [ "x86_64-linux" ];
  };
}

