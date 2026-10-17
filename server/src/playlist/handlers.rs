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
    let folder_for_live = folder_path.clone();

    let result = tokio::task::spawn_blocking(move || {
        let window = match mode.as_str() {
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
        }?;

        let peers = crate::indexer::storage::list_files_in_folder(&folder_for_live)
            .unwrap_or_default();
        let current_uuid = window
            .items
            .get(window.current_index)
            .map(|f| f.uuid.clone());
        let items = crate::indexer::live_photo::enrich_and_filter_live_photos(
            window.items,
            &peers,
            true,
        );
        let mut current_index = window.current_index;
        if let Some(uuid) = current_uuid {
            if let Some(idx) = items.iter().position(|f| f.uuid == uuid) {
                current_index = idx;
            } else if current_index >= items.len() {
                current_index = items.len().saturating_sub(1);
            }
        }
        Ok(storage::PlaylistWindow {
            items,
            current_index,
            at_start: window.at_start,
            at_end: window.at_end,
        })
    })
    .await
    .map_err(|e| actix_web::error::ErrorInternalServerError(e.to_string()))?;

    match result {
        Ok(window) => {
            Ok(HttpResponse::Ok().json(PlaylistResponse {
                items: window.items,
                current_index: window.current_index,
                at_start: window.at_start,
                at_end: window.at_end,
            }))
        }
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
