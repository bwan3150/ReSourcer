use serde::{Deserialize, Serialize};
use crate::indexer::models::IndexedFile;

#[derive(Debug, Deserialize)]
pub struct PlaylistQuery {
    pub uuid: String,
    pub folder_path: String,
    pub mode: String,              // "sequential" or "shuffle"
    pub sort: Option<String>,      // name_asc, name_desc, size_asc, etc.
    pub file_type: Option<String>, // filter by type (e.g. "video")
    pub keep_uuids: Option<String>, // comma-separated UUIDs to keep (shuffle mode)
}

#[derive(Debug, Serialize)]
pub struct PlaylistResponse {
    pub items: Vec<IndexedFile>,
    pub current_index: usize,
}
