use crate::size::Size;
use anyhow::{bail, Result};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Mode {
    AsIs,
    Summarize,
    Paraphrase,
}

/// The set of operations requested for one job - constructed from CLI
/// flags in main.rs, or deserialized directly when a worker process
/// receives a job over its stdin pipe.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Ops {
    pub summarize: bool,
    pub paraphrase: bool,
    pub passthrough: bool,
    pub sanitize: bool,
    pub translate_lang: Option<String>,
    pub title: bool,
    pub subtitle: bool,
    /// Target output size for --summarize (see size::parse); ignored for
    /// other primary modes.
    pub size: Option<Size>,
    /// Fully custom instruction (--prompt), sent as a second system
    /// message after the persona. Mutually exclusive with every other
    /// operation field above (see `validate`) - when set, it fully
    /// replaces the structured JSON-schema prompt built by
    /// `build_system_prompt`/`plan`, so the model's raw response is used
    /// as-is instead of being parsed as JSON.
    pub custom_prompt: Option<String>,
    /// Optional `--system="..."` persona/style guide, e.g. "You are a
    /// terse technical editor writing in formal German by default." When
    /// set, this replaces the default generic persona sentence but the
    /// strict JSON-output contract that follows it is always kept intact
    /// (a custom --system can change tone/voice, not the output format).
    pub system: Option<String>,
}

impl Ops {
    pub fn validate(&self) -> Result<()> {
        let primary_count =
            [self.summarize, self.paraphrase, self.passthrough].iter().filter(|&&x| x).count();
        if primary_count > 1 {
            bail!(
                "--summarize/--paraphrase/--passthrough are mutually exclusive \
                 (pick at most one primary mode)"
            );
        }
        if self.custom_prompt.is_some()
            && (self.summarize
                || self.paraphrase
                || self.passthrough
                || self.sanitize
                || self.translate_lang.is_some()
                || self.title
                || self.subtitle
                || self.size.is_some())
        {
            bail!(
                "--prompt is mutually exclusive with --summarize/--paraphrase/--passthrough/\
                 --sanitize/--translate/--title/--subtitle/--size"
            );
        }
        Ok(())
    }

    fn mode(&self) -> Mode {
        if self.summarize {
            Mode::Summarize
        } else if self.paraphrase {
            Mode::Paraphrase
        } else {
            Mode::AsIs
        }
    }
}

/// What a job's prompt looks like once `--prompt`'s custom-instruction
/// escape hatch is taken into account. `Structured` is the normal
/// generated-JSON-schema path; `Custom` skips schema generation and
/// response parsing entirely - the model's raw text becomes the result
/// verbatim.
pub enum PromptPlan {
    Structured { system: String, keys: Vec<&'static str> },
    Custom { persona: String, custom: String },
}

pub fn plan(ops: &Ops) -> PromptPlan {
    match &ops.custom_prompt {
        Some(custom) => PromptPlan::Custom {
            persona: ops
                .system
                .clone()
                .unwrap_or_else(|| "You are a precise text-processing engine.".to_string()),
            custom: custom.clone(),
        },
        None => {
            let (system, keys) = build_system_prompt(ops);
            PromptPlan::Structured { system, keys }
        }
    }
}


/// Builds the single combined chat prompt for one job: a system message
/// describing exactly which JSON keys are expected and what each key
/// means, followed by the raw input text as the user message. Returning
/// only the requested keys (rather than always emitting all of
/// title/subtitle/body) keeps small-model output focused and keeps
/// prompts self-documenting for future maintainers.
pub fn build_system_prompt(ops: &Ops) -> (String, Vec<&'static str>) {
    let mut keys = vec!["body"];

    let mode_instruction = match ops.mode() {
        Mode::AsIs => "Keep the text's content and meaning unchanged.",
        Mode::Summarize => "Summarize the text concisely, capturing only the key points.",
        Mode::Paraphrase => {
            "Paraphrase the text: reword it while preserving its full meaning and roughly the same length."
        }
    };

    let mut instructions = vec![mode_instruction.to_string()];

    if let Some(size) = ops.size {
        instructions.push(crate::size::instruction(size));
    }

    if ops.sanitize {
        instructions.push("Additionally, correct any spelling and grammar mistakes.".to_string());
    }

    if let Some(lang) = &ops.translate_lang {
        instructions.push(format!(
            "Additionally, translate the resulting text into the language with code '{lang}'."
        ));
    }

    if ops.title {
        keys.push("title");
        instructions.push(
            "Also provide a concise, descriptive title for the text under the \"title\" key."
                .to_string(),
        );
    }

    if ops.subtitle {
        keys.push("subtitle");
        instructions.push(
            "Also provide a short subtitle/tagline for the text under the \"subtitle\" key."
                .to_string(),
        );
    }

    let keys_str = keys
        .iter()
        .map(|k| format!("\"{k}\""))
        .collect::<Vec<_>>()
        .join(", ");

    // The persona/style sentence is the only part a custom --system
    // guide replaces - everything about the required JSON output
    // contract below is always enforced regardless.
    let persona = ops
        .system
        .clone()
        .unwrap_or_else(|| "You are a precise text-processing engine.".to_string());

    let system = format!(
        "{persona} You will be given a body of \
         text. Follow the instructions below exactly and respond with ONLY a \
         single valid JSON object (no markdown code fences, no commentary) \
         containing exactly these keys: {keys_str}.\n\n\
         Instructions:\n- {instr}\n\n\
         The \"body\" key must always contain the resulting processed text \
         (after applying the instructions above), preserving the input's own \
         formatting conventions (e.g. Markdown headers/lists/code blocks, if \
         present).",
        instr = instructions.join("\n- ")
    );

    (system, keys)
}

/// Leniently extracts a JSON object from a model's raw text response:
/// strips ```json/``` code fences if the model wrapped its answer in
/// one anyway (small models do this often despite instructions), then
/// takes the first balanced `{...}` block found. Returns the raw text
/// on failure so the caller can surface it for debugging - we
/// deliberately never silently guess or drop a requested field.
pub fn extract_json_object(raw: &str) -> Result<serde_json::Value> {
    let trimmed = raw.trim();
    let candidate = trimmed
        .strip_prefix("```json")
        .or_else(|| trimmed.strip_prefix("```"))
        .unwrap_or(trimmed);
    let candidate = candidate.strip_suffix("```").unwrap_or(candidate).trim();

    let start = candidate.find('{').ok_or_else(|| {
        anyhow::anyhow!("model response did not contain a JSON object:\n{raw}")
    })?;

    let mut depth = 0i32;
    let mut end = None;
    for (i, c) in candidate[start..].char_indices() {
        match c {
            '{' => depth += 1,
            '}' => {
                depth -= 1;
                if depth == 0 {
                    end = Some(start + i + 1);
                    break;
                }
            }
            _ => {}
        }
    }
    let end = end.ok_or_else(|| {
        anyhow::anyhow!("model response had an unterminated JSON object:\n{raw}")
    })?;

    serde_json::from_str(&candidate[start..end])
        .map_err(|e| anyhow::anyhow!("failed to parse model JSON response ({e}):\n{raw}"))
}

/// Verifies every key requested in `keys` is present (and a string) in
/// `value`, failing loud (with the full raw response) rather than
/// silently omitting a field the caller asked for.
pub fn require_keys(value: &serde_json::Value, keys: &[&str], raw: &str) -> Result<()> {
    for key in keys {
        match value.get(*key) {
            Some(serde_json::Value::String(_)) => {}
            _ => bail!("model response is missing expected string field \"{key}\":\n{raw}"),
        }
    }
    Ok(())
}
