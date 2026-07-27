//! Candle-based GGUF inference engine - replaces the earlier mistralrs
//! backend. Kept deliberately small: we only need single-turn chat
//! completion for three architecture families (Llama/TinyLlama, Qwen2,
//! Phi3), not mistralrs' full server/agentic feature set (which pulled
//! in ~500 transitive crates we never used - MCP tool-calling, web
//! search, image/audio generation, an HTTP server stack, PagedAttention).
//!
//! Loading pattern (GGUF parsing, per-arch `ModelWeights::from_gguf`,
//! the sampling loop, and the streaming token decoder) mirrors candle's
//! own `candle-examples/examples/quantized{,-phi,-qwen2-instruct}`
//! reference examples.

use anyhow::{bail, Context, Result};
use candle_core::quantized::gguf_file;
use candle_core::{Device, Tensor};
use candle_transformers::generation::{LogitsProcessor, Sampling};
use candle_transformers::models::quantized_llama::ModelWeights as LlamaWeights;
use candle_transformers::models::quantized_phi3::ModelWeights as Phi3Weights;
use candle_transformers::models::quantized_qwen2::ModelWeights as Qwen2Weights;
use std::path::Path;
use tokenizers::Tokenizer;

/// Model architecture family, detected from the GGUF file's own
/// `general.architecture` metadata key (a standard llama.cpp-convention
/// key present in every GGUF file) - no per-model registry field needed.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Arch {
    Llama,
    Qwen2,
    Phi3,
}

impl Arch {
    fn detect(name: &str) -> Result<Self> {
        match name {
            // GGUF's own convention: TinyLlama/Llama/Mistral-family
            // conversions all report "llama" here regardless of the
            // specific model, since they share the same architecture.
            "llama" => Ok(Arch::Llama),
            "qwen2" => Ok(Arch::Qwen2),
            "phi3" => Ok(Arch::Phi3),
            other => bail!(
                "unsupported model architecture '{other}' (supported: llama, qwen2, phi3)"
            ),
        }
    }

    /// Renders one user turn into the chat-formatted prompt string this
    /// architecture's instruct-tuned checkpoints expect. Kept as a small
    /// per-arch match (mirroring candle's own examples) rather than
    /// parsing/rendering the GGUF's `tokenizer.chat_template` Jinja
    /// template - none of the architectures we support need anything
    /// more elaborate than a fixed wrapper around system+user text.
    fn format_prompt(&self, system: &[&str], user: &str) -> String {
        match self {
            Arch::Llama => {
                // TinyLlama-Chat's Zephyr-style template.
                let mut out = String::new();
                for s in system {
                    out.push_str(&format!("<|system|>\n{s}</s>\n"));
                }
                out.push_str(&format!("<|user|>\n{user}</s>\n<|assistant|>\n"));
                out
            }
            Arch::Qwen2 => {
                let mut out = String::new();
                for s in system {
                    out.push_str(&format!("<|im_start|>system\n{s}<|im_end|>\n"));
                }
                out.push_str(&format!(
                    "<|im_start|>user\n{user}<|im_end|>\n<|im_start|>assistant\n"
                ));
                out
            }
            Arch::Phi3 => {
                let mut out = String::new();
                for s in system {
                    out.push_str(&format!("<|system|>\n{s}<|end|>\n"));
                }
                out.push_str(&format!("<|user|>\n{user}<|end|>\n<|assistant|>\n"));
                out
            }
        }
    }

    /// The end-of-turn marker string for this architecture, looked up in
    /// the tokenizer's vocabulary to get its token id. Used only as a
    /// fallback when the GGUF file doesn't carry an explicit
    /// `tokenizer.ggml.eos_token_id` (rare, but not guaranteed).
    fn eos_marker(&self) -> &'static str {
        match self {
            Arch::Llama => "</s>",
            Arch::Qwen2 => "<|im_end|>",
            Arch::Phi3 => "<|end|>",
        }
    }
}

enum Weights {
    Llama(LlamaWeights),
    Qwen2(Qwen2Weights),
    Phi3(Phi3Weights),
}

