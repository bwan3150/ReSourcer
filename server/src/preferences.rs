// 运行偏好：config/preference.json
//
// 与 app.json 的区别：app.json 记的是「这个版本是什么」（版本号、下载地址），
// 由更新流程写入；preference.json 记的是「这台部署想怎么跑」，由用户决定，
// 更新时不应该被覆盖。
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Preferences {
    /// 是否由服务端托管网页端。关掉之后只剩后端 API + 移动端 App
    #[serde(default = "default_true")]
    pub enable_web: bool,
}

fn default_true() -> bool {
    true
}

impl Default for Preferences {
    fn default() -> Self {
        Self { enable_web: true }
    }
}

fn path() -> std::path::PathBuf {
    crate::static_files::data_dir()
        .join("config")
        .join("preference.json")
}

/// 读取偏好；文件不存在或损坏时一律回退到默认值，不让它挡住启动
pub fn load() -> Preferences {
    let Ok(data) = std::fs::read(path()) else {
        return Preferences::default();
    };
    match serde_json::from_slice(&data) {
        Ok(p) => p,
        Err(e) => {
            eprintln!("[preference] 解析 preference.json 失败，使用默认值: {}", e);
            Preferences::default()
        }
    }
}

/// 写回偏好
pub fn save(prefs: &Preferences) -> Result<(), String> {
    let p = path();
    if let Some(parent) = p.parent() {
        std::fs::create_dir_all(parent).map_err(|e| format!("无法创建配置目录: {}", e))?;
    }
    let body = serde_json::to_string_pretty(prefs).map_err(|e| e.to_string())?;
    std::fs::write(&p, body).map_err(|e| format!("无法写入 preference.json: {}", e))
}

/// 首次启动时把默认偏好落盘，让用户知道有这个文件可以改
pub fn ensure_exists() {
    if !path().exists() {
        let _ = save(&Preferences::default());
    }
}
