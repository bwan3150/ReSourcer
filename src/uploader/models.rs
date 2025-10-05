use serde::{Deserialize, Serialize};

// 上传配置
#[derive(Debug, Deserialize)]
pub struct UploadConfig {
    pub save_path: Option<String>,
}

// 上传结果
#[derive(Debug, Serialize)]
pub struct UploadResult {
    pub status: String,
    pub file_name: String,
    pub file_path: String,
    pub file_size: u64,
}

// 设备信息
#[derive(Debug, Serialize, Deserialize)]
pub struct DeviceInfo {
    pub device_id: String,
    pub device_name: String,
    pub connected_at: String,
}
