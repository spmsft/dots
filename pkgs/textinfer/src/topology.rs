use std::collections::BTreeMap;

/// Reads /sys/devices/system/cpu/cpu*/topology/die_id for each online
/// core, grouping core ids by die (CCD on AMD). Returns an empty map if
/// the topology files aren't readable (e.g. non-Linux, sandboxed/
/// virtualized environments) so callers can fall back gracefully - this
/// sandbox itself reports die_id=0 for all cores despite having 16 of
/// them, confirming real multi-die hardware can't be assumed.
fn cores_by_die() -> BTreeMap<usize, Vec<usize>> {
    let mut by_die: BTreeMap<usize, Vec<usize>> = BTreeMap::new();
    let core_ids = core_affinity::get_core_ids().unwrap_or_default();

    for core in core_ids {
        let path = format!(
            "/sys/devices/system/cpu/cpu{}/topology/die_id",
            core.id
        );
        let die_id = std::fs::read_to_string(&path)
            .ok()
            .and_then(|s| s.trim().parse::<usize>().ok())
            .unwrap_or(0);
        by_die.entry(die_id).or_default().push(core.id);
    }

    by_die
}

/// Plans `workers` core-id groups of up to `cores_per_worker` cores each.
/// Prefers keeping each worker's cores within a single CCD/die (avoiding
/// cross-die Infinity-Fabric traffic); when the host doesn't expose
/// multiple dies (or doesn't have enough distinct dies for the requested
/// worker count), falls back to simple contiguous slicing of all
/// available cores instead.
pub fn plan_workers(workers: usize, cores_per_worker: usize) -> Vec<Vec<usize>> {
    let by_die = cores_by_die();

    if by_die.len() >= workers.max(1) {
        let mut dies: Vec<Vec<usize>> = by_die.into_values().collect();
        dies.truncate(workers);
        return dies
            .into_iter()
            .map(|mut cores| {
                cores.truncate(cores_per_worker);
                cores
            })
            .collect();
    }

    // Fallback: no usable multi-die topology - just slice all cores
    // contiguously across the requested number of workers.
    let all_cores: Vec<usize> = core_affinity::get_core_ids()
        .unwrap_or_default()
        .into_iter()
        .map(|c| c.id)
        .collect();

    all_cores
        .chunks(cores_per_worker.max(1))
        .take(workers.max(1))
        .map(|chunk| chunk.to_vec())
        .collect()
}

/// Pins the calling process to the given set of core ids via
/// sched_setaffinity(pid=0, ...). Must be called before spawning any
/// other threads (Tokio runtime, mistralrs/rayon internals) - Linux
/// threads inherit their creating thread's affinity mask at creation
/// time, so setting this once at worker startup restricts every thread
/// the process later spawns to the same core set.
pub fn pin_current_process(core_ids: &[usize]) {
    if core_ids.is_empty() {
        return;
    }
    let mut cpu_set = nix::sched::CpuSet::new();
    for &id in core_ids {
        if cpu_set.set(id).is_err() {
            eprintln!("textinfer: warning: failed to add core {id} to affinity set");
        }
    }
    if let Err(e) = nix::sched::sched_setaffinity(nix::unistd::Pid::from_raw(0), &cpu_set) {
        eprintln!("textinfer: warning: failed to set CPU affinity: {e}");
    }
}
