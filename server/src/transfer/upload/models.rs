// 上传相关的数据模型（从uploader/models.rs迁移）
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

/// 任务列表响应
#[derive(Debug, Serialize)]
pub struct TaskListResponse {
    pub tasks: Vec<UploadTask>,
}

/// 历史记录分页响应
#[derive(Debug, Serialize)]
pub struct HistoryResponse {
    pub items: Vec<UploadTask>,
    pub total: i64,
    pub offset: i64,
    pub limit: i64,
    pub has_more: bool,
}