impl Weights {
    fn forward(&mut self, x: &Tensor, index_pos: usize) -> candle_core::Result<Tensor> {
        match self {
            Weights::Llama(m) => m.forward(x, index_pos),
            Weights::Qwen2(m) => m.forward(x, index_pos),
            Weights::Phi3(m) => m.forward(x, index_pos),
        }
    }
}

/// A loaded model ready to run chat completions against. Not `Clone`/
/// `Send` across threads by design - each worker process (see
/// topology.rs/spawn_workers in main.rs) loads its own instance.
pub struct LoadedModel {
    weights: Weights,
    tokenizer: Tokenizer,
    arch: Arch,
    device: Device,
    eos_token_id: u32,
}

/// Picks the best available device: CUDA if this build was compiled
/// with the `cuda` Cargo feature and a GPU is present, else CPU. Same
/// approach as candle's own examples (`candle_examples::device`).
fn pick_device() -> Device {
    if candle_core::utils::cuda_is_available() {
        match Device::new_cuda(0) {
            Ok(d) => return d,
            Err(e) => eprintln!("parat: [warn] CUDA available but failed to init ({e}), falling back to CPU"),
        }
    }
    Device::Cpu
}

impl LoadedModel {
    /// Loads a GGUF model plus its companion `tokenizer.json` from local
    /// paths only (no network access - see main.rs's fetch/load split).
    pub fn load(gguf_path: &Path, tokenizer_path: &Path) -> Result<Self> {
        let device = pick_device();
        let mut file = std::fs::File::open(gguf_path)
            .with_context(|| format!("failed to open GGUF file {}", gguf_path.display()))?;
        let content = gguf_file::Content::read(&mut file)
            .map_err(|e| e.with_path(gguf_path.to_path_buf()))
            .context("failed to parse GGUF file")?;
        // Header/metadata parsing above is cheap (a few KB); the actual
        // weight bytes are loaded from a memory map below instead of via
        // `file`'s `Read` impl, so each tensor can be borrowed directly
        // from mapped pages (zero-copy on CPU) rather than copied twice
        // (once into a `Vec<u8>` off the file, again into the final
        // `Vec<T>`) - see `MmapSource`/`MmapedBlocks` in vendored
        // candle-core for the implementation.
        drop(file);
        // SAFETY: `gguf_path` is a local model file that parat does not
        // itself modify while loaded; this mirrors the same assumption
        // candle's own `MmapedSafetensors` makes for safetensors files.
        let mut source = unsafe { gguf_file::MmapSource::open(gguf_path) }
            .with_context(|| format!("failed to mmap GGUF file {}", gguf_path.display()))?;

        let arch_name = content
            .metadata
            .get("general.architecture")
            .and_then(|v| v.to_string().ok())
            .context("GGUF file has no 'general.architecture' metadata key")?;
        let arch = Arch::detect(arch_name)?;

        // Extract before `content` is consumed by `from_gguf` below -
        // standard llama.cpp-convention metadata key, authoritative for
        // this exact checkpoint (preferred over a hardcoded per-arch
        // marker string, used only as a fallback if absent).
        let eos_from_metadata = content
            .metadata
            .get("tokenizer.ggml.eos_token_id")
            .and_then(|v| v.to_u32().ok());

        let weights = match arch {
            Arch::Llama => Weights::Llama(
                LlamaWeights::from_gguf(content, &mut source, &device)
                    .context("failed to load llama-architecture weights from GGUF")?,
            ),
            Arch::Qwen2 => Weights::Qwen2(
                Qwen2Weights::from_gguf(content, &mut source, &device)
                    .context("failed to load qwen2-architecture weights from GGUF")?,
            ),
            Arch::Phi3 => Weights::Phi3(
                Phi3Weights::from_gguf(false, content, &mut source, &device)
                    .context("failed to load phi3-architecture weights from GGUF")?,
            ),
        };

        let tokenizer = Tokenizer::from_file(tokenizer_path).map_err(|e| {
            anyhow::anyhow!(
                "failed to load tokenizer from {}: {e}",
                tokenizer_path.display()
            )
        })?;

        // Prefer the GGUF's own explicit EOS token id over a hardcoded
        // per-arch marker string, since it's authoritative for this
        // exact checkpoint rather than a guess based on architecture
        // family alone.
        let eos_token_id = eos_from_metadata
            .or_else(|| tokenizer.get_vocab(true).get(arch.eos_marker()).copied())
            .with_context(|| {
                format!("could not determine an end-of-turn token id for architecture {arch:?}")
            })?;

        Ok(Self {
            weights,
            tokenizer,
            arch,
            device,
            eos_token_id,
        })
    }

