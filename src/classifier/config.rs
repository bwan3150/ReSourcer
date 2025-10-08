use super::models::{AppState, Preset};
use std::path::PathBuf;
use std::fs;
use std::io;
use serde::{Deserialize, Serialize};

// 上传历史记录项
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UploadHistoryItem {
    pub id: String,
    pub file_name: String,
    pub target_folder: String,
    pub status: String, // "completed", "failed"
    pub file_size: u64,
    pub error: Option<String>,
    pub created_at: String,
}

// 获取配置文件目录 ~/.config/re-sourcer/
pub fn get_config_dir() -> PathBuf {
    let home = std::env::var("HOME")
        .or_else(|_| std::env::var("USERPROFILE"))
        .unwrap_or_else(|_| ".".to_string());

    PathBuf::from(home).join(".config").join("re-sourcer")
}

// 获取配置文件路径
pub fn get_config_path() -> PathBuf {
    get_config_dir().join("config.json")
}

// 确保配置目录存在
pub fn ensure_config_dir() -> io::Result<()> {
    let config_dir = get_config_dir();
    if !config_dir.exists() {
        fs::create_dir_all(&config_dir)?;
    }
    Ok(())
}

// 读取配置
pub fn load_config() -> io::Result<AppState> {
    let config_path = get_config_path();

    if !config_path.exists() {
        return Ok(get_default_state());
    }

    let content = fs::read_to_string(config_path)?;
    let state: AppState = serde_json::from_str(&content)
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;

    Ok(state)
}

// 保存配置
pub fn save_config(state: &AppState) -> io::Result<()> {
    ensure_config_dir()?;
    let config_path = get_config_path();
    let content = serde_json::to_string_pretty(state)
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
    fs::write(config_path, content)?;
    Ok(())
}

// 默认应用状态 - 不设置默认文件夹，由用户在设置页面指定
pub fn get_default_state() -> AppState {
    AppState {
        source_folder: String::new(),
        hidden_folders: Vec::new(),
        backup_source_folders: Vec::new(),
    }
}

// 加载预设列表 - 从嵌入的 config/presets.json 读取
pub fn load_presets() -> io::Result<Vec<Preset>> {
    use crate::static_files::ConfigAsset;

    // 从嵌入的资源读取预设文件
    if let Some(config_file) = ConfigAsset::get("presets.json") {
        let presets: Vec<Preset> = serde_json::from_slice(&config_file.data)
            .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
        return Ok(presets);
    }

    // 如果找不到嵌入的文件，返回空列表
    Ok(Vec::new())
}

pub const SUPPORTED_EXTENSIONS: &[&str] = &[
    "png", "jpg", "jpeg", "webp", "gif", "bmp",
    "PNG", "JPG", "JPEG", "WEBP", "GIF", "BMP",
    "mp4", "mov", "avi", "mkv", "webm",
    "MP4", "MOV", "AVI", "MKV", "WEBM",
    "heic", "HEIC", "heif", "HEIF"
];

// ========== 上传历史记录管理 ==========

// 获取上传历史记录文件路径
pub fn get_upload_history_path() -> PathBuf {
    get_config_dir().join("upload_history.json")
}

// 加载上传历史记录
pub fn load_upload_history() -> io::Result<Vec<UploadHistoryItem>> {
    let history_path = get_upload_history_path();

    if !history_path.exists() {
        return Ok(Vec::new());
    }

    let content = fs::read_to_string(&history_path)?;
    let history: Vec<UploadHistoryItem> = serde_json::from_str(&content)
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;

    Ok(history)
}

// 保存上传历史记录
pub fn save_upload_history(history: &[UploadHistoryItem]) -> io::Result<()> {
    ensure_config_dir()?;

    let history_path = get_upload_history_path();
    let content = serde_json::to_string_pretty(history)
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;

    fs::write(&history_path, content)?;
    Ok(())
}

// 添加到上传历史记录（去重并限制数量）
pub fn add_to_upload_history(item: UploadHistoryItem) -> io::Result<()> {
    let mut history = load_upload_history()?;

    // 去重：如果已存在相同 ID，先移除
    history.retain(|h| h.id != item.id);

    // 添加到开头
    history.insert(0, item);

    // 限制数量（最多100条）
    if history.len() > 100 {
        history.truncate(100);
    }

    save_upload_history(&history)
}

// 从上传历史记录中删除单个条目
pub fn remove_from_upload_history(task_id: &str) -> io::Result<()> {
    let mut history = load_upload_history()?;
    history.retain(|h| h.id != task_id);
    save_upload_history(&history)
}

// 清空上传历史记录
pub fn clear_upload_history() -> io::Result<()> {
    save_upload_history(&[])
}