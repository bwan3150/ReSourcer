use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize)]
pub struct SettingsConfig {
    pub main_folder: String,
    pub categories: Vec<String>,
    pub hidden_categories: Vec<String>,
}

#[derive(Debug, Deserialize)]
pub struct SetFolderRequest {
    pub path: String,
}

#[derive(Debug, Deserialize)]
pub struct CreateFolderRequest {
    pub name: String,
}

#[derive(Debug, Deserialize)]
pub struct ToggleFolderRequest {
    pub name: String,
    pub hide: bool,
}

#[derive(Debug, Deserialize)]
pub struct ApplyPresetRequest {
    pub folders: Vec<String>,
}

#[derive(Debug, Serialize)]
pub struct FoldersResponse {
    pub folders: Vec<String>,
    pub hidden: Vec<String>,
}
