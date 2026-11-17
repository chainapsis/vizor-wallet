//! How much of the device a scan batch may use.
//!
//! Trial decryption and commitment tree work run on rayon threads, by
//! default one per core at the default priority, so a long scan keeps every
//! performance core busy and heats a phone. The app lowers the level when the
//! device gets hot or enters low power mode; each batch reads it when it
//! starts. The lower level scans on a dedicated pool with fewer threads at a
//! lower scheduling priority, which on Apple devices moves them to the
//! efficiency cores: the same work at less power, over a longer time.

use std::sync::atomic::{AtomicU8, Ordering};
use std::sync::LazyLock;

/// The level a batch scans at.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum ScanPower {
    /// Rayon's global pool: one thread per core, default priority.
    Full,
    /// Half the cores at utility priority.
    Efficient,
}

impl ScanPower {
    pub(crate) fn from_level(level: u8) -> Self {
        match level {
            0 => Self::Full,
            _ => Self::Efficient,
        }
    }

    fn level(self) -> u8 {
        match self {
            Self::Full => 0,
            Self::Efficient => 1,
        }
    }
}

static SCAN_POWER: AtomicU8 = AtomicU8::new(0);

/// Sets the level later batches scan at.
pub(crate) fn set(power: ScanPower) {
    SCAN_POWER.store(power.level(), Ordering::Relaxed);
}

/// The level the next batch scans at.
pub(crate) fn current() -> ScanPower {
    ScanPower::from_level(SCAN_POWER.load(Ordering::Relaxed))
}

/// Runs `scan` at `power`.
///
/// Efficient runs `scan` on a worker of its pool, so every rayon task it
/// spawns lands in that pool. The scanning thread then blocks on the batch's
/// decryption results while holding one worker, so the pool has at least
/// two threads; with one it would wait on tasks nothing can run.
pub(crate) fn install<R: Send>(power: ScanPower, scan: impl FnOnce() -> R + Send) -> R {
    let pool = match power {
        ScanPower::Full => None,
        ScanPower::Efficient => EFFICIENT_POOL.as_ref(),
    };
    match pool {
        Some(pool) => pool.install(scan),
        // Not built (thread creation failed): scan as before.
        None => scan(),
    }
}

/// Threads in the reduced pool: the scanning thread plus `decrypting` workers.
fn pool_threads(decrypting: usize) -> usize {
    decrypting.max(1) + 1
}

fn cores() -> usize {
    std::thread::available_parallelism()
        .map(|cores| cores.get())
        .unwrap_or(2)
}

static EFFICIENT_POOL: LazyLock<Option<rayon::ThreadPool>> =
    LazyLock::new(|| build_pool(pool_threads(cores() / 2)));

fn build_pool(threads: usize) -> Option<rayon::ThreadPool> {
    rayon::ThreadPoolBuilder::new()
        .num_threads(threads)
        .thread_name(|index| format!("vizor-scan-efficient-{index}"))
        .start_handler(|_| lower_thread_priority())
        .build()
        .inspect(|_| log::info!("sync: efficient scan pool started with {threads} threads"))
        .inspect_err(|error| log::warn!("sync: could not start the efficient scan pool: {error}"))
        .ok()
}

/// Lowers the calling thread to utility priority. Best effort: a failure
/// leaves the thread at the default priority.
fn lower_thread_priority() {
    #[cfg(any(target_os = "ios", target_os = "macos"))]
    {
        // SAFETY: sets the QoS class of the calling thread only.
        unsafe {
            libc::pthread_set_qos_class_self_np(libc::qos_class_t::QOS_CLASS_UTILITY, 0);
        }
    }
    #[cfg(any(target_os = "android", target_os = "linux"))]
    {
        // Nice values are per thread on Linux: `gettid` names this thread.
        // SAFETY: changes the nice value of the calling thread only.
        unsafe {
            libc::setpriority(libc::PRIO_PROCESS, libc::gettid() as libc::id_t, 10);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn levels_round_trip_and_unknown_levels_are_efficient() {
        for power in [ScanPower::Full, ScanPower::Efficient] {
            assert_eq!(ScanPower::from_level(power.level()), power);
        }
        assert_eq!(ScanPower::from_level(7), ScanPower::Efficient);
    }

    #[test]
    fn a_reduced_pool_keeps_a_worker_for_the_scanning_thread() {
        assert_eq!(pool_threads(0), 2);
        assert_eq!(pool_threads(1), 2);
        assert_eq!(pool_threads(4), 5);
    }

    #[test]
    fn efficient_scans_on_its_own_pool() {
        let global = rayon::current_num_threads();
        assert_eq!(install(ScanPower::Full, rayon::current_num_threads), global);
        assert_eq!(
            install(ScanPower::Efficient, rayon::current_num_threads),
            pool_threads(cores() / 2)
        );
    }

    #[test]
    fn a_reduced_pool_runs_tasks_its_scanning_thread_waits_for() {
        // The scanner spawns decryption tasks and blocks on their results, as
        // `BatchReceiver::into_results` does.
        let sum = install(ScanPower::Efficient, || {
            let (tx, rx) = std::sync::mpsc::channel();
            for value in 0..64u64 {
                let tx = tx.clone();
                rayon::spawn_fifo(move || tx.send(value).unwrap());
            }
            drop(tx);
            rx.into_iter().sum::<u64>()
        });
        assert_eq!(sum, (0..64).sum::<u64>());
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn efficient_runs_at_the_utility_qos_class() {
        fn qos() -> u32 {
            let mut class = libc::qos_class_t::QOS_CLASS_UNSPECIFIED;
            let mut relative = 0;
            // SAFETY: reads the calling thread's QoS class into locals.
            unsafe {
                libc::pthread_get_qos_class_np(libc::pthread_self(), &mut class, &mut relative);
            }
            class as u32
        }
        assert_eq!(
            install(ScanPower::Efficient, qos),
            libc::qos_class_t::QOS_CLASS_UTILITY as u32
        );
    }
}
