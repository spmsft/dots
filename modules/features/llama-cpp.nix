{ config, lib, pkgs, dotsLocal, ... }:

let
  coreLib = import ../core/lib.nix { inherit lib; };
  cfg = config.features.llama-cpp;

  # rules.nix only ever sets features.llama-cpp.enable = true when
  # dotsLocal.gpu == "nvidia", but this option can also be flipped on
  # manually (e.g. from a context module or dots-local extraModules) -
  # so cudaEnabled is derived independently here too, rather than
  # assumed. When false, the CUDA-specific cmake flags/env/alien
  # packages below are all skipped, leaving a CPU (+ Vulkan, which works
  # across vendors) build - this is what makes it safe to enable this
  # feature at all on a non-Nvidia machine.
  cudaEnabled = dotsLocal.gpu == "nvidia";

  # Properly shell-escaped cmake flags
  cmakeFlagsEscaped = lib.escapeShellArgs cfg.cmakeFlags;

  # setup-llama-cpp {install|remove|update} - "update" is the same build
  # logic as "install" but skips the exists-already prompt (always pulls +
  # rebuilds).
  setupCommand = pkgs.writeShellScriptBin "setup-llama-cpp" ''
    set -e

    source ${../core/scripts/common.sh}

    ACTION="''${1:-install}"

    INSTALL_DIR="$HOME/.local/share/llama-cpp-chromaden"
    BUILD_DIR="$INSTALL_DIR/build"

    usage() {
      echo "Usage: setup-llama-cpp [install|remove|update]"
      echo ""
      echo "  install  Clone+build if missing, prompt to rebuild if present (default)"
      echo "  update   Force pull latest + rebuild (no prompt)"
      echo "  remove   Remove the build and install directories"
    }

    do_build() {
      local force_rebuild="$1"
      mkdir -p "$INSTALL_DIR/bin"
      mkdir -p "$BUILD_DIR"

      cd "$BUILD_DIR"

      if [ -d "llama.cpp/.git" ]; then
        if [[ "$force_rebuild" -eq 1 ]]; then
          REPLY="y"
        elif [ -t 0 ]; then
          read -p "llama.cpp exists. Rebuild? (y/N) " -n 1 -r
          echo
        else
          log_warn "llama.cpp exists. Use 'setup-llama-cpp update' to force rebuild."
          exit 0
        fi

        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
          echo "Skipping build."
          exit 0
        fi
        log_info "Updating llama.cpp..."
        cd llama.cpp
        git pull origin master
        rm -rf build
      else
        log_info "Cloning llama.cpp (master branch)..."
        git clone --depth 1 --branch master https://github.com/ggml-org/llama.cpp.git
        cd llama.cpp
      fi

      log_info "Configuring with CMake..."
      ${lib.optionalString cudaEnabled ''
      export CUDA_HOME=/opt/cuda
      export PATH=$CUDA_HOME/bin:$PATH
      export CC=gcc-15
      export CXX=g++-15
      export CUDAHOSTCXX=/usr/bin/g++-15

      # Ensure nvcc doesn't pick up system gcc-16
      export NVCC_PREPEND_FLAGS="-ccbin /usr/bin/g++-15"
      ''}

      cmake -B build ${cmakeFlagsEscaped}

      log_info "Building (this will take 10-30 minutes)..."
      cmake --build build --config Release -j$(nproc)

      log_info "Installing..."
      rm -f "$INSTALL_DIR/bin"/llama-*
      cp build/bin/llama-* "$INSTALL_DIR/bin/"
      ln -sf llama-cli "$INSTALL_DIR/bin/llama"

      # Wrapper scripts for library paths
      for bin in "$INSTALL_DIR/bin"/llama-*; do
        if [ -f "$bin" ] && [ ! -L "$bin" ]; then
          mv "$bin" "$bin.wrapped"
          cat > "$bin" << EOF
#!/bin/bash
export LD_LIBRARY_PATH="${lib.optionalString cudaEnabled "/opt/cuda/lib64:"}/usr/lib:\$LD_LIBRARY_PATH"
exec "$bin.wrapped" "\$@"
EOF
          chmod +x "$bin"
        fi
      done

      date > "$INSTALL_DIR/.build-date"
      log_success "Build complete."
      echo "Ensure you set caps: sudo setcap 'cap_ipc_lock=+ep' $INSTALL_DIR/bin/llama-*.wrapped"
    }

    do_remove() {
      read -p "Remove build and install directories? (y/N) " -n 1 -r
      echo
      if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$INSTALL_DIR"
        log_success "Clean complete."
      fi
    }

    case "$ACTION" in
      install) do_build 0 ;;
      update) do_build 1 ;;
      remove) do_remove ;;
      --help|-h) usage ;;
      *) log_error "Unknown action: $ACTION"; usage; exit 1 ;;
    esac
  '';

