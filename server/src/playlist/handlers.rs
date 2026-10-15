use actix_web::{web, HttpResponse, Result};
use super::models::*;
use super::storage;

pub async fn playlist(query: web::Query<PlaylistQuery>) -> Result<HttpResponse> {
    let uuid = query.uuid.clone();
    let folder_path = query.folder_path.clone();
    let mode = query.mode.clone();
    let sort = query.sort.clone();
    let file_type = query.file_type.clone();
    let current_queue_str = query.current_queue.clone();

    let result = tokio::task::spawn_blocking(move || {
        match mode.as_str() {
            "shuffle" => {
                let queue: Option<Vec<String>> = current_queue_str.and_then(|s| {
                    let parsed: Vec<String> = s
                        .split(',')
                        .map(|u| u.trim().to_string())
                        .filter(|u| !u.is_empty())
                        .collect();
                    if parsed.is_empty() {
                        None
                    } else {
                        Some(parsed)
                    }
                });
                storage::get_playlist_shuffle(
                    &folder_path,
                    &uuid,
                    file_type.as_deref(),
                    queue.as_deref(),
                )
            }
            "list_loop" => storage::get_playlist_sequential(
                &folder_path,
                &uuid,
                file_type.as_deref(),
                sort.as_deref(),
                true, // wrap
            ),
            _ => {
                // sequential (default): ordered, no wrap
                storage::get_playlist_sequential(
                    &folder_path,
                    &uuid,
                    file_type.as_deref(),
                    sort.as_deref(),
                    false,
                )
            }
        }
    })
    .await
    .map_err(|e| actix_web::error::ErrorInternalServerError(e.to_string()))?;

    match result {
        Ok(window) => Ok(HttpResponse::Ok().json(PlaylistResponse {
            items: window.items,
            current_index: window.current_index,
            at_start: window.at_start,
            at_end: window.at_end,
        })),
        Err(e) => {
            if matches!(e, rusqlite::Error::QueryReturnedNoRows) {
                Ok(HttpResponse::NotFound().json(serde_json::json!({
                    "error": "File not found"
                })))
            } else {
                Ok(HttpResponse::InternalServerError().json(serde_json::json!({
                    "error": format!("Playlist error: {}", e)
                })))
            }
        }
    }
}
