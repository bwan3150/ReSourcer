// SQLite 数据库模块 - 统一管理所有数据存储
use rusqlite::{Connection, Result as SqliteResult};
use std::path::PathBuf;
use std::fs;

/// 获取配置目录路径 ~/.config/re-sourcer/
pub fn get_config_dir() -> PathBuf {
    let home = std::env::var("HOME")
        .or_else(|_| std::env::var("USERPROFILE"))
        .unwrap_or_else(|_| ".".to_string());

    PathBuf::from(home).join(".config").join("re-sourcer")
}

/// 获取数据库文件路径
pub fn get_db_path() -> PathBuf {
    get_config_dir().join("data.db")
}

/// 确保配置目录存在
pub fn ensure_config_dir() -> std::io::Result<()> {
    let config_dir = get_config_dir();
    if !config_dir.exists() {
        fs::create_dir_all(&config_dir)?;
    }
    Ok(())
}

/// 获取数据库连接
pub fn get_connection() -> SqliteResult<Connection> {
    let db_path = get_db_path();
    Connection::open(&db_path)
}

/// 初始化数据库（创建表结构，执行迁移）
pub fn init_db() -> SqliteResult<()> {
    ensure_config_dir().map_err(|e| {
        rusqlite::Error::InvalidPath(PathBuf::from(format!("无法创建配置目录: {}", e)))
    })?;

    let conn = get_connection()?;

    // 创建主配置表（单行，只存全局设置）
    conn.execute(
        "CREATE TABLE IF NOT EXISTS config (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            hidden_folders TEXT NOT NULL DEFAULT '[]',
            use_cookies INTEGER NOT NULL DEFAULT 1
        )",
        [],
    )?;

    // 创建源文件夹表
    conn.execute(
        "CREATE TABLE IF NOT EXISTS source_folders (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            folder_path TEXT NOT NULL UNIQUE,
            is_selected INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL
        )",
        [],
    )?;

    // 创建分类排序表（旧表，保留用于迁移）
    conn.execute(
        "CREATE TABLE IF NOT EXISTS category_order (
            source_folder TEXT PRIMARY KEY,
            order_list TEXT NOT NULL DEFAULT '[]'
        )",
        [],
    )?;

    // 创建子文件夹排序表（新表，支持任意层级文件夹排序）
    conn.execute(
        "CREATE TABLE IF NOT EXISTS subfolder_order (
            folder_path TEXT PRIMARY KEY,
            order_list TEXT NOT NULL DEFAULT '[]'
        )",
        [],
    )?;

    // 从 category_order 迁移数据到 subfolder_order
    conn.execute(
        "INSERT OR IGNORE INTO subfolder_order (folder_path, order_list)
         SELECT source_folder, order_list FROM category_order",
        [],
    )?;

    // 修复 .clip 文件分类：旧版 indexer 将 .clip 归为 "other"，应为 "image"
    conn.execute(
        "UPDATE file_index SET file_type = 'image' WHERE extension = 'clip' AND file_type = 'other'",
        [],
    ).ok(); // file_index 表可能尚未创建，忽略错误

    // 创建下载历史表
    conn.execute(
        "CREATE TABLE IF NOT EXISTS download_history (
            id TEXT PRIMARY KEY,
            url TEXT NOT NULL,
            platform TEXT NOT NULL,
            status TEXT NOT NULL,
            file_name TEXT,
            file_path TEXT,
            error TEXT,
            created_at TEXT NOT NULL
        )",
        [],
    )?;

    // 创建上传历史表
    conn.execute(
        "CREATE TABLE IF NOT EXISTS upload_history (
            id TEXT PRIMARY KEY,
            file_name TEXT NOT NULL,
            target_folder TEXT NOT NULL,
            status TEXT NOT NULL,
            file_size INTEGER NOT NULL,
            error TEXT,
            created_at TEXT NOT NULL
        )",
        [],
    )?;

    // 创建文件索引表
    conn.execute(
        "CREATE TABLE IF NOT EXISTS file_index (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            uuid TEXT UNIQUE NOT NULL,
            fingerprint TEXT NOT NULL,
            current_path TEXT UNIQUE,
            folder_path TEXT NOT NULL,
            file_name TEXT NOT NULL,
            file_type TEXT NOT NULL,
            extension TEXT NOT NULL,
            file_size INTEGER NOT NULL,
            created_at TEXT NOT NULL,
            modified_at TEXT NOT NULL,
            indexed_at TEXT NOT NULL
        )",
        [],
    )?;
    conn.execute("CREATE INDEX IF NOT EXISTS idx_file_folder ON file_index(folder_path)", [])?;
    conn.execute("CREATE INDEX IF NOT EXISTS idx_file_fingerprint ON file_index(fingerprint)", [])?;
    conn.execute("CREATE INDEX IF NOT EXISTS idx_file_modified ON file_index(modified_at)", [])?;

    // 创建文件夹索引表
    conn.execute(
        "CREATE TABLE IF NOT EXISTS folder_index (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            path TEXT UNIQUE NOT NULL,
            parent_path TEXT,
            source_folder TEXT NOT NULL,
            name TEXT NOT NULL,
            depth INTEGER NOT NULL DEFAULT 0,
            file_count INTEGER DEFAULT 0,
            indexed_at TEXT NOT NULL
        )",
        [],
    )?;
    conn.execute("CREATE INDEX IF NOT EXISTS idx_folder_parent ON folder_index(parent_path)", [])?;
    conn.execute("CREATE INDEX IF NOT EXISTS idx_folder_source ON folder_index(source_folder)", [])?;

    // 确保 config 表有初始行
    conn.execute(
        "INSERT OR IGNORE INTO config (id, hidden_folders, use_cookies) VALUES (1, '[]', 1)",
        [],
    )?;

    // 执行数据迁移（从旧 JSON 文件）
    migrate_from_json(&conn)?;

    Ok(())
}

