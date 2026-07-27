use std::collections::{BTreeMap, BTreeSet};

/// Returns the NUMA node id a core belongs to, read from the kernel's
/// `/sys/devices/system/cpu/cpu{N}/node{M}` symlink (the actual
/// memory-locality domain), or `None` if no such symlink exists (non-
/// NUMA-aware kernel, non-Linux, or a single-node/sandboxed machine).
/// This is the authoritative grouping key for "mechanical sympathy":
/// unlike `die_id` (CCD), which is only a reliable proxy for memory
/// locality on NPS1-configured AMD parts, the NUMA node is what actually
/// determines which physical DRAM a first memory touch lands on - on
/// multi-socket/NPS>1 EPYC hosts a die can be split across nodes or
/// multiple dies merged into one, so grouping workers by die alone could
/// still cross a real memory-locality boundary.
fn node_id_for_core(core_id: usize) -> Option<usize> {
    let cpu_dir = format!("/sys/devices/system/cpu/cpu{core_id}");
    std::fs::read_dir(cpu_dir).ok()?.find_map(|entry| {
        let name = entry.ok()?.file_name();
        name.to_str()?.strip_prefix("node")?.parse::<usize>().ok()
    })
}

/// Reads /sys/devices/system/cpu/cpu*/topology/die_id for each online
/// core, grouping core ids by die (CCD on AMD). Returns an empty map if
/// the topology files aren't readable (e.g. non-Linux, sandboxed/
/// virtualized environments) so callers can fall back gracefully - this
/// sandbox itself reports die_id=0 for all cores despite having 16 of
/// them, confirming real multi-die hardware can't be assumed.
fn die_id_for_core(core_id: usize) -> Option<usize> {
    let path = format!("/sys/devices/system/cpu/cpu{core_id}/topology/die_id");
    std::fs::read_to_string(&path)
        .ok()
        .and_then(|s| s.trim().parse::<usize>().ok())
}

/// Groups core ids by NUMA node (preferred - see `node_id_for_core`),
/// falling back to die/CCD id when node info isn't exposed, and finally
/// to a single group (id 0) when neither is available.
fn cores_by_die() -> BTreeMap<usize, Vec<usize>> {
    let mut by_die: BTreeMap<usize, Vec<usize>> = BTreeMap::new();
    let core_ids = core_affinity::get_core_ids().unwrap_or_default();

    for core in core_ids {
        let group_id = node_id_for_core(core.id)
            .or_else(|| die_id_for_core(core.id))
            .unwrap_or(0);
        by_die.entry(group_id).or_default().push(core.id);
    }

    by_die
}

/// Like `cores_by_die`, but groups by each logical CPU's physical
/// `core_id` (deduped per group via a set) rather than its raw logical id
/// - SMT sibling threads on the same physical core share a `core_id`, so
/// this yields the true physical-core count per NUMA node/die instead of
/// the logical (hyperthread-inclusive) one.
fn physical_cores_by_die() -> BTreeMap<usize, BTreeSet<usize>> {
    let mut by_die: BTreeMap<usize, BTreeSet<usize>> = BTreeMap::new();
    let core_ids = core_affinity::get_core_ids().unwrap_or_default();

    for core in core_ids {
        let group_id = node_id_for_core(core.id)
            .or_else(|| die_id_for_core(core.id))
            .unwrap_or(0);
        let core_path = format!("/sys/devices/system/cpu/cpu{}/topology/core_id", core.id);
        if let Some(phys_core_id) = std::fs::read_to_string(&core_path)
            .ok()
            .and_then(|s| s.trim().parse::<usize>().ok())
        {
            by_die.entry(group_id).or_default().insert(phys_core_id);
        }
    }

    by_die
}

/// Number of distinct physical cores (SMT siblings deduped) on a single
/// NUMA node/die - the natural default for --cores-per-worker: pinning a
/// worker to more logical threads than physical cores per node just
/// oversubscribes the same physical cores via SMT for no throughput
/// gain on CPU-bound inference, while pinning to fewer wastes part of a
/// node. Returns `None` if /sys topology info isn't available (matches
/// `cores_by_die`'s fallback story) so callers can fall back to a fixed
/// default instead.
pub fn physical_cores_per_die() -> Option<usize> {
    let by_die = physical_cores_by_die();
    by_die.values().map(|cores| cores.len()).max()
}

/// Plans `workers` core-id groups of up to `cores_per_worker` cores each.
/// Prefers keeping each worker's cores within a single NUMA node (falling
/// back to CCD/die when node info isn't exposed), so weights first-
/// touched during model load (see `pin_current_process`'s call site in
/// main.rs, which always runs before `load_model`) land in that worker's
/// local DRAM rather than triggering remote-node memory traffic; when the
/// host doesn't expose multiple nodes/dies (or doesn't have enough
/// distinct ones for the requested worker count), falls back to simple
/// contiguous slicing of all available cores instead.
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
/// other threads (candle/rayon/gemm internals) - Linux threads inherit
/// their creating thread's affinity mask at creation time, so setting
/// this once at worker startup restricts every thread the process later
/// spawns to the same core set.
pub fn pin_current_process(core_ids: &[usize]) {
    if core_ids.is_empty() {
        return;
    }
    let mut cpu_set = nix::sched::CpuSet::new();
    for &id in core_ids {
        if cpu_set.set(id).is_err() {
            eprintln!("parat: warning: failed to add core {id} to affinity set");
        }
    }
    if let Err(e) = nix::sched::sched_setaffinity(nix::unistd::Pid::from_raw(0), &cpu_set) {
        eprintln!("parat: warning: failed to set CPU affinity: {e}");
    }
}
