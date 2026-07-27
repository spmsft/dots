# CPU-only, in-process text summarize/paraphrase/translate CLI, built
# from source in ./paratext (see pkgs/paratext.nix - registered as
# external.paratext since there's no upstream package for it). Enabled
# by default: this is a core CLI tool, not an opt-in extra, and its
# model download is a deliberate one-off action (`parat --fetch`),
# never triggered automatically here - see main.rs's fetch/load split
# (memory-bank/decisions.md has the full rationale).
{ config, lib, pkgs, ... }:

let
  coreLib = import ../core/lib.nix { inherit lib; };
  cfg = config.features.paratext;

  modelEntry = lib.types.submodule {
    options = {
      repo_id = lib.mkOption {
        type = lib.types.str;
        description = "Hugging Face repo id hosting the GGUF file.";
      };
      file = lib.mkOption {
        type = lib.types.str;
        description = "GGUF filename within the repo.";
      };
      tokenizer_repo_id = lib.mkOption {
        type = lib.types.str;
        description = ''
          Hugging Face repo id hosting a companion tokenizer.json (the
          original non-GGUF model repo, e.g. "microsoft/phi-4" for the
          "microsoft/phi-4-gguf" GGUF repo) - required since candle
          (unlike the earlier mistralrs backend) needs an explicit
          tokenizer.json rather than parsing the GGUF's own embedded
          vocab, and GGUF-only repos typically don't ship one.
        '';
      };
    };
  };

  modelsConfig = {
    default_model = cfg.defaultModel;
    quick_model = cfg.quickModel;
    tiny_model = cfg.tinyModel;
    models = cfg.models;
  };
in {
  options.features.paratext = {
    enable = coreLib.mkDefaultEnabledOption "paratext CLI (CPU-only in-process text summarize/paraphrase/translate tool)";

    defaultModel = lib.mkOption {
      type = lib.types.str;
      default = "phi-4";
      description = "Name (key into `models`) of the model used unless --model/--quick/--tiny is passed.";
    };

    quickModel = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "qwen2.5-7b";
      description = "Name (key into `models`) of the model used for --quick. Null disables --quick.";
    };

    tinyModel = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "tiny";
      description = ''
        Name (key into `models`) of the model used for --tiny - a small,
        low-quality model kept around for fast smoke-testing (does not
        produce good enough output for real use). Null disables --tiny.
      '';
    };

    models = lib.mkOption {
      type = lib.types.attrsOf modelEntry;
      default = {
        phi-4 = {
          repo_id = "microsoft/phi-4-gguf";
          file = "phi-4-Q4_K.gguf";
          tokenizer_repo_id = "microsoft/phi-4";
        };
        "qwen2.5-7b" = {
          repo_id = "bartowski/Qwen2.5-7B-Instruct-GGUF";
          file = "Qwen2.5-7B-Instruct-Q4_K_M.gguf";
          tokenizer_repo_id = "Qwen/Qwen2.5-7B-Instruct";
        };
        tiny = {
          repo_id = "TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF";
          file = "tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf";
          tokenizer_repo_id = "TinyLlama/TinyLlama-1.1B-Chat-v1.0";
        };
      };
      description = ''
        Model registry, rendered to ~/.config/paratext/models.json.
        Downloading is never automatic - run `parat --fetch` (or
        `parat --fetch --model <name>`) once per model.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Prefer the tune overlay's top-level `pkgs.paratext` (present only
    # when global-scope tuning is enabled for this profile/context - see
    # flake.nix's tunePackagesByContext + ./ai-paratext.tune-specs.nix),
    # falling back to the plain, untuned `pkgs.external.paratext`
    # otherwise. Same fallback convention as tune-support.nix/
    # package-tuning.nix use for external.* packages generally.
    home.packages = [ (pkgs.paratext or pkgs.external.paratext) ];

    home.file.".config/paratext/models.json".text = builtins.toJSON modelsConfig;
  };
}
