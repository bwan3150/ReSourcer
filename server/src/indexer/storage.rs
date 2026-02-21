// SQLite CRUD 操作
use rusqlite::params;
use super::models::{IndexedFile, IndexedFolder, BreadcrumbItem};
use crate::database::get_connection;

/// 插入或更新文件索引
pub fn upsert_file(file: &IndexedFile) -> Result<(), rusqlite::Error> {
    let conn = get_connection()?;
    conn.execute(
        "INSERT INTO file_index (uuid, fingerprint, current_path, folder_path, file_name, file_type, extension, file_size, created_at, modified_at, indexed_at, source_url)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12)
         ON CONFLICT(uuid) DO UPDATE SET
            fingerprint = excluded.fingerprint,
            current_path = excluded.current_path,
            folder_path = excluded.folder_path,
            file_name = excluded.file_name,
            file_type = excluded.file_type,
            extension = excluded.extension,
            file_size = excluded.file_size,
            modified_at = excluded.modified_at,
            indexed_at = excluded.indexed_at,
            source_url = COALESCE(excluded.source_url, file_index.source_url)",
        params![
            file.uuid,
            file.fingerprint,
            file.current_path,
            file.folder_path,
            file.file_name,
            file.file_type,
            file.extension,
            file.file_size,
            file.created_at,
            file.modified_at,
            file.indexed_at,
            file.source_url,
        ],
    )?;
    Ok(())
}

/// 插入或更新文件夹索引
pub fn upsert_folder(folder: &IndexedFolder) -> Result<(), rusqlite::Error> {
    let conn = get_connection()?;
    conn.execute(
        "INSERT INTO folder_index (path, parent_path, source_folder, name, depth, file_count, indexed_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
         ON CONFLICT(path) DO UPDATE SET
            parent_path = excluded.parent_path,
            source_folder = excluded.source_folder,
            name = excluded.name,
            depth = excluded.depth,
            file_count = excluded.file_count,
            indexed_at = excluded.indexed_at",
        params![
            folder.path,
            folder.parent_path,
            folder.source_folder,
            folder.name,
            folder.depth,
            folder.file_count,
            folder.indexed_at,
        ],
    )?;
    Ok(())
}

/// 分页查询文件
pub fn get_files_paginated(
    folder_path: &str,
    offset: i64,
    limit: i64,
    file_type: Option<&str>,
    sort: Option<&str>,
) -> Result<(Vec<IndexedFile>, i64), rusqlite::Error> {
    let conn = get_connection()?;

    // 构建排序
    let order_clause = match sort {
        Some("name_asc") => "file_name ASC",
        Some("name_desc") => "file_name DESC",
        Some("size_asc") => "file_size ASC",
        Some("size_desc") => "file_size DESC",
        Some("created_asc") => "created_at ASC",
        Some("created_desc") => "created_at DESC",
        _ => "modified_at DESC", // 默认按修改时间降序
    };

    let (files, total) = if let Some(ft) = file_type {
        let total: i64 = conn.query_row(
            "SELECT COUNT(*) FROM file_index WHERE folder_path = ?1 AND file_type = ?2 AND current_path IS NOT NULL",
            params![folder_path, ft],
            |row| row.get(0),
        )?;

        let query = format!(
            "SELECT uuid, fingerprint, current_path, folder_path, file_name, file_type, extension, file_size, created_at, modified_at, indexed_at, source_url
             FROM file_index WHERE folder_path = ?1 AND file_type = ?2 AND current_path IS NOT NULL
             ORDER BY {} LIMIT ?3 OFFSET ?4", order_clause
        );
        let mut stmt = conn.prepare(&query)?;
        let files = stmt.query_map(params![folder_path, ft, limit, offset], map_file_row)?
            .collect::<Result<Vec<_>, _>>()?;

        (files, total)
    } else {
        let total: i64 = conn.query_row(
            "SELECT COUNT(*) FROM file_index WHERE folder_path = ?1 AND current_path IS NOT NULL",
            params![folder_path],
            |row| row.get(0),
        )?;

        let query = format!(
            "SELECT uuid, fingerprint, current_path, folder_path, file_name, file_type, extension, file_size, created_at, modified_at, indexed_at, source_url
             FROM file_index WHERE folder_path = ?1 AND current_path IS NOT NULL
             ORDER BY {} LIMIT ?2 OFFSET ?3", order_clause
        );
        let mut stmt = conn.prepare(&query)?;
        let files = stmt.query_map(params![folder_path, limit, offset], map_file_row)?
            .collect::<Result<Vec<_>, _>>()?;

        (files, total)
    };

    Ok((files, total))
}

