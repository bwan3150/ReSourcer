use serde::{Deserialize, Serialize};

/// 上传任务状态
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum UploadStatus {
    Pending,    // 等待上传
    Uploading,  // 上传中
    Completed,  // 已完成
    Failed,     // 失败
}

/// 上传任务
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UploadTask {
    pub id: String,                    // 任务 ID
    pub file_name: String,             // 文件名
    pub file_size: u64,                // 文件大小（字节）
    pub target_folder: String,         // 目标文件夹路径
    pub status: UploadStatus,          // 状态
    pub progress: f32,                 // 进度 (0-100)
    pub uploaded_size: u64,            // 已上传大小（字节）
    pub error: Option<String>,         // 错误信息
    pub created_at: String,            // 创建时间
}

/// 上传请求（通过 multipart form-data）
#[derive(Debug, Deserialize)]
pub struct UploadRequest {
    pub target_folder: String,  // 目标文件夹
}

/// 上传响应
#[derive(Debug, Serialize)]
pub struct UploadResponse {
    pub task_id: String,
    pub message: String,
}

/// 任务列表响应
#[derive(Debug, Serialize)]
pub struct TaskListResponse {
    pub tasks: Vec<UploadTask>,
}