    /// Runs one chat completion: renders `system`+`user` through this
    /// architecture's prompt format, then autoregressively samples up to
    /// `max_tokens`, invoking `on_token` with each newly decoded text
    /// fragment (for streaming/progress display) as it's produced.
    /// Greedy (temperature 0) decoding is used throughout - deterministic
    /// output for a text-processing tool with a strict JSON contract is
    /// preferable to sampling variance.
    pub fn generate(
        &mut self,
        system: &[&str],
        user: &str,
        max_tokens: usize,
        mut on_token: impl FnMut(&str),
    ) -> Result<String> {
        let prompt = self.arch.format_prompt(system, user);
        let encoding = self
            .tokenizer
            .encode(prompt, true)
            .map_err(|e| anyhow::anyhow!("failed to tokenize prompt: {e}"))?;
        let prompt_tokens = encoding.get_ids().to_vec();
        if prompt_tokens.is_empty() {
            bail!("tokenizer produced no tokens for the given input");
        }

        let mut logits_processor = LogitsProcessor::from_sampling(42, Sampling::ArgMax);
        let mut all_tokens: Vec<u32> = Vec::with_capacity(prompt_tokens.len() + max_tokens);

        // Stream-decoding state mirroring candle-examples'
        // TokenOutputStream: token-level decoding can produce partial
        // UTF-8/subword fragments, so we re-decode the tail window each
        // step and only emit the newly-stable suffix.
        let mut prev_index = 0usize;
        let mut current_index = 0usize;
        let emit_new_text = |tokenizer: &Tokenizer,
                                 all_tokens: &[u32],
                                 prev_index: &mut usize,
                                 current_index: &mut usize,
                                 on_token: &mut dyn FnMut(&str)| {
            let prev_text = if all_tokens.is_empty() {
                String::new()
            } else {
                tokenizer
                    .decode(&all_tokens[*prev_index..*current_index], true)
                    .unwrap_or_default()
            };
            let text = tokenizer
                .decode(&all_tokens[*prev_index..], true)
                .unwrap_or_default();
            if text.len() > prev_text.len() {
                let new_text = &text[prev_text.len()..];
                on_token(new_text);
                *prev_index = *current_index;
                *current_index = all_tokens.len();
            }
        };

        let input = Tensor::new(prompt_tokens.as_slice(), &self.device)?.unsqueeze(0)?;
        let logits = self.weights.forward(&input, 0)?;
        let logits = logits.squeeze(0)?;
        let mut next_token = logits_processor.sample(&logits)?;
        all_tokens.push(next_token);
        emit_new_text(
            &self.tokenizer,
            &all_tokens,
            &mut prev_index,
            &mut current_index,
            &mut on_token,
        );

        if next_token != self.eos_token_id {
            for index in 0..max_tokens.saturating_sub(1) {
                let input = Tensor::new(&[next_token], &self.device)?.unsqueeze(0)?;
                let logits = self
                    .weights
                    .forward(&input, prompt_tokens.len() + index + 1)?;
                let logits = logits.squeeze(0)?;
                next_token = logits_processor.sample(&logits)?;
                all_tokens.push(next_token);
                emit_new_text(
                    &self.tokenizer,
                    &all_tokens,
                    &mut prev_index,
                    &mut current_index,
                    &mut on_token,
                );
                if next_token == self.eos_token_id {
                    break;
                }
            }
        }

        // Final decode of the whole sequence gives us the exact text
        // (trailing partial fragments included) rather than relying on
        // the streamed pieces summing up perfectly.
        let decoded = self
            .tokenizer
            .decode(&all_tokens, true)
            .map_err(|e| anyhow::anyhow!("failed to decode generated tokens: {e}"))?;
        Ok(decoded)
    }
}
