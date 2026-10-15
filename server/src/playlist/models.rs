use serde::{Deserialize, Serialize};
use crate::indexer::models::IndexedFile;

#[derive(Debug, Deserialize)]
pub struct PlaylistQuery {
    pub uuid: String,
    pub folder_path: String,
    /// `sequential` | `list_loop` | `shuffle`
    pub mode: String,
    pub sort: Option<String>,      // name_asc, name_desc, size_asc, etc.
    pub file_type: Option<String>, // filter by type (e.g. "video")
    /// Comma-separated UUIDs of the client's current shuffle queue.
    /// Only used in shuffle mode while navigating an existing shuffled window.
    /// Omit (or leave empty) when first entering shuffle so the server builds a fresh random queue.
    pub current_queue: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct PlaylistResponse {
    pub items: Vec<IndexedFile>,
    pub current_index: usize,
    /// True when the current file is the first in folder sort order (sequential / list_loop).
    #[serde(default)]
    pub at_start: bool,
    /// True when the current file is the last in folder sort order (sequential / list_loop).
    #[serde(default)]
    pub at_end: bool,
}
