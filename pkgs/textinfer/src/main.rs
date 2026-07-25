mod cli;
mod prompt;
mod registry;
mod size;
mod topology;

use anyhow::{bail, Context, Result};
use clap::Parser;
use mistralrs::{GgufModelBuilder, Model, TextMessageRole, TextMessages};
use serde::{Deserialize, Serialize};
use std::io::{BufRead, Read, Write};
use std::path::PathBuf;
use std::process::{Child, ChildStdin, ChildStdout, Command, Stdio};

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
        std::env::var("TEXTINFER_MODELS_CONFIG")
            .map(PathBuf::from)
            .unwrap_or_else(|_| {
                dirs_home().join(".config/textinfer/models.json")
            })
    })
}

fn models_dir(args: &cli::Args) -> PathBuf {
    args.models_dir.clone().unwrap_or_else(|| {
        std::env::var("TEXTINFER_MODELS_DIR")
            .map(PathBuf::from)
            .unwrap_or_else(|_| dirs_home().join(".local/share/textinfer/models"))
    })
}

fn dirs_home() -> PathBuf {
    std::env::var("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("."))
}

fn default_workers(args: &cli::Args) -> usize {
    args.workers
        .or_else(|| std::env::var("TEXTINFER_WORKERS").ok().and_then(|s| s.parse().ok()))
        .unwrap_or(2)
}

fn default_cores_per_worker(args: &cli::Args) -> usize {
    args.cores_per_worker
        .or_else(|| {
            std::env::var("TEXTINFER_CORES_PER_WORKER")
                .ok()
                .and_then(|s| s.parse().ok())
        })
        .unwrap_or(4)
}

fn ops_from_args(args: &cli::Args) -> Result<prompt::Ops> {
    if args.translate && args.lang.is_none() {
        bail!("--translate requires --lang=<code>");
    }
    if args.quick && args.model.is_some() {
        bail!("--quick and --model are mutually exclusive");
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
        sanitize: args.sanitize,
        translate_lang: if args.translate { args.lang.clone() } else { None },
        title: args.title,
        subtitle: args.subtitle,
        size,
        custom_prompt: args.prompt.clone(),
        system: args.system.clone(),
    };
    ops.validate()?;
    Ok(ops)
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

/// Runs one job against an already-loaded model: builds the prompt,
/// sends the chat request, and (for the structured/non---prompt path)
/// leniently parses+validates the JSON response. Shared by both the
/// single-process path and each worker.
async fn run_job(model: &Model, ops: &prompt::Ops, text: &str) -> Result<serde_json::Value> {
    match prompt::plan(ops) {
        prompt::PromptPlan::Custom { persona, custom } => {
            let messages = TextMessages::new()
                .add_message(TextMessageRole::System, persona)
                .add_message(TextMessageRole::System, custom)
                .add_message(TextMessageRole::User, text);
            let response = model
                .send_chat_request(messages)
                .await
                .context("inference request failed")?;
            let raw = response.choices[0]
                .message
                .content
                .clone()
                .unwrap_or_default();
            Ok(serde_json::json!({ "body": raw.trim() }))
        }
        prompt::PromptPlan::Structured { system, keys } => {
            let messages = TextMessages::new()
                .add_message(TextMessageRole::System, system)
                .add_message(TextMessageRole::User, text);

            let gen_start = std::time::Instant::now();
            let response = model
                .send_chat_request(messages)
                .await
                .context("inference request failed")?;
            eprintln!("textinfer: [timing] generation took {:.2}s", gen_start.elapsed().as_secs_f32());

            let raw = response.choices[0]
                .message
                .content
                .clone()
                .unwrap_or_default();

            let value = prompt::extract_json_object(&raw)?;
            prompt::require_keys(&value, &keys, &raw)?;
            Ok(value)
        }
    }
}

/// Resolves which registry model name a run should use: --model wins,
/// then --quick (mapped through the registry's quick_model), else the
/// registry's default_model.
fn resolve_model_name(args: &cli::Args, cfg: &registry::ModelsConfig) -> Result<String> {
    if let Some(model) = &args.model {
        Ok(model.clone())
    } else if args.quick {
        cfg.quick_model
            .clone()
            .context("no quick model configured in the registry (set quick_model)")
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

/// Downloads (if not already cached) every requested model's GGUF file
/// via the network, one-off, so normal inference runs never need to.
fn run_fetch(args: &cli::Args) -> Result<()> {
    std::env::set_var("HF_HOME", models_dir(args));
    let cfg = registry::load(&models_config_path(args))?;

    let targets: Vec<(String, registry::ModelEntry)> = if args.model.is_some() || args.quick {
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
            println!("{name}: already cached at {}", path.display());
            continue;
        }
        println!("{name}: downloading {}/{} ...", entry.repo_id, entry.file);
        let path = api
            .model(entry.repo_id.clone())
            .download(&entry.file)
            .with_context(|| format!("failed to download model '{name}'"))?;
        println!("{name}: fetched to {}", path.display());
    }

    Ok(())
}

async fn load_model(args: &cli::Args) -> Result<Model> {
    let load_start = std::time::Instant::now();
    std::env::set_var("HF_HOME", models_dir(args));
    let cfg = registry::load(&models_config_path(args))?;
    let model_name = resolve_model_name(args, &cfg)?;
    let entry = registry::resolve(&cfg, &model_name)?;

    let gguf_path = resolve_local_gguf(entry).with_context(|| {
        format!(
            "model '{model_name}' is not downloaded yet - run `textinfer --fetch --model {model_name}` first"
        )
    })?;
    let model_dir = gguf_path
        .parent()
        .context("resolved model path has no parent directory")?
        .to_path_buf();

    // Passing a local directory (rather than a HF repo id) makes
    // mistralrs load purely from disk - no hf-hub network/ETag checks
    // on every invocation, which is what made repo-id-based loading
    // slow and inconsistent (measured 30-90s here just for cache-freshness
    // checks, even with the model fully cached already).
    let model = GgufModelBuilder::new(model_dir.to_string_lossy().to_string(), vec![entry.file.clone()])
        .build()
        .await
        .with_context(|| format!("failed to load model '{model_name}'"))?;
    eprintln!("textinfer: [timing] model load took {:.2}s", load_start.elapsed().as_secs_f32());
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

fn run_worker(args: &cli::Args) -> Result<()> {
    let runtime = tokio::runtime::Runtime::new()?;
    runtime.block_on(async {
        if let Some(cores_str) = &args.worker_cores {
            let cores: Vec<usize> = cores_str
                .split(',')
                .filter_map(|s| s.trim().parse().ok())
                .collect();
            topology::pin_current_process(&cores);
        }

        let model = load_model(args).await?;

        let stdin = std::io::stdin();
        let mut stdout = std::io::stdout();
        for line in stdin.lock().lines() {
            let line = line.context("failed to read job from stdin")?;
            if line.trim().is_empty() {
                continue;
            }
            let job: JobIn = serde_json::from_str(&line).context("failed to parse job")?;
            let out = match run_job(&model, &job.ops, &job.text).await {
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
        Ok::<(), anyhow::Error>(())
    })
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
    let args = cli::Args::parse();

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

    if args.dry_run {
        for input in &inputs {
            print!("{}", render_dry_run(&input.label, &ops, &input.text));
            println!();
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
        // user asked for a single worker.
        let runtime = tokio::runtime::Runtime::new()?;
        runtime.block_on(async {
            let model = load_model(&args).await?;
            let mut out = Vec::with_capacity(jobs.len());
            for job in &jobs {
                let out_item = match run_job(&model, &job.ops, &job.text).await {
                    Ok(value) => JobOut { id: job.id, value: Some(value), error: None },
                    Err(e) => JobOut { id: job.id, value: None, error: Some(e.to_string()) },
                };
                out.push(out_item);
            }
            Ok::<Vec<JobOut>, anyhow::Error>(out)
        })?
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
                    Some(value) => print!("{}", render_markdown(&input.label, multiple, value)),
                    None => {
                        had_error = true;
                        eprintln!(
                            "textinfer: {}: {}",
                            input.label,
                            result.error.as_deref().unwrap_or("unknown error")
                        );
                    }
                }
                if multiple {
                    println!();
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
                println!("{}", serde_json::to_string_pretty(&entries)?);
            } else if let Some(entry) = entries.into_iter().next() {
                println!("{}", serde_json::to_string_pretty(&entry)?);
            }
            if had_error {
                std::process::exit(1);
            }
        }
    }

    Ok(())
}
