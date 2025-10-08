use serde::{Deserialize, Serialize};

// 与 classifier/models.rs 中的 AppState 共用
// 但这里只关注设置相关的字段

#[derive(Serialize)]
pub struct FolderInfo {
    pub name: String,
    pub hidden: bool,
}

#[derive(Deserialize)]
pub struct SaveSettingsRequest {
    pub source_folder: String,
    pub categories: Vec<String>, // 要显示的分类列表
    pub hidden_folders: Vec<String>, // 要隐藏的文件夹列表
}

#[derive(Deserialize)]
pub struct CreateFolderRequest {
    pub folder_name: String,
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
