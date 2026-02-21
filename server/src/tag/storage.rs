// 标签模块 - SQLite CRUD 操作
use crate::database::get_connection;
use super::models::Tag;
use std::collections::HashMap;

/// 从数据库行映射为 Tag
fn map_tag_row(row: &rusqlite::Row) -> Result<Tag, rusqlite::Error> {
    Ok(Tag {
        id: row.get(0)?,
        source_folder: row.get(1)?,
        name: row.get(2)?,
        color: row.get(3)?,
        created_at: row.get(4)?,
    })
}

/// 创建标签
pub fn create_tag(source_folder: &str, name: &str, color: &str) -> Result<Tag, rusqlite::Error> {
    let conn = get_connection()?;
    let now = chrono::Utc::now().to_rfc3339();

    conn.execute(
        "INSERT INTO tags (source_folder, name, color, created_at) VALUES (?1, ?2, ?3, ?4)",
        rusqlite::params![source_folder, name, color, now],
    )?;

    let id = conn.last_insert_rowid();
    Ok(Tag {
        id,
        source_folder: source_folder.to_string(),
        name: name.to_string(),
        color: color.to_string(),
        created_at: now,
    })
}

/// 更新标签
pub fn update_tag(id: i64, name: Option<&str>, color: Option<&str>) -> Result<(), rusqlite::Error> {
    let conn = get_connection()?;

    if let Some(name) = name {
        conn.execute("UPDATE tags SET name = ?1 WHERE id = ?2", rusqlite::params![name, id])?;
    }
    if let Some(color) = color {
        conn.execute("UPDATE tags SET color = ?1 WHERE id = ?2", rusqlite::params![color, id])?;
    }

    Ok(())
}

/// 删除标签（级联删除 file_tags 关联）
pub fn delete_tag(id: i64) -> Result<(), rusqlite::Error> {
    let conn = get_connection()?;
    conn.execute("DELETE FROM file_tags WHERE tag_id = ?1", rusqlite::params![id])?;
    conn.execute("DELETE FROM tags WHERE id = ?1", rusqlite::params![id])?;
    Ok(())
}

/// 获取源文件夹的所有标签
pub fn get_tags(source_folder: &str) -> Result<Vec<Tag>, rusqlite::Error> {
    let conn = get_connection()?;
    let mut stmt = conn.prepare(
        "SELECT id, source_folder, name, color, created_at FROM tags WHERE source_folder = ?1 ORDER BY name ASC"
    )?;

    let tags = stmt.query_map(rusqlite::params![source_folder], map_tag_row)?
        .collect::<Result<Vec<_>, _>>()?;

    Ok(tags)
}

/// 设置文件的标签（全量替换）
pub fn set_file_tags(file_uuid: &str, tag_ids: &[i64]) -> Result<(), rusqlite::Error> {
    let conn = get_connection()?;

    // 先删除旧关联
    conn.execute("DELETE FROM file_tags WHERE file_uuid = ?1", rusqlite::params![file_uuid])?;

    // 插入新关联
    let now = chrono::Utc::now().to_rfc3339();
    for tag_id in tag_ids {
        conn.execute(
            "INSERT INTO file_tags (file_uuid, tag_id, created_at) VALUES (?1, ?2, ?3)",
            rusqlite::params![file_uuid, tag_id, now],
        )?;
    }

    Ok(())
}

/// 获取文件的标签
pub fn get_file_tags(file_uuid: &str) -> Result<Vec<Tag>, rusqlite::Error> {
    let conn = get_connection()?;
    let mut stmt = conn.prepare(
        "SELECT t.id, t.source_folder, t.name, t.color, t.created_at
         FROM tags t
         INNER JOIN file_tags ft ON t.id = ft.tag_id
         WHERE ft.file_uuid = ?1
         ORDER BY t.name ASC"
    )?;

    let tags = stmt.query_map(rusqlite::params![file_uuid], map_tag_row)?
        .collect::<Result<Vec<_>, _>>()?;

    Ok(tags)
}

/// 批量获取多个文件的标签
pub fn get_files_tags(file_uuids: &[String]) -> Result<HashMap<String, Vec<Tag>>, rusqlite::Error> {
    if file_uuids.is_empty() {
        return Ok(HashMap::new());
    }

    let conn = get_connection()?;

    // 构建动态占位符
    let placeholders: Vec<String> = file_uuids.iter().enumerate()
        .map(|(i, _)| format!("?{}", i + 1))
        .collect();
    let placeholders_str = placeholders.join(", ");

    let query = format!(
        "SELECT ft.file_uuid, t.id, t.source_folder, t.name, t.color, t.created_at
         FROM tags t
         INNER JOIN file_tags ft ON t.id = ft.tag_id
         WHERE ft.file_uuid IN ({})
         ORDER BY t.name ASC",
        placeholders_str
    );

    let mut stmt = conn.prepare(&query)?;

    let params: Vec<&dyn rusqlite::types::ToSql> = file_uuids.iter()
        .map(|s| s as &dyn rusqlite::types::ToSql)
        .collect();

    let rows = stmt.query_map(params.as_slice(), |row| {
        let file_uuid: String = row.get(0)?;
        let tag = Tag {
            id: row.get(1)?,
            source_folder: row.get(2)?,
            name: row.get(3)?,
            color: row.get(4)?,
            created_at: row.get(5)?,
        };
        Ok((file_uuid, tag))
    })?;

    let mut result: HashMap<String, Vec<Tag>> = HashMap::new();
    for row in rows {
        let (file_uuid, tag) = row?;
        result.entry(file_uuid).or_default().push(tag);
    }

    Ok(result)
}
