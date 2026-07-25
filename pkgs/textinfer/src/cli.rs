use clap::{Parser, ValueEnum};
use std::path::PathBuf;

#[derive(Debug, Clone, Copy, ValueEnum, PartialEq, Eq)]
pub enum OutputFormat {
    Markdown,
    Json,
}

/// textinfer - CPU-bound local text summarization/paraphrasing/translation
/// via mistralrs (in-process, no server). Reads one or more files, or
/// stdin when none are given, and processes each independently.
#[derive(Debug, Parser)]
#[command(name = "textinfer", version, about)]
pub struct Args {
    /// Input files to process. When omitted, reads a single job from stdin.
    pub files: Vec<PathBuf>,

    /// Summarize the input (primary mode; mutually exclusive with --paraphrase/--passthrough).
    #[arg(long)]
    pub summarize: bool,

    /// Paraphrase the input (primary mode; mutually exclusive with --summarize/--passthrough).
    #[arg(long)]
    pub paraphrase: bool,

    /// Pass the input through with its content and meaning unchanged
    /// (primary mode; mutually exclusive with --summarize/--paraphrase).
    /// This is what happens if no primary mode is given at all - stating
    /// it explicitly documents intent and is required when combining
    /// with --prompt's mutual-exclusivity check. Still combinable with
    /// --sanitize/--translate/--title/--subtitle, same as the other
    /// primary modes.
    #[arg(long)]
    pub passthrough: bool,

    /// Fix spelling/grammar. Combinable with any primary mode.
    #[arg(long)]
    pub sanitize: bool,

    /// Translate the result. Requires --lang.
    #[arg(long)]
    pub translate: bool,

    /// Target language code for --translate, e.g. "de", "en".
    #[arg(long)]
    pub lang: Option<String>,

    /// Also generate a title.
    #[arg(long)]
    pub title: bool,

    /// Also generate a subtitle.
    #[arg(long)]
    pub subtitle: bool,

    /// Target output size for --summarize: a percentage of the original
    /// ("30%" = keep 30%, "-70%" = cut 70%, same result) or an absolute
    /// size ("2kb", "500b", "1mb"). A steering hint only - the model uses
    /// its own judgement on how to actually shape the result.
    #[arg(long)]
    pub size: Option<String>,

    /// Fully custom instruction, sent as a second system message after
    /// the persona (--system) and before the input content. Mutually
    /// exclusive with --summarize/--paraphrase/--passthrough/--sanitize/
    /// --translate/--title/--subtitle/--size - use this for full manual
    /// control over what the model is asked to do instead of those.
    #[arg(long)]
    pub prompt: Option<String>,

    /// Hard cap on generated tokens per input. Without this the model
    /// has no stopping signal beyond its own end-of-text token, so a
    /// confused or degenerate response (e.g. a trivial one-word input)
    /// can ramble for thousands of tokens - minutes on a CPU - before
    /// ever finishing. Defaults to an automatic estimate scaled to each
    /// input's own size and the requested operation (see
    /// `prompt::effective_max_tokens`) rather than one flat number that
    /// would be wildly wrong for either a one-line input or a full
    /// document; set this to override that estimate for every input.
    #[arg(long)]
    pub max_tokens: Option<usize>,

    /// Print the exact prompt/messages that would be sent to the model
    /// for each input, then exit without loading the model or running
    /// any inference.
    #[arg(long)]
    pub dry_run: bool,

    /// Ensure the target model(s) are downloaded to the local model
    /// cache, then exit - a deliberate one-off setup step. Downloads the
    /// model given by --model/--quick/--tiny, or every model in the
    /// registry if none is given. Normal inference runs never touch the
    /// network themselves; they fail fast with a hint to run this first
    /// if a model isn't cached yet.
    #[arg(long)]
    pub fetch: bool,

    /// Use the registry's "quick" model (see --list-models) instead of
    /// the default. Mutually exclusive with --model/--tiny.
    #[arg(long)]
    pub quick: bool,

    /// Use the registry's "tiny" model (see --list-models) - a small,
    /// low-quality model kept around for fast smoke-testing, not for
    /// real output. Mutually exclusive with --model/--quick.
    #[arg(long)]
    pub tiny: bool,

    /// Custom persona/style guide, e.g. "You are a terse technical editor
    /// writing in formal German by default." Replaces the default generic
    /// persona sentence; the required JSON output contract is unaffected.
    #[arg(long)]
    pub system: Option<String>,

    /// Output format for results.
    #[arg(long, value_enum, default_value_t = OutputFormat::Markdown)]
    pub format: OutputFormat,

    /// Write result output only to this file instead of stdout. Timing
    /// diagnostics, warnings, and errors always go to stderr regardless
    /// of this flag - this file receives exactly the result content
    /// (or, with --dry-run, exactly the printed prompt/messages), never
    /// mixed with any other output.
    #[arg(short = 'o', long)]
    pub output: Option<PathBuf>,

    /// Model name from the registry (see `textinfer --list-models`).
    /// Defaults to the registry's configured default model.
    #[arg(long)]
    pub model: Option<String>,

    /// Print the known models from the registry and exit.
    #[arg(long)]
    pub list_models: bool,

    /// Number of worker processes. Defaults to the registry/env-configured
    /// value, falling back to 2.
    #[arg(long)]
    pub workers: Option<usize>,

    /// CPU cores per worker. Defaults to the registry/env-configured
    /// value, falling back to the number of physical cores (SMT sibling
    /// threads deduped) on a single CCD/die, or 4 if that can't be
    /// determined - pinning a worker to more logical threads than
    /// physical cores per die just oversubscribes the same cores via SMT
    /// with no throughput gain.
    #[arg(long)]
    pub cores_per_worker: Option<usize>,

    /// Path to the JSON model registry file. Defaults to
    /// $TEXTINFER_MODELS_CONFIG, which the Nix module sets.
    #[arg(long)]
    pub models_config: Option<PathBuf>,

    /// Directory used as the Hugging Face model cache. Defaults to
    /// $TEXTINFER_MODELS_DIR, which the Nix module sets to
    /// $HOME/.local/share/textinfer/models.
    #[arg(long)]
    pub models_dir: Option<PathBuf>,

    /// Internal: run as a pinned worker subprocess reading JSONL jobs from
    /// stdin. Not intended for direct use.
    #[arg(long, hide = true)]
    pub worker_internal: Option<usize>,

    /// Internal: comma-separated CPU core ids this worker should pin to.
    #[arg(long, hide = true)]
    pub worker_cores: Option<String>,
}
