mod cli;
mod model;
mod prompt;
mod registry;
mod size;
mod topology;

// Enabling candle's/candle-nn's "mkl" Cargo feature only makes
// intel-mkl-src's build.rs run - it doesn't by itself force the linker
// to pull in MKL's native symbols. This `extern crate` is the documented
// way to make that actually happen (candle's own examples do the same).
#[cfg(feature = "mkl")]
extern crate intel_mkl_src;

// mimalloc as the global allocator: candle's tensor ops do a lot of
// small/medium heap churn (intermediate buffers per op), and glibc's
// default malloc is a known weak point there vs. mimalloc's
// thread-caching design - always on (no feature gate; it's a drop-in,
// platform-portable allocator swap, not a GPU/CPU-ISA-specific tradeoff
// like mkl/cuda).
#[global_allocator]
static GLOBAL: mimalloc::MiMalloc = mimalloc::MiMalloc;

use anyhow::{bail, Context, Result};
use indicatif::{ProgressBar, ProgressStyle};
use serde::{Deserialize, Serialize};
use std::io::{BufRead, IsTerminal, Read, Write};
use std::path::PathBuf;
use std::process::{Child, ChildStdin, ChildStdout, Command, Stdio};
use std::time::{Duration, Instant};

/// One unit of work: an input's text plus the operations requested for
/// it. Sent to worker subprocesses as a single JSON line on their stdin.
#[derive(Debug, Serialize, Deserialize)]
struct JobIn {
    id: usize,
    text: String,
    ops: prompt::Ops,
}

/// A worker's response to one `JobIn`, sent back as a single JSON line
/// on its stdout. `error` carries the raw model output / failure reason
/// so callers can see exactly what went wrong rather than a bare panic.
#[derive(Debug, Serialize, Deserialize)]
struct JobOut {
    id: usize,
    value: Option<serde_json::Value>,
    error: Option<String>,
}

/// One resolved input: where it came from (for error messages /
/// markdown headings) and its raw text.
struct Input {
    label: String,
    text: String,
}

fn models_config_path(args: &cli::Args) -> PathBuf {
    args.models_config.clone().unwrap_or_else(|| {
        std::env::var("PARATEXT_MODELS_CONFIG")
            .map(PathBuf::from)
            .unwrap_or_else(|_| {
                dirs_home().join(".config/paratext/models.json")
            })
    })
}

fn models_dir(args: &cli::Args) -> PathBuf {
    args.models_dir.clone().unwrap_or_else(|| {
        std::env::var("PARATEXT_MODELS_DIR")
            .map(PathBuf::from)
            .unwrap_or_else(|_| dirs_home().join(".local/share/paratext/models"))
    })
}

