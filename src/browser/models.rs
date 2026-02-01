use serde::{Deserialize, Serialize};

/// 目录项(文件或文件夹)
#[derive(Serialize, Debug)]
pub struct DirectoryItem {
    pub name: String,
    pub path: String,
    pub is_directory: bool,
}

/// 浏览目录响应
#[derive(Serialize)]
pub struct BrowseResponse {
    pub current_path: String,
    pub parent_path: Option<String>,
    pub items: Vec<DirectoryItem>,
}

/// 浏览目录请求
#[derive(Deserialize)]
pub struct BrowseRequest {
    pub path: Option<String>, // 如果为空,则使用用户主目录
}

/// 创建目录请求
#[derive(Deserialize)]
pub struct CreateDirectoryRequest {
    pub parent_path: String,
    pub directory_name: String,
}
