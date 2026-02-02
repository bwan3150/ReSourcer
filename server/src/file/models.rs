// 文件操作相关的数据模型
use serde::{Deserialize, Serialize};

/// 文件类型枚举
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum FileType {
    Image,
    Video,
    Gif,
    Other,
}

/// 文件信息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileInfo {
    pub name: String,
    pub path: String,
    pub file_type: FileType,
    pub extension: String,
    pub size: u64,
    pub modified: String,
    pub width: Option<u32>,
    pub height: Option<u32>,
    pub duration: Option<f64>,
}

/// 文件列表响应
#[derive(Debug, Serialize, Deserialize)]
pub struct FilesResponse {
    pub files: Vec<FileInfo>,
}

/// 重命名文件请求
#[derive(Debug, Deserialize)]
pub struct RenameFileRequest {
    pub file_path: String,
    pub new_name: String,
}

/// 移动文件请求
#[derive(Debug, Deserialize)]
pub struct MoveFileRequest {
    pub file_path: String,
    pub target_folder: String,
    #[serde(default)]
    pub new_name: Option<String>,  // 可选：移动时同时重命名
}

/// 文件操作响应
#[derive(Debug, Serialize)]
pub struct FileOperationResponse {
    pub status: String,
    pub new_path: Option<String>,
}

/// 支持的图片格式
pub const IMAGE_EXTENSIONS: &[&str] = &["jpg", "jpeg", "png", "webp", "bmp", "tiff", "svg"];

/// 支持的视频格式
pub const VIDEO_EXTENSIONS: &[&str] = &["mp4", "mov", "avi", "mkv", "flv", "wmv", "m4v", "webm"];

/// GIF 格式
pub const GIF_EXTENSION: &str = "gif";