/// 通过 UUID 查询文件
pub fn get_file_by_uuid(uuid: &str) -> Result<Option<IndexedFile>, rusqlite::Error> {
    let conn = get_connection()?;
    let mut stmt = conn.prepare(
        "SELECT uuid, fingerprint, current_path, folder_path, file_name, file_type, extension, file_size, created_at, modified_at, indexed_at, source_url
         FROM file_index WHERE uuid = ?1"
    )?;
    let mut rows = stmt.query_map(params![uuid], map_file_row)?;
    match rows.next() {
        Some(Ok(file)) => Ok(Some(file)),
        Some(Err(e)) => Err(e),
        None => Ok(None),
    }
}

/// 通过路径查询文件
pub fn get_file_by_path(path: &str) -> Result<Option<IndexedFile>, rusqlite::Error> {
    let conn = get_connection()?;
    let mut stmt = conn.prepare(
        "SELECT uuid, fingerprint, current_path, folder_path, file_name, file_type, extension, file_size, created_at, modified_at, indexed_at, source_url
         FROM file_index WHERE current_path = ?1"
    )?;
    let mut rows = stmt.query_map(params![path], map_file_row)?;
    match rows.next() {
        Some(Ok(file)) => Ok(Some(file)),
        Some(Err(e)) => Err(e),
        None => Ok(None),
    }
}

/// 查找指纹匹配的孤儿文件（current_path 为 NULL，即文件已被标记为缺失）
pub fn find_orphan_by_fingerprint(fingerprint: &str) -> Result<Option<IndexedFile>, rusqlite::Error> {
    let conn = get_connection()?;
    let mut stmt = conn.prepare(
        "SELECT uuid, fingerprint, current_path, folder_path, file_name, file_type, extension, file_size, created_at, modified_at, indexed_at, source_url
         FROM file_index WHERE fingerprint = ?1 AND current_path IS NULL LIMIT 1"
    )?;
    let mut rows = stmt.query_map(params![fingerprint], map_file_row)?;
    match rows.next() {
        Some(Ok(file)) => Ok(Some(file)),
        Some(Err(e)) => Err(e),
        None => Ok(None),
    }
}

/// 更新文件路径（移动/重命名时使用）
pub fn update_file_path(uuid: &str, new_path: &str, new_folder: &str, new_name: &str) -> Result<(), rusqlite::Error> {
    let conn = get_connection()?;
    let now = chrono::Utc::now().to_rfc3339();
    conn.execute(
        "UPDATE file_index SET current_path = ?1, folder_path = ?2, file_name = ?3, indexed_at = ?4 WHERE uuid = ?5",
        params![new_path, new_folder, new_name, now, uuid],
    )?;
    Ok(())
}

/// 标记已不存在的文件为缺失（set current_path = NULL）
pub fn mark_missing(folder_path: &str, still_existing_paths: &[String]) -> Result<(), rusqlite::Error> {
    let conn = get_connection()?;

    if still_existing_paths.is_empty() {
        // 该文件夹下所有文件都不存在了
        conn.execute(
            "UPDATE file_index SET current_path = NULL WHERE folder_path = ?1 AND current_path IS NOT NULL",
            params![folder_path],
        )?;
    } else {
        // 构建占位符
        let placeholders: Vec<String> = still_existing_paths.iter().enumerate()
            .map(|(i, _)| format!("?{}", i + 2))
            .collect();
        let sql = format!(
            "UPDATE file_index SET current_path = NULL WHERE folder_path = ?1 AND current_path IS NOT NULL AND current_path NOT IN ({})",
            placeholders.join(",")
        );

        let mut stmt = conn.prepare(&sql)?;
        let mut param_values: Vec<Box<dyn rusqlite::types::ToSql>> = Vec::new();
        param_values.push(Box::new(folder_path.to_string()));
        for p in still_existing_paths {
            param_values.push(Box::new(p.clone()));
        }
        let params_ref: Vec<&dyn rusqlite::types::ToSql> = param_values.iter().map(|p| p.as_ref()).collect();
        stmt.execute(&*params_ref)?;
    }

    Ok(())
}

/// 查询子文件夹
pub fn get_subfolders(parent_path: &str) -> Result<Vec<IndexedFolder>, rusqlite::Error> {
    let conn = get_connection()?;
    let mut stmt = conn.prepare(
        "SELECT path, parent_path, source_folder, name, depth, file_count, indexed_at
         FROM folder_index WHERE parent_path = ?1 ORDER BY name ASC"
    )?;
    let folders = stmt.query_map(params![parent_path], |row| {
        Ok(IndexedFolder {
            path: row.get(0)?,
            parent_path: row.get(1)?,
            source_folder: row.get(2)?,
            name: row.get(3)?,
            depth: row.get(4)?,
            file_count: row.get(5)?,
            indexed_at: row.get(6)?,
        })
    })?.collect::<Result<Vec<_>, _>>()?;
    Ok(folders)
}

