// 收藏模块 - SQLite CRUD 操作
use rusqlite::params;
use std::collections::HashMap;
use crate::database::get_connection;
use crate::indexer::models::IndexedFile;
use crate::indexer::storage::map_file_row;

const FILE_COLUMNS: &str = "f.uuid, f.fingerprint, f.current_path, f.folder_path, f.file_name, f.file_type, f.extension, f.file_size, f.created_at, f.modified_at, f.indexed_at, f.source_url";

/// 切换收藏状态：同级已收藏则取消，否则标记（覆盖旧级别）
/// 返回切换后是否处于收藏状态
pub fn toggle_favorite(uuid: &str, level: &str) -> Result<bool, rusqlite::Error> {
    let conn = get_connection()?;
    let existing: Option<String> = conn.query_row(
        "SELECT level FROM favorites WHERE file_uuid = ?1",
        params![uuid],
        |row| row.get(0),
    ).ok();

    if existing.as_deref() == Some(level) {
        conn.execute("DELETE FROM favorites WHERE file_uuid = ?1", params![uuid])?;
        Ok(false)
    } else {
        let now = chrono::Utc::now().to_rfc3339();
        conn.execute(
            "INSERT INTO favorites (file_uuid, level, created_at) VALUES (?1, ?2, ?3)
             ON CONFLICT(file_uuid) DO UPDATE SET level = excluded.level, created_at = excluded.created_at",
            params![uuid, level, now],
        )?;
        Ok(true)
    }
}

/// 分页查询收藏文件（容忍 file_index 中已不存在的孤儿 uuid）
pub fn list_favorites(
    level: Option<&str>,
    offset: i64,
    limit: i64,
) -> Result<(Vec<IndexedFile>, i64), rusqlite::Error> {
    let conn = get_connection()?;
    let level_clause = if level.is_some() { " AND fav.level = ?" } else { "" };

    let count_query = format!(
        "SELECT COUNT(*) FROM favorites fav JOIN file_index f ON f.uuid = fav.file_uuid
         WHERE f.current_path IS NOT NULL{}",
        level_clause
    );
    let total: i64 = {
        let mut stmt = conn.prepare(&count_query)?;
        let mut params_vec: Vec<&str> = Vec::new();
        if let Some(l) = level { params_vec.push(l); }
        let mut rows = stmt.query(rusqlite::params_from_iter(params_vec.iter()))?;
        rows.next()?.map(|r| r.get(0)).transpose()?.unwrap_or(0)
    };

    let query = format!(
        "SELECT {} FROM favorites fav JOIN file_index f ON f.uuid = fav.file_uuid
         WHERE f.current_path IS NOT NULL{}
         ORDER BY fav.created_at DESC LIMIT ? OFFSET ?",
        FILE_COLUMNS, level_clause
    );
    let mut stmt = conn.prepare(&query)?;
    let mut params_vec: Vec<String> = Vec::new();
    if let Some(l) = level { params_vec.push(l.to_string()); }
    params_vec.push(limit.to_string());
    params_vec.push(offset.to_string());
    let files = stmt
        .query_map(rusqlite::params_from_iter(params_vec.iter()), map_file_row)?
        .collect::<Result<Vec<_>, _>>()?;

    Ok((files, total))
}

/// 批量查询多个 uuid 的收藏状态，返回 uuid -> level 映射（未收藏的不在结果里）
pub fn get_favorite_status(uuids: &[String]) -> Result<HashMap<String, String>, rusqlite::Error> {
    if uuids.is_empty() {
        return Ok(HashMap::new());
    }
    let conn = get_connection()?;
    let placeholders = uuids.iter().map(|_| "?").collect::<Vec<_>>().join(", ");
    let query = format!(
        "SELECT file_uuid, level FROM favorites WHERE file_uuid IN ({})",
        placeholders
    );
    let mut stmt = conn.prepare(&query)?;
    let rows = stmt.query_map(rusqlite::params_from_iter(uuids.iter()), |row| {
        Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
    })?;
    let mut map = HashMap::new();
    for row in rows {
        let (uuid, level) = row?;
        map.insert(uuid, level);
    }
    Ok(map)
}
