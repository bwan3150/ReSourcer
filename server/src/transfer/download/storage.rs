// 下载模块的存储功能 - 历史记录和配置管理
use std::path::PathBuf;
use std::fs;
use serde::{Deserialize, Serialize};

/// 下载历史记录项
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HistoryItem {
    pub id: String,
    pub url: String,
    pub platform: String,
    pub status: String, // "completed", "failed", "cancelled"
    pub file_name: Option<String>, // 成功时有值
    pub file_path: Option<String>, // 成功时有值
    pub error: Option<String>, // 失败时有值
    pub created_at: String,
}

/// 下载器配置数据
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConfigData {
    pub source_folder: String,
    pub hidden_folders: Vec<String>,
    pub use_cookies: bool,
}

// 获取配置目录路径 ~/.config/re-sourcer
pub fn get_config_dir() -> Result<PathBuf, String> {
    let home = std::env::var("HOME")
        .or_else(|_| std::env::var("USERPROFILE"))
        .map_err(|_| "无法获取 HOME 环境变量".to_string())?;

    Ok(PathBuf::from(home).join(".config").join("re-sourcer"))
}

// 获取认证文件根目录
pub fn get_credentials_dir() -> Result<PathBuf, String> {
    Ok(get_config_dir()?.join("credentials"))
}

// 确保配置目录存在
pub fn ensure_config_dir() -> Result<(), String> {
    let config_dir = get_config_dir()?;
    if !config_dir.exists() {
        fs::create_dir_all(&config_dir)
            .map_err(|e| format!("无法创建配置目录: {}", e))?;
    }

    let creds_dir = get_credentials_dir()?;
    if !creds_dir.exists() {
        fs::create_dir_all(&creds_dir)
            .map_err(|e| format!("无法创建认证目录: {}", e))?;
    }

    Ok(())
}

// 默认配置
fn get_default_config() -> ConfigData {
    ConfigData {
        source_folder: String::new(),
        hidden_folders: vec![],
        use_cookies: true,
    }
}

// 获取配置文件路径
fn get_config_path() -> Result<PathBuf, String> {
    Ok(get_config_dir()?.join("config.json"))
}

// 加载主配置文件
pub fn load_config() -> Result<ConfigData, String> {
    let config_path = get_config_path()?;

    if !config_path.exists() {
        return Ok(get_default_config());
    }

    let content = fs::read_to_string(&config_path)
        .map_err(|e| format!("无法读取配置文件: {}", e))?;

    serde_json::from_str(&content)
        .map_err(|e| format!("配置文件格式错误: {}", e))
}

// 保存主配置文件（预留接口，暂未使用）
#[allow(dead_code)]
pub fn save_config(config: &ConfigData) -> Result<(), String> {
    ensure_config_dir()?;

    let config_path = get_config_path()?;
    let content = serde_json::to_string_pretty(config)
        .map_err(|e| format!("序列化配置失败: {}", e))?;

    fs::write(&config_path, content)
        .map_err(|e| format!("无法写入配置文件: {}", e))?;

    Ok(())
}

// 获取历史记录文件路径
fn get_history_path() -> Result<PathBuf, String> {
    Ok(get_config_dir()?.join("download_history.json"))
}

// 加载历史记录
pub fn load_history() -> Result<Vec<HistoryItem>, String> {
    let history_path = get_history_path()?;

    if !history_path.exists() {
        return Ok(Vec::new());
    }

    let content = fs::read_to_string(&history_path)
        .map_err(|e| format!("无法读取历史记录: {}", e))?;

    serde_json::from_str(&content)
        .map_err(|e| format!("历史记录格式错误: {}", e))
}

// 保存历史记录
fn save_history(history: &[HistoryItem]) -> Result<(), String> {
    ensure_config_dir()?;

    let history_path = get_history_path()?;
    let content = serde_json::to_string_pretty(history)
        .map_err(|e| format!("序列化历史记录失败: {}", e))?;

    fs::write(&history_path, content)
        .map_err(|e| format!("无法写入历史记录: {}", e))?;

    Ok(())
}

// 添加到历史记录（去重并限制数量）
pub fn add_to_history(item: HistoryItem) -> Result<(), String> {
    let mut history = load_history()?;

    // 去重：如果已存在相同 ID，先移除
    history.retain(|h| h.id != item.id);

    // 添加到开头
    history.insert(0, item);

    // 限制数量（最多100条）
    if history.len() > 100 {
        history.truncate(100);
    }

    save_history(&history)
}

// 从历史记录中删除单个条目
pub fn remove_from_history(task_id: &str) -> Result<(), String> {
    let mut history = load_history()?;
    history.retain(|h| h.id != task_id);
    save_history(&history)
}

// 清空历史记录
pub fn clear_history() -> Result<(), String> {
    save_history(&[])
}
