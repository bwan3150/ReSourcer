use serde::{Deserialize, Serialize};

// 设备信息
#[derive(Debug, Serialize, Deserialize)]
pub struct DeviceInfo {
    pub device_id: String,
    pub device_name: String,
    pub connected_at: String,
}
