use serde::{Deserialize, Serialize};

// 下载任务请求
#[derive(Debug, Deserialize)]
pub struct DownloadRequest {
    pub url: String,
    pub save_path: Option<String>,
    pub format: Option<String>, // 可选：best, mp4, mp3 等
}

// 下载任务信息
#[derive(Debug, Serialize)]
pub struct DownloadTask {
    pub id: String,
    pub url: String,
    pub status: String, // pending, downloading, completed, failed
    pub progress: f32,
    pub save_path: String,
    pub error: Option<String>,
}

// 任务状态响应
#[derive(Debug, Serialize)]
pub struct TaskStatusResponse {
    pub status: String,
    pub tasks: Vec<DownloadTask>,
}
