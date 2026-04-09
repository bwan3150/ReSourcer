use actix_web::{web, HttpResponse, Result};
use super::models::*;
use super::storage;

pub async fn playlist(query: web::Query<PlaylistQuery>) -> Result<HttpResponse> {
    let uuid = query.uuid.clone();
    let folder_path = query.folder_path.clone();
    let mode = query.mode.clone();
    let sort = query.sort.clone();
    let file_type = query.file_type.clone();
    let keep_uuids_str = query.keep_uuids.clone();

    let result = tokio::task::spawn_blocking(move || {
        match mode.as_str() {
            "shuffle" => {
                let keep: Option<Vec<String>> = keep_uuids_str.map(|s| {
                    s.split(',').map(|u| u.trim().to_string()).filter(|u| !u.is_empty()).collect()
                });
                storage::get_playlist_shuffle(
                    &folder_path,
                    &uuid,
                    file_type.as_deref(),
                    keep.as_deref(),
                )
            }
            _ => {
                // sequential (default)
                storage::get_playlist_sequential(
                    &folder_path,
                    &uuid,
                    file_type.as_deref(),
                    sort.as_deref(),
                )
            }
        }
    })
    .await
    .map_err(|e| actix_web::error::ErrorInternalServerError(e.to_string()))?;

    match result {
        Ok((items, current_index)) => {
            Ok(HttpResponse::Ok().json(PlaylistResponse { items, current_index }))
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