/// 从旧 JSON 文件迁移数据到 SQLite
fn migrate_from_json(conn: &Connection) -> SqliteResult<()> {
    let config_dir = get_config_dir();

    // 检查是否已经迁移过（通过检查是否有源文件夹记录或者旧文件是否存在）
    let old_config_path = config_dir.join("config.json");
    let old_download_history_path = config_dir.join("download_history.json");
    let old_upload_history_path = config_dir.join("upload_history.json");
    let old_category_order_path = config_dir.join("category_order.json");

    // 迁移主配置
    if old_config_path.exists() {
        if let Ok(content) = fs::read_to_string(&old_config_path) {
            if let Ok(old_config) = serde_json::from_str::<serde_json::Value>(&content) {
                // 提取 hidden_folders 和 use_cookies
                let hidden_folders = old_config.get("hidden_folders")
                    .and_then(|v| serde_json::to_string(v).ok())
                    .unwrap_or_else(|| "[]".to_string());

                let use_cookies = old_config.get("use_cookies")
                    .and_then(|v| v.as_bool())
                    .unwrap_or(true);

                conn.execute(
                    "UPDATE config SET hidden_folders = ?1, use_cookies = ?2 WHERE id = 1",
                    rusqlite::params![hidden_folders, use_cookies as i32],
                )?;

                // 提取 source_folder（当前选中）
                if let Some(source_folder) = old_config.get("source_folder").and_then(|v| v.as_str()) {
                    if !source_folder.is_empty() {
                        let now = chrono::Utc::now().to_rfc3339();
                        // 插入当前选中的源文件夹
                        conn.execute(
                            "INSERT OR IGNORE INTO source_folders (folder_path, is_selected, created_at) VALUES (?1, 1, ?2)",
                            rusqlite::params![source_folder, now],
                        )?;
                    }
                }

                // 提取 backup_source_folders
                if let Some(backups) = old_config.get("backup_source_folders").and_then(|v| v.as_array()) {
                    let now = chrono::Utc::now().to_rfc3339();
                    for backup in backups {
                        if let Some(folder_path) = backup.as_str() {
                            conn.execute(
                                "INSERT OR IGNORE INTO source_folders (folder_path, is_selected, created_at) VALUES (?1, 0, ?2)",
                                rusqlite::params![folder_path, now],
                            )?;
                        }
                    }
                }
            }
        }
        // 删除旧配置文件
        let _ = fs::remove_file(&old_config_path);
    }

    // 迁移分类排序配置
    if old_category_order_path.exists() {
        if let Ok(content) = fs::read_to_string(&old_category_order_path) {
            if let Ok(old_config) = serde_json::from_str::<serde_json::Value>(&content) {
                if let Some(orders) = old_config.get("orders").and_then(|v| v.as_object()) {
                    for (source_folder, order_list) in orders {
                        if let Ok(order_json) = serde_json::to_string(order_list) {
                            conn.execute(
                                "INSERT OR REPLACE INTO category_order (source_folder, order_list) VALUES (?1, ?2)",
                                rusqlite::params![source_folder, order_json],
                            )?;
                            // 同时写入新表
                            conn.execute(
                                "INSERT OR REPLACE INTO subfolder_order (folder_path, order_list) VALUES (?1, ?2)",
                                rusqlite::params![source_folder, order_json],
                            )?;
                        }
                    }
                }
            }
        }
        // 删除旧文件
        let _ = fs::remove_file(&old_category_order_path);
    }

    // 迁移下载历史
    if old_download_history_path.exists() {
        if let Ok(content) = fs::read_to_string(&old_download_history_path) {
            if let Ok(history) = serde_json::from_str::<Vec<serde_json::Value>>(&content) {
                for item in history {
                    let id = item.get("id").and_then(|v| v.as_str()).unwrap_or_default();
                    let url = item.get("url").and_then(|v| v.as_str()).unwrap_or_default();
                    let platform = item.get("platform").and_then(|v| v.as_str()).unwrap_or_default();
                    let status = item.get("status").and_then(|v| v.as_str()).unwrap_or_default();
                    let file_name = item.get("file_name").and_then(|v| v.as_str());
                    let file_path = item.get("file_path").and_then(|v| v.as_str());
                    let error = item.get("error").and_then(|v| v.as_str());
                    let created_at = item.get("created_at").and_then(|v| v.as_str()).unwrap_or_default();

                    conn.execute(
                        "INSERT OR IGNORE INTO download_history (id, url, platform, status, file_name, file_path, error, created_at)
                         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
                        rusqlite::params![id, url, platform, status, file_name, file_path, error, created_at],
                    )?;
                }
            }
        }
        // 删除旧文件
        let _ = fs::remove_file(&old_download_history_path);
    }

    // 迁移上传历史
    if old_upload_history_path.exists() {
        if let Ok(content) = fs::read_to_string(&old_upload_history_path) {
            if let Ok(history) = serde_json::from_str::<Vec<serde_json::Value>>(&content) {
                for item in history {
                    let id = item.get("id").and_then(|v| v.as_str()).unwrap_or_default();
                    let file_name = item.get("file_name").and_then(|v| v.as_str()).unwrap_or_default();
                    let target_folder = item.get("target_folder").and_then(|v| v.as_str()).unwrap_or_default();
                    let status = item.get("status").and_then(|v| v.as_str()).unwrap_or_default();
                    let file_size = item.get("file_size").and_then(|v| v.as_u64()).unwrap_or(0);
                    let error = item.get("error").and_then(|v| v.as_str());
                    let created_at = item.get("created_at").and_then(|v| v.as_str()).unwrap_or_default();

                    conn.execute(
                        "INSERT OR IGNORE INTO upload_history (id, file_name, target_folder, status, file_size, error, created_at)
                         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
                        rusqlite::params![id, file_name, target_folder, status, file_size as i64, error, created_at],
                    )?;
                }
            }
        }
        // 删除旧文件
        let _ = fs::remove_file(&old_upload_history_path);
    }

    Ok(())
}
