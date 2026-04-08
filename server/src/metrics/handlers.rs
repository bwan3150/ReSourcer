use actix_web::{web, HttpResponse, Result};
use std::sync::{Arc, RwLock};
use sysinfo::Disks;
use super::models::*;
use super::storage;

pub async fn current(
    state: web::Data<Arc<RwLock<MetricsState>>>,
) -> Result<HttpResponse> {
    let s = state.read().unwrap();
    match &s.latest {
        Some(snapshot) => Ok(HttpResponse::Ok().json(snapshot)),
        None => Ok(HttpResponse::Ok().json(serde_json::json!({
            "status": "collecting",
            "message": "First snapshot not yet available"
        }))),
    }
}

pub async fn history(query: web::Query<HistoryQuery>) -> Result<HttpResponse> {
    let minutes = query.minutes.unwrap_or(60).min(1440);

    let result = tokio::task::spawn_blocking(move || {
        storage::get_history(minutes)
    }).await.map_err(|e| actix_web::error::ErrorInternalServerError(e.to_string()))?;

    match result {
        Ok(snapshots) => {
            let count = snapshots.len();
            Ok(HttpResponse::Ok().json(HistoryResponse {
                snapshots,
                count,
                range_minutes: minutes,
            }))
        }
        Err(e) => Ok(HttpResponse::InternalServerError().json(serde_json::json!({
            "error": format!("Failed to fetch metrics history: {}", e)
        }))),
    }
}

pub async fn disk_details() -> Result<HttpResponse> {
    let disks_info = tokio::task::spawn_blocking(|| {
        let disks = Disks::new_with_refreshed_list();
        disks.list().iter().map(|d| {
            let total = d.total_space();
            let avail = d.available_space();
            DiskInfo {
                name: d.name().to_string_lossy().to_string(),
                mount_point: d.mount_point().to_string_lossy().to_string(),
                total_bytes: total,
                used_bytes: total.saturating_sub(avail),
                available_bytes: avail,
                filesystem: d.file_system().to_string_lossy().to_string(),
            }
        }).collect::<Vec<_>>()
    }).await.map_err(|e| actix_web::error::ErrorInternalServerError(e.to_string()))?;

    Ok(HttpResponse::Ok().json(serde_json::json!({ "disks": disks_info })))
}
