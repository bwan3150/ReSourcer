use serde::{Deserialize, Serialize};

/// 文件类型
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum FileType {
    Image,   // 图片
    Video,   // 视频
    Gif,     // GIF 动图
    Other,   // 其他文件
}

/// 文件信息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileInfo {
    pub name: String,              // 文件名
    pub path: String,              // 相对路径（用于API访问）
    pub file_type: FileType,       // 文件类型
    pub extension: String,         // 文件扩展名（如 ".jpg"）
    pub size: u64,                 // 文件大小（字节）
    pub modified: String,          // 修改时间
    pub width: Option<u32>,        // 图片/视频宽度
    pub height: Option<u32>,       // 图片/视频高度
    pub duration: Option<f64>,     // 视频/GIF时长（秒）
}

/// 文件夹信息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FolderInfo {
    pub name: String,              // 文件夹名称
    pub path: String,              // 文件夹路径
    pub is_source: bool,           // 是否为源文件夹
    pub file_count: usize,         // 文件数量
}

/// 获取文件列表的响应
#[derive(Debug, Serialize, Deserialize)]
pub struct FilesResponse {
    pub files: Vec<FileInfo>,
}

/// 获取文件夹列表的响应
#[derive(Debug, Serialize, Deserialize)]
pub struct FoldersResponse {
    pub folders: Vec<FolderInfo>,
}

/// 重命名文件请求
#[derive(Debug, Deserialize)]
pub struct RenameFileRequest {
    pub file_path: String,  // 文件路径
    pub new_name: String,   // 新文件名(不含路径)
}

/// 移动文件请求
#[derive(Debug, Deserialize)]
pub struct MoveFileRequest {
    pub file_path: String,     // 文件路径
    pub target_folder: String, // 目标文件夹路径
}

/// 文件操作响应
#[derive(Debug, Serialize)]
pub struct FileOperationResponse {
    pub status: String,
    pub new_path: Option<String>,
}