in {
  options.features.llama-cpp = {
    enable = coreLib.mkDefaultDisabledOption "llama.cpp with Zen 5 optimization (CUDA/Blackwell added only when dotsLocal.gpu == \"nvidia\")";

    cmakeFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "-DCMAKE_BUILD_TYPE=Release"
        "-DBUILD_SHARED_LIBS=OFF"
        "-DLLAMA_BUILD_SERVER=ON"
        "-DLLAMA_OPENSSL=ON"
        "-DLLAMA_CURL=ON"
        "-DGGML_CUDA=${if cudaEnabled then "ON" else "OFF"}"
      ] ++ lib.optionals cudaEnabled [
        # "native" queries the actual GPU present via nvcc at build
        # time - safe here (unlike pkgs/paratext.nix's Nix-sandboxed
        # build, which has no GPU to query and must be told an explicit
        # dotsLocal.machine.cudaComputeCap) because this script runs
        # directly on the target machine, which has the real GPU
        # present when `setup-llama-cpp` is actually invoked.
        "-DCMAKE_CUDA_ARCHITECTURES=native"
        "-DGGML_CUDA_FA_ALL_QUANTS=ON"
      ] ++ [
        "-DGGML_CCACHE=OFF"
        "-DGGML_BLAS=OFF"
        "-DGGML_AVX=ON"
        "-DGGML_AVX_VNNI=ON"
        "-DGGML_FMA=ON"
        "-DGGML_F16C=ON"
        "-DGGML_BMI2=ON"
        "-DGGML_AVX2=ON"
        "-DGGML_AVX512=ON"
        "-DGGML_AVX512_VNNI=ON"
        "-DGGML_AVX512_BF16=ON"
        "-DGGML_AVX512_VBMI=ON"       # Added for Zen 5
        "-DGGML_LTO=ON"
        "-DGGML_NATIVE=OFF"
        "-DCMAKE_C_FLAGS='-march=znver5 -O3'"
        "-DCMAKE_CXX_FLAGS='-march=znver5 -O3'"
      ] ++ lib.optionals cudaEnabled [
        "-DCMAKE_CUDA_HOST_COMPILER=/usr/bin/g++-15"
        "-DCMAKE_CUDA_FLAGS='-Xcompiler=-march=znver5 -Xcompiler=-mtune=znver5'"
      ];
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ setupCommand pkgs.python313Packages.huggingface-hub ];

    home.sessionPath = [ 
      "${config.home.homeDirectory}/.local/bin"
      "$HOME/.local/share/llama-cpp-chromaden/bin"
    ];

    home.sessionVariables = {
      HF_HOME = "/opt/ai/hf_cache";
    } // lib.optionalAttrs cudaEnabled {
      CUDA_HOME = "/opt/cuda";
    };

    home.activation.setupAiDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD mkdir -p /opt/ai/hf_cache /opt/ai/models
    '';

    alienPackages.enabledPackages = [
      "vulkan-llama"
    ] ++ lib.optionals cudaEnabled [
      "cuda-llama"
      "gcc15"
      "gcc15-libs"
    ];

    programs.bash.initExtra = ''
      hf-get() {
        local REPO_ID="$1"
        local TARGET_DIR="/opt/ai/models/''${REPO_ID##*/}"
        echo "Downloading $REPO_ID to $TARGET_DIR..."
        hf download "$REPO_ID" --local-dir "$TARGET_DIR" "''${@:2}"
      }
    '';
  };
}
