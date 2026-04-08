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

/// Shared state: the latest snapshot + server start time
pub struct MetricsState {
    pub latest: Option<MetricsSnapshot>,
    pub started_at: chrono::DateTime<chrono::Utc>,
}

impl Default for MetricsState {
    fn default() -> Self {
        Self {
            latest: None,
            started_at: chrono::Utc::now(),
        }
    }
}
