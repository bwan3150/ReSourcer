// 上传模块的存储功能 - 使用 SQLite 数据库
use crate::database;
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

// 加载上传历史记录（从 SQLite 数据库）
pub fn load_history() -> io::Result<Vec<HistoryItem>> {
    let conn = database::get_connection()
        .map_err(|e| io::Error::new(io::ErrorKind::Other, format!("数据库连接失败: {}", e)))?;

    let mut stmt = conn.prepare(
        "SELECT id, file_name, target_folder, status, file_size, error, created_at
         FROM upload_history
         ORDER BY created_at DESC
         LIMIT 100"
    ).map_err(|e| io::Error::new(io::ErrorKind::Other, format!("准备查询失败: {}", e)))?;

    let history: Vec<HistoryItem> = stmt.query_map([], |row| {
        let file_size: i64 = row.get(4)?;
        Ok(HistoryItem {
            id: row.get(0)?,
            file_name: row.get(1)?,
            target_folder: row.get(2)?,
            status: row.get(3)?,
            file_size: file_size as u64,
            error: row.get(5)?,
            created_at: row.get(6)?,
        })
    })
    .map_err(|e| io::Error::new(io::ErrorKind::Other, format!("查询历史记录失败: {}", e)))?
    .filter_map(|r| r.ok())
    .collect();

    Ok(history)
}

// 添加到上传历史记录（去重并限制数量）
pub fn add_to_history(item: HistoryItem) -> io::Result<()> {
    let conn = database::get_connection()
        .map_err(|e| io::Error::new(io::ErrorKind::Other, format!("数据库连接失败: {}", e)))?;

    // 使用 INSERT OR REPLACE 实现去重
    conn.execute(
        "INSERT OR REPLACE INTO upload_history (id, file_name, target_folder, status, file_size, error, created_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
        rusqlite::params![
            item.id,
            item.file_name,
            item.target_folder,
            item.status,
            item.file_size as i64,
            item.error,
            item.created_at
        ],
    ).map_err(|e| io::Error::new(io::ErrorKind::Other, format!("添加历史记录失败: {}", e)))?;

    // 限制数量（保留最新100条）
    conn.execute(
        "DELETE FROM upload_history WHERE id NOT IN (
            SELECT id FROM upload_history ORDER BY created_at DESC LIMIT 100
        )",
        [],
    ).ok();

    Ok(())
}

// 从上传历史记录中删除单个条目
pub fn remove_from_history(task_id: &str) -> io::Result<()> {
    let conn = database::get_connection()
        .map_err(|e| io::Error::new(io::ErrorKind::Other, format!("数据库连接失败: {}", e)))?;

    conn.execute(
        "DELETE FROM upload_history WHERE id = ?1",
        rusqlite::params![task_id],
    ).map_err(|e| io::Error::new(io::ErrorKind::Other, format!("删除历史记录失败: {}", e)))?;

    Ok(())
}

// 清空上传历史记录
pub fn clear_history() -> io::Result<()> {
    let conn = database::get_connection()
        .map_err(|e| io::Error::new(io::ErrorKind::Other, format!("数据库连接失败: {}", e)))?;

    conn.execute("DELETE FROM upload_history", [])
        .map_err(|e| io::Error::new(io::ErrorKind::Other, format!("清空历史记录失败: {}", e)))?;

    Ok(())
}
