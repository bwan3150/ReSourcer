use serde::{Deserialize, Serialize};

// 平台类型（网站）
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum Platform {
    #[serde(rename = "youtube")]
    YouTube,
    #[serde(rename = "bilibili")]
    Bilibili,
    #[serde(rename = "x")]
    X,
    #[serde(rename = "tiktok")]
    TikTok,
    #[serde(rename = "pixiv")]
    Pixiv,
    #[serde(rename = "xiaohongshu")]
    Xiaohongshu,
    #[serde(rename = "unknown")]
    Unknown,
}

// 下载器类型（工具）
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum DownloaderType {
    #[serde(rename = "ytdlp")]
    YtDlp,
    #[serde(rename = "gallery_dl")]
    GalleryDl,
    #[serde(rename = "unknown")]
    Unknown,
}

// 任务状态
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum TaskStatus {
    #[serde(rename = "pending")]
    Pending,
    #[serde(rename = "downloading")]
    Downloading,
    #[serde(rename = "completed")]
    Completed,
    #[serde(rename = "failed")]
    Failed,
    #[serde(rename = "cancelled")]
    Cancelled,
}

// URL 检测请求
#[derive(Debug, Deserialize)]
pub struct DetectRequest {
    pub url: String,
}

// URL 检测响应
#[derive(Debug, Serialize)]
pub struct DetectResponse {
    pub platform: Platform,
    pub downloader: DownloaderType,
    pub confidence: f32, // 0.0 - 1.0
    pub platform_name: String,
    pub requires_auth: bool,
}

// 下载任务请求
#[derive(Debug, Deserialize)]
pub struct DownloadRequest {
    pub url: String,
    pub downloader: Option<DownloaderType>, // 用户可选择覆盖自动检测
    pub save_folder: String, // 相对于 source_folder 的路径，空字符串表示根目录
    pub format: Option<String>, // 格式选项：best, mp4, mp3 等
}

// 下载任务信息
#[derive(Debug, Clone, Serialize)]
pub struct DownloadTask {
    pub id: String,
    pub url: String,
    pub platform: Platform,
    pub downloader: DownloaderType,
    pub status: TaskStatus,
    pub progress: f32, // 0.0 - 100.0
    pub speed: Option<String>, // 下载速度（如 "1.2MB/s"）
    pub eta: Option<String>, // 预计剩余时间
    pub save_folder: String,
    pub file_name: Option<String>, // 下载完成后的文件名
    pub file_path: Option<String>, // 完整文件路径
    pub error: Option<String>,
    pub created_at: String, // ISO 8601 格式
}

// 任务列表响应
#[derive(Debug, Serialize)]
pub struct TaskListResponse {
    pub status: String,
    pub tasks: Vec<DownloadTask>,
}

// 单个任务响应
#[derive(Debug, Serialize)]
pub struct TaskResponse {
    pub status: String,
    pub task: DownloadTask,
}

// 创建任务响应
#[derive(Debug, Serialize)]
pub struct CreateTaskResponse {
    pub status: String,
    pub task_id: String,
    pub message: String,
}

// 文件夹信息
#[derive(Debug, Serialize)]
pub struct FolderInfo {
    pub name: String,
    pub hidden: bool,
}


// 配置响应
#[derive(Debug, Serialize)]
pub struct ConfigResponse {
    pub source_folder: String,
    pub hidden_folders: Vec<String>,
    pub use_cookies: bool,
    pub auth_status: AuthStatus,
}

// 认证状态（按平台）
#[derive(Debug, Serialize, Deserialize)]
pub struct AuthStatus {
    pub x: bool,
    pub pixiv: bool,
}

// 保存配置请求
#[derive(Debug, Deserialize)]
pub struct SaveConfigRequest {
    pub source_folder: String,
    pub hidden_folders: Vec<String>,
    pub use_cookies: bool,
}
