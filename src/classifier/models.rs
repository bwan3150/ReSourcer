use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize)]
pub struct AppState {
    pub source_folder: String,
    #[serde(default)]
    pub hidden_folders: Vec<String>, // 隐藏的文件夹列表
    #[serde(default)]
    pub backup_source_folders: Vec<String>, // 备用源文件夹列表
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
pub struct CreateFolderRequest {
    pub folder_name: String,
}

#[derive(Serialize)]
pub struct FolderInfo {
    pub name: String,
    pub hidden: bool,
    pub file_count: usize,
}

#[derive(Deserialize)]
pub struct SaveSettingsRequest {
    pub source_folder: String,
    pub categories: Vec<String>, // 要显示的分类列表
    pub hidden_folders: Vec<String>, // 要隐藏的文件夹列表
}

// 源文件夹管理请求
#[derive(Deserialize)]
pub struct AddSourceFolderRequest {
    pub folder_path: String,
}

#[derive(Deserialize)]
pub struct SwitchSourceFolderRequest {
    pub folder_path: String,
}

#[derive(Deserialize)]
pub struct RemoveSourceFolderRequest {
    pub folder_path: String,
}

// 分类排序请求
#[derive(Deserialize)]
pub struct ReorderCategoriesRequest {
    pub source_folder: String, // 源文件夹路径
    pub category_order: Vec<String>, // 新的分类顺序
}

// 分类排序配置 - 按源文件夹存储
#[derive(Serialize, Deserialize, Default)]
pub struct CategoryOrderConfig {
    #[serde(default)]
    pub orders: std::collections::HashMap<String, Vec<String>>, // 源文件夹 -> 分类顺序
}