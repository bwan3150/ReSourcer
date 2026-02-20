// 预览相关的数据模型（从gallery/models.rs迁移）
use serde::{Deserialize, Serialize};

/// 文件类型
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum FileType {
    Image,   // 图片
    Video,   // 视频
    Gif,     // GIF 动图
    Audio,   // 音频
    Pdf,     // PDF 文档
    Other,   // 其他文件
}

/// 文件信息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileInfo {
    pub name: String,              // 文件名
    pub path: String,              // 绝对路径（用于API访问）
    pub file_type: FileType,       // 文件类型
    pub extension: String,         // 文件扩展名（如 ".jpg"）
    pub size: u64,                 // 文件大小（字节）
    pub created: String,           // 创建时间
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

/// 支持的图片格式
pub const IMAGE_EXTENSIONS: &[&str] = &["jpg", "jpeg", "png", "webp", "bmp", "tiff", "svg", "heic", "heif", "avif"];

/// 支持的视频格式
pub const VIDEO_EXTENSIONS: &[&str] = &["mp4", "mov", "avi", "mkv", "flv", "wmv", "m4v", "webm"];

/// GIF 格式
pub const GIF_EXTENSION: &str = "gif";

/// 支持的音频格式
pub const AUDIO_EXTENSIONS: &[&str] = &["mp3", "wav", "aac", "flac", "m4a", "ogg", "wma"];

/// PDF 格式
pub const PDF_EXTENSION: &str = "pdf";

/// CLIP (Clip Studio Paint) 格式
pub const CLIP_EXTENSION: &str = "clip";
