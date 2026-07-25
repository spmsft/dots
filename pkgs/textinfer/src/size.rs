use anyhow::{bail, Context, Result};
use serde::{Deserialize, Serialize};

/// A `--size` spec for `--summarize`: either a target percentage of the
/// original text's length, or an absolute target size in bytes.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum Size {
    /// Target length as a percentage of the original (1..=100).
    Percent(u32),
    /// Target length in bytes (used as an approximate char-count guide -
    /// LLMs can't hit an exact byte count, this is a steering hint only).
    Bytes(u64),
}

/// Parses a `--size` value in one of these forms:
/// - `"30%"`  - absolute target: keep ~30% of the original.
/// - `"-70%"` - relative reduction: cut 70%, i.e. also keep ~30%
///   (the two forms are equivalent ways to say the same thing - pick
///   whichever reads more naturally at the call site).
/// - `"2kb"`, `"500b"`, `"1mb"` (case-insensitive) - absolute target size.
pub fn parse(spec: &str) -> Result<Size> {
    let spec = spec.trim();

    if let Some(pct) = spec.strip_suffix('%') {
        let n: i64 = pct
            .trim()
            .parse()
            .with_context(|| format!("invalid --size percentage '{spec}'"))?;
        let keep = if n < 0 { 100 + n } else { n };
        if !(1..=100).contains(&keep) {
            bail!("--size percentage must resolve to 1-100% (got '{spec}' -> {keep}%)");
        }
        return Ok(Size::Percent(keep as u32));
    }

    let lower = spec.to_ascii_lowercase();
    let (num_part, multiplier) = if let Some(n) = lower.strip_suffix("kb") {
        (n, 1024u64)
    } else if let Some(n) = lower.strip_suffix("mb") {
        (n, 1024 * 1024)
    } else if let Some(n) = lower.strip_suffix("gb") {
        (n, 1024 * 1024 * 1024)
    } else if let Some(n) = lower.strip_suffix('b') {
        (n, 1)
    } else {
        bail!("invalid --size '{spec}' - expected a percentage (e.g. '30%', '-70%') or an absolute size (e.g. '2kb', '500b')");
    };

    let n: u64 = num_part
        .trim()
        .parse()
        .with_context(|| format!("invalid --size value '{spec}'"))?;
    Ok(Size::Bytes(n * multiplier))
}

/// Human-readable instruction fragment describing the target size, for
/// inclusion in the prompt sent to the model.
pub fn instruction(size: Size) -> String {
    match size {
        Size::Percent(p) => {
            format!("Target the summary length at approximately {p}% of the original text's length.")
        }
        Size::Bytes(b) => {
            format!("Target the summary length at approximately {b} characters.")
        }
    }
}
