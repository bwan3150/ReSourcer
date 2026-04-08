use std::sync::{Arc, RwLock};
use sysinfo::{System, Disks, Pid};
use super::models::{MetricsSnapshot, MetricsState};
use super::storage;

/// Spawns the background metrics collection loop.
pub fn start_collector(state: Arc<RwLock<MetricsState>>) {
    // Collection task: every 30 seconds (first tick is immediate)
    tokio::spawn(async move {
        let mut sys = System::new();
        let pid = Pid::from_u32(std::process::id());
        let disks = Disks::new_with_refreshed_list();

        let mut interval = tokio::time::interval(std::time::Duration::from_secs(30));

        loop {
            interval.tick().await;

            // CPU requires two refreshes with a gap
            sys.refresh_cpu_usage();
            tokio::time::sleep(std::time::Duration::from_millis(200)).await;
            sys.refresh_cpu_usage();

            // Memory + process
            sys.refresh_memory();
            sys.refresh_process(pid);

            let snapshot = build_snapshot(&sys, &disks, pid, &state);

            // Update cached latest
            {
                let mut s = state.write().unwrap();
                let is_first = s.latest.is_none();
                s.latest = Some(snapshot.clone());
                if is_first {
                    eprintln!("[metrics] first snapshot: CPU {:.1}%, Mem {:.1} GB",
                        snapshot.cpu_usage_percent,
                        snapshot.memory_used_bytes as f64 / 1024.0 / 1024.0 / 1024.0);
                }
            }

            // Persist to SQLite
            let snap = snapshot.clone();
            let _ = tokio::task::spawn_blocking(move || {
                if let Err(e) = storage::insert_snapshot(&snap) {
                    eprintln!("[metrics] failed to persist snapshot: {}", e);
                }
            }).await;
        }
    });

    // Cleanup task: every 10 minutes
    tokio::spawn(async {
        let mut interval = tokio::time::interval(std::time::Duration::from_secs(600));
        loop {
            interval.tick().await;
            let _ = tokio::task::spawn_blocking(|| {
                if let Err(e) = storage::cleanup_old_snapshots() {
                    eprintln!("[metrics] cleanup error: {}", e);
                }
            }).await;
        }
    });

    eprintln!("[metrics] collector started (30s interval, 24h retention)");
}

fn build_snapshot(sys: &System, disks: &Disks, pid: Pid, state: &Arc<RwLock<MetricsState>>) -> MetricsSnapshot {
    let cpu_usage = sys.global_cpu_info().cpu_usage();
    let mem_total = sys.total_memory();
    let mem_used = sys.used_memory();
    let mem_available = sys.available_memory();

    // Load averages
    let load = System::load_average();

    // Process memory (RSS)
    let process_mem = sys.process(pid)
        .map(|p| p.memory())
        .unwrap_or(0);

    // Disk: use the largest disk as primary (typically the data volume on NAS)
    let (disk_total, disk_used, disk_avail) = disks.list().iter()
        .max_by_key(|d| d.total_space())
        .map(|d| {
            let total = d.total_space();
            let avail = d.available_space();
            (total, total.saturating_sub(avail), avail)
        })
        .unwrap_or((0, 0, 0));

    // Uptime
    let started_at = state.read().unwrap().started_at;
    let uptime = (chrono::Utc::now() - started_at).num_seconds().max(0) as u64;

    MetricsSnapshot {
        timestamp: chrono::Utc::now().to_rfc3339(),
        cpu_usage_percent: cpu_usage,
        memory_total_bytes: mem_total,
        memory_used_bytes: mem_used,
        memory_available_bytes: mem_available,
        disk_total_bytes: disk_total,
        disk_used_bytes: disk_used,
        disk_available_bytes: disk_avail,
        load_avg_1m: load.one,
        load_avg_5m: load.five,
        load_avg_15m: load.fifteen,
        process_memory_bytes: process_mem,
        uptime_seconds: uptime,
        system_uptime_seconds: System::uptime(),
    }
}
