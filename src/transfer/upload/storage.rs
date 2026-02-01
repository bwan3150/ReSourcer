// 上传模块的存储功能 - 历史记录管理
use std::path::PathBuf;
use std::fs;
use std::io;
use serde::{Deserialize, Serialize};

/// 上传历史记录项
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HistoryItem {
    pub id: String,
    pub file_name: String,
    pub target_folder: String,
    pub status: String, // "completed", "failed"
    pub file_size: u64,
    pub error: Option<String>,
    pub created_at: String,
}

// 获取配置目录路径 ~/.config/re-sourcer
fn get_config_dir() -> PathBuf {
    let home = std::env::var("HOME")
        .or_else(|_| std::env::var("USERPROFILE"))
        .unwrap_or_else(|_| ".".to_string());

    PathBuf::from(home).join(".config").join("re-sourcer")
}

// 确保配置目录存在
fn ensure_config_dir() -> io::Result<()> {
    let config_dir = get_config_dir();
    if !config_dir.exists() {
        fs::create_dir_all(&config_dir)?;
    }
    Ok(())
}

// 获取上传历史记录文件路径
fn get_upload_history_path() -> PathBuf {
    get_config_dir().join("upload_history.json")
}

// 加载上传历史记录
pub fn load_history() -> io::Result<Vec<HistoryItem>> {
    let history_path = get_upload_history_path();

    if !history_path.exists() {
        return Ok(Vec::new());
    }

    let content = fs::read_to_string(&history_path)?;
    let history: Vec<HistoryItem> = serde_json::from_str(&content)
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;

    Ok(history)
}

// 保存上传历史记录
fn save_history(history: &[HistoryItem]) -> io::Result<()> {
    ensure_config_dir()?;

    let history_path = get_upload_history_path();
    let content = serde_json::to_string_pretty(history)
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;

    fs::write(&history_path, content)?;
    Ok(())
}

// 添加到上传历史记录（去重并限制数量）
pub fn add_to_history(item: HistoryItem) -> io::Result<()> {
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

// 从上传历史记录中删除单个条目
pub fn remove_from_history(task_id: &str) -> io::Result<()> {
    let mut history = load_history()?;
    history.retain(|h| h.id != task_id);
    save_history(&history)
}

// 清空上传历史记录
pub fn clear_history() -> io::Result<()> {
    save_history(&[])
}
