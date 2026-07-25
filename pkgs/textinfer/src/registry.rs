use anyhow::{bail, Result};
use serde::Deserialize;
use std::collections::HashMap;
use std::path::Path;

/// One entry in the model registry - mirrors the Nix-rendered JSON that
/// `suites.ai-textinfer.models` produces (see modules/features/ai-textinfer.nix).
/// Kept intentionally minimal: mistralrs auto-detects architecture/chat
/// template from the GGUF file's own metadata, so no `arch` field is
/// needed here.
#[derive(Debug, Clone, Deserialize)]
pub struct ModelEntry {
    /// Hugging Face repo id, e.g. "microsoft/phi-4-gguf".
    pub repo_id: String,
    /// GGUF filename to fetch from that repo, e.g. "phi-4-Q4_K.gguf".
    /// Not currently a full path with tokenizer info - mistralrs derives
    /// the tokenizer directly from the GGUF file's own embedded vocab
    /// metadata (validated in the textinfer-mistralrs-proto scratch run),
    /// so no separate tokenizer.json / tokenizer_repo_id is needed.
    pub file: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct ModelsConfig {
    pub models: HashMap<String, ModelEntry>,
    pub default_model: String,
    /// Name of the model tagged as the fast/low-latency choice in the
    /// registry (e.g. "qwen2.5-7b"), selected via `--quick`. `None` if no
    /// model has been designated for that role.
    #[serde(default)]
    pub quick_model: Option<String>,
    /// Name of the model tagged as the tiny/smoke-test choice in the
    /// registry, selected via `--tiny`. `None` if no model has been
    /// designated for that role.
    #[serde(default)]
    pub tiny_model: Option<String>,
}

pub fn load(path: &Path) -> Result<ModelsConfig> {
    let text = std::fs::read_to_string(path).map_err(|e| {
        anyhow::anyhow!("failed to read models config at {}: {e}", path.display())
    })?;
    let cfg: ModelsConfig = serde_json::from_str(&text)
        .map_err(|e| anyhow::anyhow!("failed to parse models config at {}: {e}", path.display()))?;
    Ok(cfg)
}

pub fn resolve<'a>(cfg: &'a ModelsConfig, name: &str) -> Result<&'a ModelEntry> {
    match cfg.models.get(name) {
        Some(entry) => Ok(entry),
        None => {
            let known: Vec<&str> = cfg.models.keys().map(|s| s.as_str()).collect();
            bail!("unknown model '{name}' - known models: {}", known.join(", "))
        }
    }
}
