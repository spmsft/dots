{ config, lib, pkgs, dotsLocal, ... }:

let
  coreLib = import ../core/lib.nix { inherit lib; };
  cfg = config.features.agent-instructions;

  # Shared, versioned base (this repo) + a private, personal addendum
  # (dots-local, see modules/local/schema.nix's agentInstructionsExtra) -
  # concatenated once and rendered out to every agentic coding tool's
  # expected global-instructions path. Mirrors the "one canonical
  # source, mirrored to N tool-specific filenames" approach used
  # elsewhere in this repo (e.g. clipboard's single backend resolution
  # feeding several command aliases).
  baseInstructions = builtins.readFile ./agent-instructions/base.md;

  renderedInstructions = baseInstructions
    + lib.optionalString (dotsLocal.agentInstructionsExtra != "") ''

      ## Personal addendum (dots-local)

      ${dotsLocal.agentInstructionsExtra}
    '';

in
{
  options.features.agent-instructions = {
    enable = coreLib.mkDefaultEnabledOption "Global instructions shared across every agentic coding tool (GitHub Copilot CLI, opencode, ...)";
  };

  config = lib.mkIf cfg.enable {
    # GitHub Copilot CLI's own documented global-instructions path.
    home.file.".copilot/copilot-instructions.md".text = renderedInstructions;

    # opencode's global AGENTS.md (falls back to ~/.claude/CLAUDE.md only
    # when this file is absent, so writing this one is sufficient for
    # opencode specifically).
    home.file.".config/opencode/AGENTS.md".text = renderedInstructions;

    # Also cover Claude Code / Gemini CLI's own global-instructions
    # conventions, in case either is ever manually installed on this
    # machine - low cost, keeps this feature's "every agentic tool"
    # promise honest without needing per-tool opt-in flags.
    home.file.".claude/CLAUDE.md".text = renderedInstructions;
    home.file.".gemini/GEMINI.md".text = renderedInstructions;
  };
}