fn dirs_home() -> PathBuf {
    std::env::var("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("."))
}

fn resolved_workers_default() -> usize {
    std::env::var("PARATEXT_WORKERS")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(2)
}

fn resolved_cores_per_worker_default() -> usize {
    std::env::var("PARATEXT_CORES_PER_WORKER")
        .ok()
        .and_then(|s| s.parse().ok())
        .or_else(topology::physical_cores_per_die)
        .unwrap_or(4)
}

fn default_workers(args: &cli::Args) -> usize {
    args.workers.unwrap_or_else(resolved_workers_default)
}

fn default_cores_per_worker(args: &cli::Args) -> usize {
    args.cores_per_worker
        .unwrap_or_else(resolved_cores_per_worker_default)
}

fn ops_from_args(args: &cli::Args) -> Result<prompt::Ops> {
    if args.translate && args.lang.is_none() {
        bail!("--translate requires --lang=<code>");
    }
    if args.lang.is_some() && !args.translate {
        bail!("--lang has no effect without --translate (it was silently ignored before this check - pass --translate too)");
    }
    if args.quick && args.model.is_some() {
        bail!("--quick and --model are mutually exclusive");
    }
    if args.tiny && args.model.is_some() {
        bail!("--tiny and --model are mutually exclusive");
    }
    if args.quick && args.tiny {
        bail!("--quick and --tiny are mutually exclusive");
    }

    let size = match &args.size {
        Some(spec) => {
            if !args.summarize {
                bail!("--size only applies to --summarize");
            }
            Some(size::parse(spec)?)
        }
        None => None,
    };

    let ops = prompt::Ops {
        summarize: args.summarize,
        paraphrase: args.paraphrase,
        passthrough: args.passthrough,
        sanitize: !args.no_sanitize,
        translate_lang: if args.translate { args.lang.clone() } else { None },
        title: args.title,
        subtitle: args.subtitle,
        body: !args.no_body,
        size,
        custom_prompt: args.prompt.clone(),
        system: args.system.clone(),
        max_tokens: args.max_tokens,
    };
    ops.validate()?;
    Ok(ops)
}

/// Opens the destination for result output (or, with --dry-run, the
/// printed prompt/messages): `-o/--output <path>` if given, else stdout.
/// This is deliberately the *only* thing that ever writes to this
/// destination - timing diagnostics, warnings, and per-input errors
/// always go to stderr via eprintln! regardless, so `-o` output is never
/// polluted with anything but the actual result content.
fn open_output(args: &cli::Args) -> Result<Box<dyn Write>> {
    match &args.output {
        Some(path) => {
            let file = std::fs::File::create(path)
                .with_context(|| format!("failed to create output file '{}'", path.display()))?;
            Ok(Box::new(file))
        }
        None => Ok(Box::new(std::io::stdout())),
    }
}

fn gather_inputs(files: &[PathBuf]) -> Result<Vec<Input>> {
    if files.is_empty() {
        let mut text = String::new();
        std::io::stdin()
            .read_to_string(&mut text)
            .context("failed to read stdin")?;
        return Ok(vec![Input {
            label: "stdin".to_string(),
            text,
        }]);
    }

    files
        .iter()
        .map(|path| {
            let text = std::fs::read_to_string(path)
                .with_context(|| format!("failed to read {}", path.display()))?;
            Ok(Input {
                label: path.display().to_string(),
                text,
            })
        })
        .collect()
}

/// Renders the exact messages that would be sent to the model for one
/// job, for `--dry-run` - never touches the model itself.
fn render_dry_run(label: &str, ops: &prompt::Ops, text: &str) -> String {
    let mut out = format!("=== {label} ===\n");
    match prompt::plan(ops) {
        prompt::PromptPlan::Structured { system, .. } => {
            out.push_str("[system]\n");
            out.push_str(&system);
            out.push('\n');
        }
        prompt::PromptPlan::Custom { persona, custom } => {
            out.push_str("[system: persona]\n");
            out.push_str(&persona);
            out.push_str("\n\n[system: prompt]\n");
            out.push_str(&custom);
            out.push('\n');
        }
    }
    out.push_str("\n[user]\n");
    out.push_str(text);
    out.push('\n');
    out
}

/// Whether stderr is an interactive terminal - gates real progress bars
/// (indicatif) vs plain periodic `eprintln!` logging. Never gated on
/// stdout, since progress/diagnostics always go to stderr regardless of
/// `-o`/redirection of the result output itself.
fn stderr_is_tty() -> bool {
    std::io::stderr().is_terminal()
}

/// Runs one chat completion to completion, driving a stderr progress
/// spinner (tok/s) when stderr is a TTY, or periodic `eprintln!`
/// progress logs otherwise (never a bar in non-interactive contexts, per
/// user request - logging is sufficient there). Returns the generated
/// text once done.
fn generate(
    model: &mut model::LoadedModel,
    system: &[&str],
    user: &str,
    label: &str,
    max_tokens: usize,
) -> Result<String> {
    let interactive = stderr_is_tty();
    let gen_start = Instant::now();
    let pb = if interactive {
        let pb = ProgressBar::new_spinner();
        pb.set_style(
            ProgressStyle::with_template("{spinner} parat: {msg}")
                .unwrap_or_else(|_| ProgressStyle::default_spinner()),
        );
        pb.enable_steady_tick(Duration::from_millis(100));
        Some(pb)
    } else {
        None
    };

    let mut tokens: usize = 0;
    let mut last_log = Instant::now();

    let result = model.generate(system, user, max_tokens, |_chunk| {
        tokens += 1;
        let elapsed = gen_start.elapsed().as_secs_f32().max(0.001);
        let tok_s = tokens as f32 / elapsed;
        if let Some(pb) = &pb {
            pb.set_message(format!("{label}: {tokens} tok, {tok_s:.1} tok/s"));
        } else if last_log.elapsed() >= Duration::from_secs(2) {
            eprintln!("parat: [progress] {label}: {tokens} tok, {tok_s:.1} tok/s");
            last_log = Instant::now();
        }
    });

    if let Some(pb) = pb {
        pb.finish_and_clear();
    }

    let text = result.context("inference request failed")?;
    let elapsed = gen_start.elapsed().as_secs_f32();
    let tok_s = tokens as f32 / elapsed.max(0.001);
    eprintln!("parat: [timing] generation took {elapsed:.2}s ({tokens} tokens, {tok_s:.1} tok/s)");

    Ok(text)
}

/// Runs one job against an already-loaded model: builds the prompt,
/// runs generation, and (for the structured/non---prompt path) leniently
/// parses+validates the JSON response. Shared by both the
/// single-process path and each worker.
fn run_job(model: &mut model::LoadedModel, ops: &prompt::Ops, text: &str) -> Result<serde_json::Value> {
    let max_tokens = prompt::effective_max_tokens(ops, text);
    match prompt::plan(ops) {
        prompt::PromptPlan::Custom { persona, custom } => {
            let raw = generate(model, &[&persona, &custom], text, "generating", max_tokens)?;
            Ok(serde_json::json!({ "body": raw.trim() }))
        }
        prompt::PromptPlan::Structured { system, keys } => {
            let raw = generate(model, &[&system], text, "generating", max_tokens)?;

            let value = prompt::extract_json_object(&raw)?;
            prompt::require_keys(&value, &keys, &raw)?;
            Ok(value)
        }
    }
}

/// Resolves which registry model name a run should use: --model wins,
/// then --quick/--tiny (mapped through the registry's quick_model/
/// tiny_model), else the registry's default_model.
fn resolve_model_name(args: &cli::Args, cfg: &registry::ModelsConfig) -> Result<String> {
    if let Some(model) = &args.model {
        Ok(model.clone())
    } else if args.quick {
        cfg.quick_model
            .clone()
            .context("no quick model configured in the registry (set quick_model)")
    } else if args.tiny {
        cfg.tiny_model
            .clone()
            .context("no tiny model configured in the registry (set tiny_model)")
    } else {
        Ok(cfg.default_model.clone())
    }
}

/// Looks up a model's GGUF file purely from the local hf-hub cache
/// layout (refs/snapshots under HF_HOME) - a plain filesystem read, no
/// network access whatsoever. Returns `None` if the model hasn't been
/// fetched yet (see `run_fetch`).
fn resolve_local_gguf(entry: &registry::ModelEntry) -> Option<PathBuf> {
    hf_hub::Cache::from_env()
        .model(entry.repo_id.clone())
        .get(&entry.file)
}

/// Same as `resolve_local_gguf` but for the companion `tokenizer.json`,
/// fetched from `tokenizer_repo_id` (see registry.rs's doc comment on
/// why this is a separate repo from the GGUF one).
fn resolve_local_tokenizer(entry: &registry::ModelEntry) -> Option<PathBuf> {
    hf_hub::Cache::from_env()
        .model(entry.tokenizer_repo_id.clone())
        .get("tokenizer.json")
}

/// Downloads (if not already cached) every requested model's GGUF file
/// and companion tokenizer.json via the network, one-off, so normal
/// inference runs never need to.
fn run_fetch(args: &cli::Args) -> Result<()> {
    std::env::set_var("HF_HOME", models_dir(args));
    let cfg = registry::load(&models_config_path(args))?;

    let targets: Vec<(String, registry::ModelEntry)> = if args.model.is_some() || args.quick || args.tiny {
        let name = resolve_model_name(args, &cfg)?;
        let entry = registry::resolve(&cfg, &name)?.clone();
        vec![(name, entry)]
    } else {
        cfg.models
            .iter()
            .map(|(name, entry)| (name.clone(), entry.clone()))
            .collect()
    };

    let api = hf_hub::api::sync::ApiBuilder::from_env()
        .build()
        .context("failed to build Hugging Face API client")?;

    for (name, entry) in targets {
        if let Some(path) = resolve_local_gguf(&entry) {
            println!("{name}: GGUF already cached at {}", path.display());
        } else {
            println!("{name}: downloading {}/{} ...", entry.repo_id, entry.file);
            let path = api
                .model(entry.repo_id.clone())
                .download(&entry.file)
                .with_context(|| format!("failed to download model '{name}'"))?;
            println!("{name}: fetched to {}", path.display());
        }

        if let Some(path) = resolve_local_tokenizer(&entry) {
            println!("{name}: tokenizer already cached at {}", path.display());
        } else {
            println!(
                "{name}: downloading tokenizer from {} ...",
                entry.tokenizer_repo_id
            );
            let path = api
                .model(entry.tokenizer_repo_id.clone())
                .download("tokenizer.json")
                .with_context(|| format!("failed to download tokenizer for model '{name}'"))?;
            println!("{name}: tokenizer fetched to {}", path.display());
        }
    }

    Ok(())
}

fn load_model(args: &cli::Args) -> Result<model::LoadedModel> {
    let load_start = std::time::Instant::now();
    std::env::set_var("HF_HOME", models_dir(args));
    let cfg = registry::load(&models_config_path(args))?;
    let model_name = resolve_model_name(args, &cfg)?;
    let entry = registry::resolve(&cfg, &model_name)?;

    let gguf_path = resolve_local_gguf(entry).with_context(|| {
        format!(
            "model '{model_name}' is not downloaded yet - run `parat --fetch --model {model_name}` first"
        )
    })?;
    let tokenizer_path = resolve_local_tokenizer(entry).with_context(|| {
        format!(
            "tokenizer for model '{model_name}' is not downloaded yet - run `parat --fetch --model {model_name}` first"
        )
    })?;

    // candle doesn't expose incremental load-progress, so this is
    // necessarily an indeterminate spinner (elapsed-time only) rather
    // than a proportional bar - only shown when stderr is a TTY, else
    // the existing plain timing eprintln! below is the whole story.
    let pb = if stderr_is_tty() {
        let pb = ProgressBar::new_spinner();
        pb.set_style(
            ProgressStyle::with_template("{spinner} parat: loading model '{msg}'... {elapsed}")
                .unwrap_or_else(|_| ProgressStyle::default_spinner()),
        );
        pb.set_message(model_name.clone());
        pb.enable_steady_tick(Duration::from_millis(100));
        Some(pb)
    } else {
        eprintln!("parat: loading model '{model_name}'...");
        None
    };

    // Loading purely from local disk paths (no hf-hub repo-id lookups) -
    // no network/ETag checks on every invocation, which is what made
    // repo-id-based loading slow and inconsistent in earlier testing
    // (measured 30-90s here just for cache-freshness checks, even with
    // the model fully cached already).
    let model = model::LoadedModel::load(&gguf_path, &tokenizer_path)
        .with_context(|| format!("failed to load model '{model_name}'"))?;

    if let Some(pb) = pb {
        pb.finish_and_clear();
    }
    eprintln!("parat: [timing] model load took {:.2}s", load_start.elapsed().as_secs_f32());
    Ok(model)
}

/// Renders one job's result to the requested output format, writing it
/// to stdout. Markdown mode prints a heading per input (skipped when
/// there's only a single stdin job) followed by title/subtitle/body;
/// json mode prints one JSON object per input (an array when there are
/// multiple).
fn render_markdown(label: &str, multiple: bool, value: &serde_json::Value) -> String {
    let mut out = String::new();
    if multiple {
        out.push_str(&format!("# {label}\n\n"));
    }
    if let Some(title) = value.get("title").and_then(|v| v.as_str()) {
        out.push_str(&format!("## {title}\n\n"));
    }
    if let Some(subtitle) = value.get("subtitle").and_then(|v| v.as_str()) {
        out.push_str(&format!("*{subtitle}*\n\n"));
    }
    if let Some(body) = value.get("body").and_then(|v| v.as_str()) {
        out.push_str(body);
        out.push('\n');
    }
    out
}

/// Pins the calling process to `cores` and bounds rayon's (and MKL/
/// OpenMP's) internal thread pool to exactly that core count - shared by
/// both `run_worker` (the multi-worker subprocess path) and `main`'s
/// direct single-process path (the common case: a single file/stdin
/// job, where spawning worker subprocesses would be pure overhead - see
/// `main`'s `jobs.len() <= 1 || workers <= 1` branch). Without this,
/// candle's rayon-based gemm/quantized kernels default to one thread per
/// *visible* logical CPU regardless of any affinity mask, needlessly
/// oversubscribing/thrashing instead of respecting `--cores-per-worker`'s
/// "1 thread per physical core" design - previously only the subprocess
/// path applied this cap, so a single-job run (the overwhelmingly common
/// case) silently ignored `--cores-per-worker`/`--workers` entirely and
/// ran with an unbounded, un-pinned thread pool. Must be called before
/// `load_model` triggers any rayon-consuming candle op: rayon reads
/// `RAYON_NUM_THREADS` once, lazily, on first use of its global pool.
fn pin_and_cap_threads(cores: &[usize]) {
    if cores.is_empty() {
        return;
    }
    topology::pin_current_process(cores);
    let n = cores.len().to_string();
    std::env::set_var("RAYON_NUM_THREADS", &n);
    std::env::set_var("OMP_NUM_THREADS", &n);
    std::env::set_var("MKL_NUM_THREADS", &n);
    // Without these, MKL/OpenMP may dynamically scale the thread count
    // *down* under perceived contention (e.g. from sibling workers
    // pinned to other CCDs) - defeating the fixed-size cap above and
    // making generation latency unpredictable across concurrent workers.
    std::env::set_var("MKL_DYNAMIC", "FALSE");
    std::env::set_var("OMP_DYNAMIC", "FALSE");
}

fn run_worker(args: &cli::Args) -> Result<()> {
    if let Some(cores_str) = &args.worker_cores {
        let cores: Vec<usize> = cores_str
            .split(',')
            .filter_map(|s| s.trim().parse().ok())
            .collect();
        pin_and_cap_threads(&cores);
    }

    let mut model = load_model(args)?;

    let stdin = std::io::stdin();
    let mut stdout = std::io::stdout();
    for line in stdin.lock().lines() {
        let line = line.context("failed to read job from stdin")?;
        if line.trim().is_empty() {
            continue;
        }
        let job: JobIn = serde_json::from_str(&line).context("failed to parse job")?;
        let out = match run_job(&mut model, &job.ops, &job.text) {
            Ok(value) => JobOut {
                id: job.id,
                value: Some(value),
                error: None,
            },
            Err(e) => JobOut {
                id: job.id,
                value: None,
                error: Some(e.to_string()),
            },
        };
        writeln!(stdout, "{}", serde_json::to_string(&out)?)?;
        stdout.flush()?;
    }
    Ok(())
}

/// Spawns `core_groups.len()` copies of the current binary in worker
/// mode, one per pinned core group, forwarding the model/registry flags
/// so each worker loads the same model independently.
fn spawn_workers(args: &cli::Args, core_groups: &[Vec<usize>]) -> Result<Vec<Child>> {
    let exe = std::env::current_exe().context("failed to resolve current executable")?;
    core_groups
        .iter()
        .enumerate()
        .map(|(idx, cores)| {
            let mut cmd = Command::new(&exe);
            if let Some(model) = &args.model {
                cmd.arg("--model").arg(model);
            }
            if args.quick {
                cmd.arg("--quick");
            }
            if args.tiny {
                cmd.arg("--tiny");
            }
            cmd.arg("--models-config").arg(models_config_path(args));
            cmd.arg("--models-dir").arg(models_dir(args));
            cmd.arg("--worker-internal").arg(idx.to_string());
            let cores_str = cores
                .iter()
                .map(|c| c.to_string())
                .collect::<Vec<_>>()
                .join(",");
            cmd.arg("--worker-cores").arg(cores_str);
            cmd.stdin(Stdio::piped())
                .stdout(Stdio::piped())
                .stderr(Stdio::inherit());
            cmd.spawn().context("failed to spawn worker process")
        })
        .collect()
}

/// Round-robin distributes jobs across worker stdins on writer threads,
/// then round-robin reads results back off worker stdouts on reader
/// threads, and reassembles them in original job order.
fn run_dispatch(
    jobs: Vec<JobIn>,
    mut children: Vec<Child>,
) -> Result<Vec<JobOut>> {
    let n = children.len();
    let mut stdins: Vec<ChildStdin> = Vec::with_capacity(n);
    let mut stdouts: Vec<ChildStdout> = Vec::with_capacity(n);
    for child in &mut children {
        stdins.push(child.stdin.take().context("worker stdin missing")?);
        stdouts.push(child.stdout.take().context("worker stdout missing")?);
    }

    // Partition jobs round-robin across workers up front so each writer
    // thread knows exactly how many results to expect back.
    let mut buckets: Vec<Vec<JobIn>> = (0..n).map(|_| Vec::new()).collect();
    for (i, job) in jobs.into_iter().enumerate() {
        buckets[i % n].push(job);
    }

    let mut handles = Vec::with_capacity(n);
    for (mut stdin, bucket) in stdins.into_iter().zip(buckets.into_iter()) {
        handles.push(std::thread::spawn(move || -> Result<()> {
            for job in &bucket {
                writeln!(stdin, "{}", serde_json::to_string(job)?)?;
            }
            Ok(())
        }));
    }

    let mut reader_handles = Vec::with_capacity(n);
    for stdout in stdouts.into_iter() {
        reader_handles.push(std::thread::spawn(move || -> Result<Vec<JobOut>> {
            let mut results = Vec::new();
            for line in std::io::BufReader::new(stdout).lines() {
                let line = line?;
                if line.trim().is_empty() {
                    continue;
                }
                results.push(serde_json::from_str::<JobOut>(&line)?);
            }
            Ok(results)
        }));
    }

    for h in handles {
        h.join().map_err(|_| anyhow::anyhow!("writer thread panicked"))??;
    }

    // Workers exit (closing stdout) once their stdin is closed above and
    // they've drained all buffered lines - drop the (now-writer-less)
    // children's stdin by letting `children` go out of scope, then wait.
    let mut all_results = Vec::new();
    for h in reader_handles {
        let mut r = h
            .join()
            .map_err(|_| anyhow::anyhow!("reader thread panicked"))??;
        all_results.append(&mut r);
    }
    for mut child in children {
        let _ = child.wait();
    }

    all_results.sort_by_key(|r| r.id);
    Ok(all_results)
}

fn main() -> Result<()> {
    // clap's derive macro can't show a runtime-computed default in
    // `--help` (its `default_value_t` is a compile-time constant), but
    // the actual --workers/--cores-per-worker values users get when they
    // omit the flag depend on env vars and (for cores-per-worker) live
    // /sys topology - so resolve those the same way `default_workers`/
    // `default_cores_per_worker` do below and splice the concrete
    // numbers into each arg's help text before clap prints/parses
    // anything, instead of just describing the fallback chain in prose.
    use clap::{CommandFactory, FromArgMatches};
    let workers_default = resolved_workers_default();
    let cores_per_worker_default = resolved_cores_per_worker_default();
    let cmd = cli::Args::command()
        .mut_arg("workers", |a| {
            a.help(format!(
                "Number of worker processes. Defaults to the registry/env-\
                 configured value, falling back to 2. [current default: {workers_default}]"
            ))
        })
        .mut_arg("cores_per_worker", |a| {
            a.help(format!(
                "CPU cores per worker. Defaults to the registry/env-\
                 configured value, falling back to the number of physical \
                 cores (SMT sibling threads deduped) on a single NUMA node/\
                 die, or 4 if that can't be determined. \
                 [current default: {cores_per_worker_default}]"
            ))
        });
    let matches = cmd.get_matches();
    let args = cli::Args::from_arg_matches(&matches)?;


    if let Some(_worker_id) = args.worker_internal {
        return run_worker(&args);
    }

    if args.list_models {
        let cfg = registry::load(&models_config_path(&args))?;
        for (name, entry) in &cfg.models {
            let marker = if *name == cfg.default_model {
                " (default)"
            } else if cfg.quick_model.as_deref() == Some(name.as_str()) {
                " (quick)"
            } else if cfg.tiny_model.as_deref() == Some(name.as_str()) {
                " (tiny)"
            } else {
                ""
            };
            println!("{name}{marker}: {}/{}", entry.repo_id, entry.file);
        }
        return Ok(());
    }

    if args.fetch {
        return run_fetch(&args);
    }

    let ops = ops_from_args(&args)?;
    let inputs = gather_inputs(&args.files)?;
    let mut out = open_output(&args)?;

    if args.dry_run {
        for input in &inputs {
            write!(out, "{}", render_dry_run(&input.label, &ops, &input.text))?;
            writeln!(out)?;
        }
        return Ok(());
    }

    let jobs: Vec<JobIn> = inputs
        .iter()
        .enumerate()
        .map(|(id, input)| JobIn {
            id,
            text: input.text.clone(),
            ops: ops.clone(),
        })
        .collect();

    let workers = default_workers(&args).max(1);
    let cores_per_worker = default_cores_per_worker(&args).max(1);

    let results: Vec<JobOut> = if jobs.len() <= 1 || workers <= 1 {
        // Single-process path: avoid subprocess overhead entirely when
        // there's only one job (the common interactive case) or when the
        // user asked for a single worker. This is the overwhelmingly
        // common case (a single file/stdin input), so `--cores-per-worker`
        // must still take effect here - previously it was silently a
        // no-op whenever this branch was taken (i.e. almost always),
        // since only the multi-worker subprocess path ever pinned/capped
        // threads. Reuse the same NUMA/die-aware core selection the
        // multi-worker path uses (`topology::plan_workers`) for a single
        // "slot" of up to `cores_per_worker` cores.
        let core_group = topology::plan_workers(1, cores_per_worker)
            .into_iter()
            .next()
            .unwrap_or_default();
        pin_and_cap_threads(&core_group);
        let mut model = load_model(&args)?;
        let mut out = Vec::with_capacity(jobs.len());
        for job in &jobs {
            let out_item = match run_job(&mut model, &job.ops, &job.text) {
                Ok(value) => JobOut { id: job.id, value: Some(value), error: None },
                Err(e) => JobOut { id: job.id, value: None, error: Some(e.to_string()) },
            };
            out.push(out_item);
        }
        out
    } else {
        let core_groups = topology::plan_workers(workers, cores_per_worker);
        let children = spawn_workers(&args, &core_groups)?;
        run_dispatch(jobs, children)?
    };

    let multiple = results.len() > 1;
    match args.format {
        cli::OutputFormat::Markdown => {
            let mut had_error = false;
            for (input, result) in inputs.iter().zip(results.iter()) {
                match &result.value {
                    Some(value) => write!(out, "{}", render_markdown(&input.label, multiple, value))?,
                    None => {
                        had_error = true;
                        eprintln!(
                            "parat: {}: {}",
                            input.label,
                            result.error.as_deref().unwrap_or("unknown error")
                        );
                    }
                }
                if multiple {
                    writeln!(out)?;
                }
            }
            if had_error {
                std::process::exit(1);
            }
        }
        cli::OutputFormat::Json => {
            let mut had_error = false;
            let entries: Vec<serde_json::Value> = inputs
                .iter()
                .zip(results.iter())
                .map(|(input, result)| match &result.value {
                    Some(value) => {
                        let mut obj = value.clone();
                        if let Some(map) = obj.as_object_mut() {
                            map.insert("source".to_string(), serde_json::Value::String(input.label.clone()));
                        }
                        obj
                    }
                    None => {
                        had_error = true;
                        serde_json::json!({
                            "source": input.label,
                            "error": result.error.clone().unwrap_or_default(),
                        })
                    }
                })
                .collect();

            if multiple {
                writeln!(out, "{}", serde_json::to_string_pretty(&entries)?)?;
            } else if let Some(entry) = entries.into_iter().next() {
                writeln!(out, "{}", serde_json::to_string_pretty(&entry)?)?;
            }
            if had_error {
                std::process::exit(1);
            }
        }
    }

    Ok(())
}
