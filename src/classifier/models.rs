use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize)]
pub struct AppState {
    pub source_folder: String,
    pub current_preset: String,
    pub presets: Vec<Preset>,
}

#[derive(Serialize, Deserialize, Clone)]
pub struct Preset {
    pub name: String,
    pub categories: Vec<String>,
}

#[derive(Serialize)]
pub struct FileInfo {
    pub name: String,
    pub path: String,
    pub file_type: String,
}

#[derive(Deserialize)]
pub struct MoveRequest {
    pub file_path: String,
    pub category: String,
    pub new_name: Option<String>,
}

#[derive(Deserialize)]
pub struct PresetRequest {
    pub name: String,
}

#[derive(Deserialize)]
pub struct SavePresetRequest {
    pub name: String,
    pub categories: Vec<String>,
}

#[derive(Deserialize)]
pub struct UpdateFolderRequest {
    pub source_folder: String,
}