/// 获取面包屑路径
pub fn get_breadcrumb(folder_path: &str, source_folder: &str) -> Vec<BreadcrumbItem> {
    let mut crumbs = Vec::new();

    // 从 folder_path 向上遍历到 source_folder
    let source = std::path::Path::new(source_folder);
    let current = std::path::Path::new(folder_path);

    // source_folder 本身作为根
    if let Some(name) = source.file_name() {
        crumbs.push(BreadcrumbItem {
            name: name.to_string_lossy().to_string(),
            path: source_folder.to_string(),
        });
    }

    // 从 source_folder 往下到 folder_path
    if let Ok(relative) = current.strip_prefix(source) {
        let mut accumulated = source.to_path_buf();
        for component in relative.components() {
            accumulated = accumulated.join(component);
            crumbs.push(BreadcrumbItem {
                name: component.as_os_str().to_string_lossy().to_string(),
                path: accumulated.to_string_lossy().to_string(),
            });
        }
    }

    crumbs
}

/// 获取文件夹的索引时间
pub fn get_folder_indexed_at(folder_path: &str) -> Result<Option<String>, rusqlite::Error> {
    let conn = get_connection()?;
    let mut stmt = conn.prepare(
        "SELECT indexed_at FROM folder_index WHERE path = ?1"
    )?;
    let mut rows = stmt.query_map(params![folder_path], |row| row.get::<_, String>(0))?;
    match rows.next() {
        Some(Ok(ts)) => Ok(Some(ts)),
        Some(Err(e)) => Err(e),
        None => Ok(None),
    }
}

/// 批量更新文件夹的文件计数
pub fn update_folder_file_counts(source_folder: &str) -> Result<(), rusqlite::Error> {
    let conn = get_connection()?;
    conn.execute(
        "UPDATE folder_index SET file_count = (
            SELECT COUNT(*) FROM file_index
            WHERE file_index.folder_path = folder_index.path AND file_index.current_path IS NOT NULL
        ) WHERE source_folder = ?1",
        params![source_folder],
    )?;
    Ok(())
}

/// 判断文件夹是否已完成文件索引
/// 注意：scan_subfolders 只会在 folder_index 中创建文件夹记录，不会索引文件。
/// 因此仅凭 folder_index 有记录不能认为文件已被索引，还需检查 file_index。
pub fn is_folder_indexed(folder_path: &str) -> Result<bool, rusqlite::Error> {
    let conn = get_connection()?;

    // 先检查 folder_index 中是否存在
    let in_folder_index: bool = conn.query_row(
        "SELECT COUNT(*) > 0 FROM folder_index WHERE path = ?1",
        params![folder_path],
        |row| row.get(0),
    )?;

    if !in_folder_index {
        return Ok(false);
    }

    // folder_index 有记录，但可能只是 scan_subfolders 添加的（未扫描文件）
    // 需要确认 file_index 中确实有该文件夹的文件记录
    let has_file_records: bool = conn.query_row(
        "SELECT COUNT(*) > 0 FROM file_index WHERE folder_path = ?1",
        params![folder_path],
        |row| row.get(0),
    )?;

    Ok(has_file_records)
}

/// 清除指定源文件夹下的所有文件索引（用于强制重建）
pub fn clear_file_index_for_source(source_folder: &str) -> Result<u64, rusqlite::Error> {
    let conn = get_connection()?;
    // file_index.folder_path 是具体的子文件夹路径，以 source_folder 开头
    let affected = conn.execute(
        "DELETE FROM file_index WHERE folder_path = ?1 OR folder_path LIKE ?2",
        params![source_folder, format!("{}/%", source_folder)],
    )?;
    Ok(affected as u64)
}

/// 从数据库查找给定路径所属的源文件夹（最长前缀匹配）
pub fn find_source_folder(path: &str) -> Option<String> {
    let conn = get_connection().ok()?;
    let mut stmt = conn.prepare(
        "SELECT folder_path FROM source_folders ORDER BY LENGTH(folder_path) DESC"
    ).ok()?;
    let paths: Vec<String> = stmt.query_map([], |row| row.get(0)).ok()?
        .filter_map(|r| r.ok())
        .collect();

    for source in &paths {
        if path.starts_with(source.as_str()) {
            return Some(source.clone());
        }
    }
    None
}

/// 行映射函数
fn map_file_row(row: &rusqlite::Row) -> Result<IndexedFile, rusqlite::Error> {
    Ok(IndexedFile {
        uuid: row.get(0)?,
        fingerprint: row.get(1)?,
        current_path: row.get(2)?,
        folder_path: row.get(3)?,
        file_name: row.get(4)?,
        file_type: row.get(5)?,
        extension: row.get(6)?,
        file_size: row.get(7)?,
        created_at: row.get(8)?,
        modified_at: row.get(9)?,
        indexed_at: row.get(10)?,
        source_url: row.get(11)?,
    })
}
