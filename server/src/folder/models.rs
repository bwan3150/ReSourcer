// 文件夹操作相关的数据模型
use serde::{Deserialize, Serialize};

/// 文件夹信息（子文件夹模式）
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FolderInfo {
    pub name: String,
    pub hidden: bool,
    pub file_count: usize,
}

/// Gallery样式的文件夹信息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GalleryFolderInfo {
    pub name: String,
    pub path: String,
    pub is_source: bool,
    pub file_count: usize,
}

/// Gallery样式的文件夹列表响应
#[derive(Debug, Serialize, Deserialize)]
pub struct GalleryFoldersResponse {
    pub folders: Vec<GalleryFolderInfo>,
}

/// 分类排序请求
#[derive(Debug, Deserialize)]
pub struct ReorderCategoriesRequest {
    pub source_folder: String,
    pub category_order: Vec<String>,
}

/// 创建文件夹请求
#[derive(Debug, Deserialize)]
pub struct CreateFolderRequest {
    pub folder_name: String,
}

/// 打开文件夹请求
#[derive(Debug, Deserialize)]
pub struct OpenFolderRequest {
    pub path: String,
}

/// 支持的图片格式
pub const IMAGE_EXTENSIONS: &[&str] = &["jpg", "jpeg", "png", "webp", "bmp", "tiff", "svg"];

/// 支持的视频格式
pub const VIDEO_EXTENSIONS: &[&str] = &["mp4", "mov", "avi", "mkv", "flv", "wmv", "m4v", "webm"];

/// GIF 格式
pub const GIF_EXTENSION: &str = "gif";
