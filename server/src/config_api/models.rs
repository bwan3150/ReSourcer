// 配置API相关的数据模型
use serde::{Deserialize, Serialize};

/// 应用状态（主配置结构）
#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct AppState {
    pub source_folder: String,
    #[serde(default)]
    pub hidden_folders: Vec<String>, // 隐藏的文件夹列表
    #[serde(default)]
    pub backup_source_folders: Vec<String>, // 备用源文件夹列表
    #[serde(default = "default_use_cookies")]
    pub use_cookies: bool, // 下载器是否使用cookies
}

fn default_use_cookies() -> bool {
    true
}

/// 预设信息
#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct Preset {
    pub name: String,
    pub categories: Vec<String>,
}

/// 保存设置请求
#[derive(Debug, Deserialize)]
pub struct SaveSettingsRequest {
    pub source_folder: String,
    pub categories: Vec<String>,
    pub hidden_folders: Vec<String>,
}

/// 下载器配置响应
#[derive(Debug, Serialize)]
pub struct DownloadConfigResponse {
    pub source_folder: String,
    pub hidden_folders: Vec<String>,
    pub use_cookies: bool,
    pub auth_status: AuthStatus,
    pub ytdlp_version: String,
}

/// 认证状态
#[derive(Debug, Serialize, Deserialize)]
pub struct AuthStatus {
    pub x: bool,
    pub pixiv: bool,
}

/// 保存下载器配置请求
#[derive(Debug, Deserialize)]
pub struct SaveDownloadConfigRequest {
    pub source_folder: String,
    pub hidden_folders: Vec<String>,
    pub use_cookies: bool,
}

/// 源文件夹列表响应
#[derive(Debug, Serialize)]
pub struct SourceFoldersResponse {
    pub current: String,
    pub backups: Vec<String>,
}

/// 添加源文件夹请求
#[derive(Debug, Deserialize)]
pub struct AddSourceFolderRequest {
    pub folder_path: String,
}

/// 移除源文件夹请求
#[derive(Debug, Deserialize)]
pub struct RemoveSourceFolderRequest {
    pub folder_path: String,
}

/// 切换源文件夹请求
#[derive(Debug, Deserialize)]
pub struct SwitchSourceFolderRequest {
    pub folder_path: String,
}

/// 预设请求
#[derive(Debug, Deserialize)]
pub struct PresetRequest {
    pub name: String,
}

/// 预设加载响应
#[derive(Debug, Serialize)]
pub struct PresetLoadResponse {
    pub status: String,
    pub categories: Vec<String>,
    pub preset_name: String,
}

/// 支持的文件扩展名列表
pub const SUPPORTED_EXTENSIONS: &[&str] = &[
    "png", "jpg", "jpeg", "webp", "gif", "bmp", "avif",
    "PNG", "JPG", "JPEG", "WEBP", "GIF", "BMP", "AVIF",
    "mp4", "mov", "avi", "mkv", "webm",
    "MP4", "MOV", "AVI", "MKV", "WEBM",
    "heic", "HEIC", "heif", "HEIF",
    "clip", "CLIP",
    "pdf", "PDF",
    "mp3", "MP3", "wav", "WAV", "aac", "AAC", "flac", "FLAC",
    "m4a", "M4A", "ogg", "OGG", "wma", "WMA",
];
