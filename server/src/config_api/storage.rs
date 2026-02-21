// 配置存储功能 - 使用 SQLite 数据库
use super::models::{AppState, Preset};
use crate::database;
use std::path::PathBuf;
use std::io;

/// 获取配置文件目录 ~/.config/re-sourcer/（仍需要用于 secret.json 和 credentials）
#[allow(dead_code)]
pub fn get_config_dir() -> PathBuf {
    database::get_config_dir()
}

/// 读取配置（从 SQLite 数据库）
pub fn load_config() -> io::Result<AppState> {
    let conn = database::get_connection()
        .map_err(|e| io::Error::new(io::ErrorKind::Other, format!("数据库连接失败: {}", e)))?;

    // 读取 config 表
    let (hidden_folders_json, use_cookies): (String, i32) = conn.query_row(
        "SELECT hidden_folders, use_cookies FROM config WHERE id = 1",
        [],
        |row| Ok((row.get(0)?, row.get(1)?)),
    ).map_err(|e| io::Error::new(io::ErrorKind::Other, format!("读取配置失败: {}", e)))?;

    let hidden_folders: Vec<String> = serde_json::from_str(&hidden_folders_json)
        .unwrap_or_default();

    // 读取当前选中的源文件夹
    let source_folder: String = conn.query_row(
        "SELECT folder_path FROM source_folders WHERE is_selected = 1 LIMIT 1",
        [],
        |row| row.get(0),
    ).unwrap_or_default();

    // 读取备用源文件夹列表
    let mut stmt = conn.prepare(
        "SELECT folder_path FROM source_folders WHERE is_selected = 0 ORDER BY created_at DESC"
    ).map_err(|e| io::Error::new(io::ErrorKind::Other, format!("准备查询失败: {}", e)))?;

    let backup_source_folders: Vec<String> = stmt.query_map([], |row| row.get(0))
        .map_err(|e| io::Error::new(io::ErrorKind::Other, format!("查询备用文件夹失败: {}", e)))?
        .filter_map(|r| r.ok())
        .collect();

    Ok(AppState {
        source_folder,
        hidden_folders,
        backup_source_folders,
        use_cookies: use_cookies != 0,
    })
}

/// 保存配置（写入 SQLite 数据库）
pub fn save_config(state: &AppState) -> io::Result<()> {
    let conn = database::get_connection()
        .map_err(|e| io::Error::new(io::ErrorKind::Other, format!("数据库连接失败: {}", e)))?;

    // 更新 config 表
    let hidden_folders_json = serde_json::to_string(&state.hidden_folders)
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;

    conn.execute(
        "UPDATE config SET hidden_folders = ?1, use_cookies = ?2 WHERE id = 1",
        rusqlite::params![hidden_folders_json, state.use_cookies as i32],
    ).map_err(|e| io::Error::new(io::ErrorKind::Other, format!("更新配置失败: {}", e)))?;

    // 更新源文件夹
    if !state.source_folder.is_empty() {
        // 先取消所有选中状态
        conn.execute("UPDATE source_folders SET is_selected = 0", [])
            .map_err(|e| io::Error::new(io::ErrorKind::Other, format!("更新源文件夹失败: {}", e)))?;

        // 插入或更新当前选中的源文件夹
        let now = chrono::Utc::now().to_rfc3339();
        conn.execute(
            "INSERT INTO source_folders (folder_path, is_selected, created_at)
             VALUES (?1, 1, ?2)
             ON CONFLICT(folder_path) DO UPDATE SET is_selected = 1",
            rusqlite::params![state.source_folder, now],
        ).map_err(|e| io::Error::new(io::ErrorKind::Other, format!("插入源文件夹失败: {}", e)))?;
    }

    Ok(())
}

/// 默认应用状态
pub fn get_default_state() -> AppState {
    AppState {
        source_folder: String::new(),
        hidden_folders: Vec::new(),
        backup_source_folders: Vec::new(),
        use_cookies: true,
    }
}


/// 获取指定文件夹的子文件夹排序
pub fn get_subfolder_order(folder_path: &str) -> Vec<String> {
    let conn = match database::get_connection() {
        Ok(c) => c,
        Err(_) => return Vec::new(),
    };

    conn.query_row(
        "SELECT order_list FROM subfolder_order WHERE folder_path = ?1",
        rusqlite::params![folder_path],
        |row| {
            let order_list_json: String = row.get(0)?;
            Ok(serde_json::from_str::<Vec<String>>(&order_list_json).unwrap_or_default())
        },
    ).unwrap_or_default()
}

/// 保存指定文件夹的子文件夹排序
pub fn set_subfolder_order(folder_path: &str, order: Vec<String>) -> io::Result<()> {
    let conn = database::get_connection()
        .map_err(|e| io::Error::new(io::ErrorKind::Other, format!("数据库连接失败: {}", e)))?;

    let order_json = serde_json::to_string(&order)
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;

    conn.execute(
        "INSERT OR REPLACE INTO subfolder_order (folder_path, order_list) VALUES (?1, ?2)",
        rusqlite::params![folder_path, order_json],
    ).map_err(|e| io::Error::new(io::ErrorKind::Other, format!("保存子文件夹排序失败: {}", e)))?;

    Ok(())
}

