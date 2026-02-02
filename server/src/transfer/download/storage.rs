// 下载模块的存储功能 - 使用 SQLite 数据库
use crate::database;
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
    Ok(database::get_config_dir())
}

// 获取认证文件根目录
pub fn get_credentials_dir() -> Result<PathBuf, String> {
    Ok(get_config_dir()?.join("credentials"))
}

// 确保配置目录存在（用于 credentials 目录）
#[allow(dead_code)]
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
#[allow(dead_code)]
fn get_default_config() -> ConfigData {
    ConfigData {
        source_folder: String::new(),
        hidden_folders: vec![],
        use_cookies: true,
    }
}

// 加载主配置文件（从 SQLite 数据库）
pub fn load_config() -> Result<ConfigData, String> {
    let conn = database::get_connection()
        .map_err(|e| format!("数据库连接失败: {}", e))?;

    // 读取 config 表
    let (hidden_folders_json, use_cookies): (String, i32) = conn.query_row(
        "SELECT hidden_folders, use_cookies FROM config WHERE id = 1",
        [],
        |row| Ok((row.get(0)?, row.get(1)?)),
    ).map_err(|e| format!("读取配置失败: {}", e))?;

    let hidden_folders: Vec<String> = serde_json::from_str(&hidden_folders_json)
        .unwrap_or_default();

    // 读取当前选中的源文件夹
    let source_folder: String = conn.query_row(
        "SELECT folder_path FROM source_folders WHERE is_selected = 1 LIMIT 1",
        [],
        |row| row.get(0),
    ).unwrap_or_default();

    Ok(ConfigData {
        source_folder,
        hidden_folders,
        use_cookies: use_cookies != 0,
    })
}

// 加载历史记录（从 SQLite 数据库）
pub fn load_history() -> Result<Vec<HistoryItem>, String> {
    let conn = database::get_connection()
        .map_err(|e| format!("数据库连接失败: {}", e))?;

    let mut stmt = conn.prepare(
        "SELECT id, url, platform, status, file_name, file_path, error, created_at
         FROM download_history
         ORDER BY created_at DESC
         LIMIT 100"
    ).map_err(|e| format!("准备查询失败: {}", e))?;

    let history: Vec<HistoryItem> = stmt.query_map([], |row| {
        Ok(HistoryItem {
            id: row.get(0)?,
            url: row.get(1)?,
            platform: row.get(2)?,
            status: row.get(3)?,
            file_name: row.get(4)?,
            file_path: row.get(5)?,
            error: row.get(6)?,
            created_at: row.get(7)?,
        })
    })
    .map_err(|e| format!("查询历史记录失败: {}", e))?
    .filter_map(|r| r.ok())
    .collect();

    Ok(history)
}

// 添加到历史记录（去重并限制数量）
pub fn add_to_history(item: HistoryItem) -> Result<(), String> {
    let conn = database::get_connection()
        .map_err(|e| format!("数据库连接失败: {}", e))?;

    // 使用 INSERT OR REPLACE 实现去重
    conn.execute(
        "INSERT OR REPLACE INTO download_history (id, url, platform, status, file_name, file_path, error, created_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
        rusqlite::params![
            item.id,
            item.url,
            item.platform,
            item.status,
            item.file_name,
            item.file_path,
            item.error,
            item.created_at
        ],
    ).map_err(|e| format!("添加历史记录失败: {}", e))?;

    // 限制数量（保留最新100条）
    conn.execute(
        "DELETE FROM download_history WHERE id NOT IN (
            SELECT id FROM download_history ORDER BY created_at DESC LIMIT 100
        )",
        [],
    ).ok();

    Ok(())
}

// 从历史记录中删除单个条目
pub fn remove_from_history(task_id: &str) -> Result<(), String> {
    let conn = database::get_connection()
        .map_err(|e| format!("数据库连接失败: {}", e))?;

    conn.execute(
        "DELETE FROM download_history WHERE id = ?1",
        rusqlite::params![task_id],
    ).map_err(|e| format!("删除历史记录失败: {}", e))?;

    Ok(())
}

// 清空历史记录
pub fn clear_history() -> Result<(), String> {
    let conn = database::get_connection()
        .map_err(|e| format!("数据库连接失败: {}", e))?;

    conn.execute("DELETE FROM download_history", [])
        .map_err(|e| format!("清空历史记录失败: {}", e))?;

    Ok(())
}
