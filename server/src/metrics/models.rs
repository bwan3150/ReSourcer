use serde::{Deserialize, Serialize};

/// A single point-in-time metrics snapshot
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MetricsSnapshot {
    pub timestamp: String,
    pub cpu_usage_percent: f32,
    pub memory_total_bytes: u64,
    pub memory_used_bytes: u64,
    pub memory_available_bytes: u64,
    pub disk_total_bytes: u64,
    pub disk_used_bytes: u64,
    pub disk_available_bytes: u64,
    pub load_avg_1m: f64,
    pub load_avg_5m: f64,
    pub load_avg_15m: f64,
    pub process_memory_bytes: u64,
    pub uptime_seconds: u64,
    pub system_uptime_seconds: u64,
}

/// Query params for history endpoint
#[derive(Debug, Deserialize)]
pub struct HistoryQuery {
    pub minutes: Option<u32>,
}

/// Response for history endpoint
#[derive(Debug, Serialize)]
pub struct HistoryResponse {
    pub snapshots: Vec<MetricsSnapshot>,
    pub count: usize,
    pub range_minutes: u32,
}

/// Disk info for the disk details endpoint
#[derive(Debug, Serialize)]
pub struct DiskInfo {
    pub name: String,
    pub mount_point: String,
    pub total_bytes: u64,
    pub used_bytes: u64,
    pub available_bytes: u64,
    pub filesystem: String,
}

/// Static system info (collected once at startup)
#[derive(Debug, Clone, Serialize)]
pub struct SystemInfo {
    pub os_name: String,
    pub os_version: String,
    pub arch: String,
    pub hostname: String,
    pub cpu_count: usize,
}

/// Shared state: the latest snapshot + server start time + system info
pub struct MetricsState {
    pub latest: Option<MetricsSnapshot>,
    pub started_at: chrono::DateTime<chrono::Utc>,
    pub system_info: SystemInfo,
}

impl MetricsState {
    pub fn new() -> Self {
        use sysinfo::System;
        Self {
            latest: None,
            started_at: chrono::Utc::now(),
            system_info: SystemInfo {
                os_name: System::name().unwrap_or_default(),
                os_version: System::os_version().unwrap_or_default(),
                arch: std::env::consts::ARCH.to_string(),
                hostname: System::host_name().unwrap_or_default(),
                cpu_count: num_cpus(),
            },
        }
    }
}

fn num_cpus() -> usize {
    let mut sys = sysinfo::System::new();
    sys.refresh_cpu_usage();
    sys.cpus().len()
}