// ==================== 源文件夹操作 ====================

/// 列出所有源文件夹
pub fn list_source_folders() -> io::Result<Vec<(String, bool)>> {
    let conn = database::get_connection()
        .map_err(|e| io::Error::new(io::ErrorKind::Other, format!("数据库连接失败: {}", e)))?;

    let mut stmt = conn.prepare(
        "SELECT folder_path, is_selected FROM source_folders ORDER BY is_selected DESC, created_at DESC"
    ).map_err(|e| io::Error::new(io::ErrorKind::Other, format!("准备查询失败: {}", e)))?;

    let folders: Vec<(String, bool)> = stmt.query_map([], |row| {
        let path: String = row.get(0)?;
        let is_selected: i32 = row.get(1)?;
        Ok((path, is_selected != 0))
    })
    .map_err(|e| io::Error::new(io::ErrorKind::Other, format!("查询源文件夹失败: {}", e)))?
    .filter_map(|r| r.ok())
    .collect();

    Ok(folders)
}

/// 获取当前选中的源文件夹
pub fn get_selected_source_folder() -> io::Result<Option<String>> {
    let conn = database::get_connection()
        .map_err(|e| io::Error::new(io::ErrorKind::Other, format!("数据库连接失败: {}", e)))?;

    let result = conn.query_row(
        "SELECT folder_path FROM source_folders WHERE is_selected = 1 LIMIT 1",
        [],
        |row| row.get(0),
    );

    match result {
        Ok(path) => Ok(Some(path)),
        Err(rusqlite::Error::QueryReturnedNoRows) => Ok(None),
        Err(e) => Err(io::Error::new(io::ErrorKind::Other, format!("查询选中文件夹失败: {}", e))),
    }
}

/// 添加源文件夹
pub fn add_source_folder(folder_path: &str) -> io::Result<()> {
    let conn = database::get_connection()
        .map_err(|e| io::Error::new(io::ErrorKind::Other, format!("数据库连接失败: {}", e)))?;

    let now = chrono::Utc::now().to_rfc3339();

    // 检查是否已存在
    let exists: bool = conn.query_row(
        "SELECT COUNT(*) > 0 FROM source_folders WHERE folder_path = ?1",
        rusqlite::params![folder_path],
        |row| row.get(0),
    ).unwrap_or(false);

    if exists {
        return Err(io::Error::new(io::ErrorKind::AlreadyExists, "源文件夹已存在"));
    }

    // 检查是否有选中的文件夹，如果没有则将新添加的设为选中
    let has_selected: bool = conn.query_row(
        "SELECT COUNT(*) > 0 FROM source_folders WHERE is_selected = 1",
        [],
        |row| row.get(0),
    ).unwrap_or(false);

    let is_selected = if has_selected { 0 } else { 1 };

    conn.execute(
        "INSERT INTO source_folders (folder_path, is_selected, created_at) VALUES (?1, ?2, ?3)",
        rusqlite::params![folder_path, is_selected, now],
    ).map_err(|e| io::Error::new(io::ErrorKind::Other, format!("添加源文件夹失败: {}", e)))?;

    Ok(())
}

/// 删除源文件夹
pub fn remove_source_folder(folder_path: &str) -> io::Result<()> {
    let conn = database::get_connection()
        .map_err(|e| io::Error::new(io::ErrorKind::Other, format!("数据库连接失败: {}", e)))?;

    // 检查是否是当前选中的文件夹
    let is_selected: bool = conn.query_row(
        "SELECT is_selected = 1 FROM source_folders WHERE folder_path = ?1",
        rusqlite::params![folder_path],
        |row| row.get(0),
    ).unwrap_or(false);

    conn.execute(
        "DELETE FROM source_folders WHERE folder_path = ?1",
        rusqlite::params![folder_path],
    ).map_err(|e| io::Error::new(io::ErrorKind::Other, format!("删除源文件夹失败: {}", e)))?;

    // 如果删除的是选中的文件夹，自动选中第一个
    if is_selected {
        conn.execute(
            "UPDATE source_folders SET is_selected = 1 WHERE id = (SELECT MIN(id) FROM source_folders)",
            [],
        ).ok();
    }

    Ok(())
}

/// 切换选中的源文件夹
pub fn select_source_folder(folder_path: &str) -> io::Result<()> {
    let conn = database::get_connection()
        .map_err(|e| io::Error::new(io::ErrorKind::Other, format!("数据库连接失败: {}", e)))?;

    // 先取消所有选中状态
    conn.execute("UPDATE source_folders SET is_selected = 0", [])
        .map_err(|e| io::Error::new(io::ErrorKind::Other, format!("更新源文件夹失败: {}", e)))?;

    // 设置目标文件夹为选中
    let affected = conn.execute(
        "UPDATE source_folders SET is_selected = 1 WHERE folder_path = ?1",
        rusqlite::params![folder_path],
    ).map_err(|e| io::Error::new(io::ErrorKind::Other, format!("选中源文件夹失败: {}", e)))?;

    if affected == 0 {
        return Err(io::Error::new(io::ErrorKind::NotFound, "源文件夹不存在"));
    }

    Ok(())
}

/// 加载预设列表 - 从嵌入的 config/presets.json 读取
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
