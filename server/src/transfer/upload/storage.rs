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

// 加载上传历史记录（从 SQLite 数据库）— 仅供内部使用
pub fn load_history() -> io::Result<Vec<HistoryItem>> {
    load_history_page(0, 5000, None)
}

// 分页加载上传历史记录
pub fn load_history_page(offset: i64, limit: i64, status: Option<&str>) -> io::Result<Vec<HistoryItem>> {
    let conn = database::get_connection()
        .map_err(|e| io::Error::new(io::ErrorKind::Other, format!("数据库连接失败: {}", e)))?;

    let (sql, params) = build_history_query(
        "SELECT id, file_name, target_folder, status, file_size, error, created_at FROM upload_history",
        status,
        Some(limit),
        Some(offset),
    );

    let mut stmt = conn.prepare(&sql)
        .map_err(|e| io::Error::new(io::ErrorKind::Other, format!("准备查询失败: {}", e)))?;

    let history: Vec<HistoryItem> = stmt.query_map(rusqlite::params_from_iter(params.iter()), |row| {
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

// 统计上传历史记录总数
pub fn count_history(status: Option<&str>) -> io::Result<i64> {
    let conn = database::get_connection()
        .map_err(|e| io::Error::new(io::ErrorKind::Other, format!("数据库连接失败: {}", e)))?;

    let (sql, params) = build_history_query(
        "SELECT COUNT(*) FROM upload_history",
        status,
        None,
        None,
    );

    let count: i64 = conn.query_row(&sql, rusqlite::params_from_iter(params.iter()), |row| row.get(0))
        .map_err(|e| io::Error::new(io::ErrorKind::Other, format!("统计历史记录失败: {}", e)))?;

    Ok(count)
}

// 构建带状态过滤的 SQL 查询
fn build_history_query(
    base_sql: &str,
    status: Option<&str>,
    limit: Option<i64>,
    offset: Option<i64>,
) -> (String, Vec<String>) {
    let mut sql = base_sql.to_string();
    let mut params: Vec<String> = Vec::new();

    match status {
        Some("completed") => {
            sql.push_str(" WHERE status = ?1");
            params.push("completed".to_string());
        }
        Some("failed") => {
            sql.push_str(" WHERE status = 'failed'");
        }
        _ => {}
    }

    if limit.is_some() || offset.is_some() {
        sql.push_str(" ORDER BY created_at DESC");
        if let Some(l) = limit {
            let idx = params.len() + 1;
            sql.push_str(&format!(" LIMIT ?{}", idx));
            params.push(l.to_string());
        }
        if let Some(o) = offset {
            let idx = params.len() + 1;
            sql.push_str(&format!(" OFFSET ?{}", idx));
            params.push(o.to_string());
        }
    }

    (sql, params)
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

    // 限制数量（保留最新5000条）
    conn.execute(
        "DELETE FROM upload_history WHERE id NOT IN (
            SELECT id FROM upload_history ORDER BY created_at DESC LIMIT 5000
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
