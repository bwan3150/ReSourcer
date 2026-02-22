// 文件系统扫描 + 移动检测
use std::path::Path;
use std::fs;
use chrono::{DateTime, Utc};
use crate::database::get_connection;
use crate::preview::models::*;
use rusqlite::params;
use super::models::{IndexedFile, IndexedFolder};
use super::storage;

/// 扫描结果
pub struct ScanResult {
    pub scanned_files: u64,
    pub scanned_folders: u64,
}

/// 判断扩展名对应的文件类型（未知扩展名归为 "other"，确保所有文件都被索引）
fn classify_extension(ext: &str) -> String {
    let ext_lower = ext.to_lowercase();
    if IMAGE_EXTENSIONS.contains(&ext_lower.as_str()) {
        "image".to_string()
    } else if ext_lower == GIF_EXTENSION {
        "gif".to_string()
    } else if VIDEO_EXTENSIONS.contains(&ext_lower.as_str()) {
        "video".to_string()
    } else if AUDIO_EXTENSIONS.contains(&ext_lower.as_str()) {
        "audio".to_string()
    } else if ext_lower == PDF_EXTENSION {
        "pdf".to_string()
    } else if ext_lower == CLIP_EXTENSION {
        "image".to_string()
    } else {
        "other".to_string()
    }
}

/// 判断文件夹是否需要重新扫描
pub fn needs_rescan(folder_path: &str) -> bool {
    let indexed_at = match storage::get_folder_indexed_at(folder_path) {
        Ok(Some(ts)) => ts,
        _ => return true,
    };

    let indexed_time = match DateTime::parse_from_rfc3339(&indexed_at) {
        Ok(t) => t.with_timezone(&Utc),
        Err(_) => return true,
    };

    let path = Path::new(folder_path);
    let mtime = match fs::metadata(path).and_then(|m| m.modified()) {
        Ok(t) => DateTime::<Utc>::from(t),
        Err(_) => return true,
    };

    mtime > indexed_time
}

/// 单文件夹快速扫描（惰性索引核心）
/// - 不计算指纹（指纹是首次打开慢的元凶：5000 文件 × 128KB 读取 = 640MB IO）
/// - 不构建返回值（handler 直接查 DB，Vec<IndexedFile> 从未被使用）
/// - skip_mark_missing: 后台增量扫描时为 true，避免竞态
pub fn scan_folder(folder_path: &str, source_folder: &str, skip_mark_missing: bool) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let dir_path = Path::new(folder_path);
    if !dir_path.is_dir() {
        return Err(format!("路径不是目录: {}", folder_path).into());
    }

    let now = Utc::now().to_rfc3339();

    // 一次性查出该文件夹所有已索引文件的 mtime，用于跳过未变化的文件
    let indexed_map = storage::get_indexed_files_for_folder(folder_path)
        .unwrap_or_default();

    // 收集需要 upsert 的文件和所有存在的路径
    struct NewFile {
        path_str: String,
        ext: String,
        file_type: String,
        file_name: String,
        file_size: i64,
        created_at: String,
        modified_at: String,
    }

    let mut new_files: Vec<NewFile> = Vec::new();
    let mut existing_paths: Vec<String> = Vec::new();

    let entries = fs::read_dir(dir_path)?;
    for entry in entries.flatten() {
        let entry_path = entry.path();
        if entry_path.is_dir() {
            continue;
        }

        let path_str = entry_path.to_string_lossy().to_string();
        existing_paths.push(path_str.clone());

        let metadata = match fs::metadata(&entry_path) {
            Ok(m) => m,
            Err(_) => continue,
        };

        let modified_at = metadata.modified()
            .map(|t| DateTime::<Utc>::from(t).to_rfc3339())
            .unwrap_or_else(|_| now.clone());

        // mtime 未变 → 跳过（不需要读文件内容、不需要写 DB）
        if let Some(existing) = indexed_map.get(&path_str) {
            if existing.modified_at == modified_at {
                continue;
            }
        }

        let ext = entry_path.extension()
            .and_then(|e| e.to_str())
            .unwrap_or("")
            .to_lowercase();

        let created_at = metadata.created()
            .map(|t| DateTime::<Utc>::from(t).to_rfc3339())
            .unwrap_or_else(|_| now.clone());

        let file_name = entry_path.file_name()
            .unwrap_or_default()
            .to_string_lossy()
            .to_string();

        new_files.push(NewFile {
            file_type: classify_extension(&ext),
            path_str,
            ext,
            file_name,
            file_size: metadata.len() as i64,
            created_at,
            modified_at,
        });
    }

    // 在单个事务中批量写入（只写新增/变更的文件）
    let conn = get_connection()?;
    let tx = conn.unchecked_transaction()?;

    for file in &new_files {
        // fast_upsert: ON CONFLICT(current_path) 保留已有 uuid 和 fingerprint
        let indexed_file = IndexedFile {
            uuid: uuid::Uuid::new_v4().to_string(),
            fingerprint: String::new(), // 空指纹，不计算
            current_path: Some(file.path_str.clone()),
            folder_path: folder_path.to_string(),
            file_name: file.file_name.clone(),
            file_type: file.file_type.clone(),
            extension: file.ext.clone(),
            file_size: file.file_size,
            created_at: file.created_at.clone(),
            modified_at: file.modified_at.clone(),
            indexed_at: now.clone(),
            source_url: None,
        };

        if let Err(e) = storage::fast_upsert_file_with_conn(&tx, &indexed_file) {
            eprintln!("索引文件失败: {} - {}", file.path_str, e);
        }
    }

    if !skip_mark_missing {
        if let Err(e) = storage::mark_missing_with_conn(&tx, folder_path, &existing_paths) {
            eprintln!("标记缺失文件失败: {}", e);
        }
    }

    // 更新文件夹索引
    let depth = if folder_path == source_folder {
        0
    } else {
        Path::new(folder_path).strip_prefix(Path::new(source_folder))
            .map(|rel| rel.components().count() as i32)
            .unwrap_or(0)
    };

    let folder_name = Path::new(folder_path)
        .file_name()
        .unwrap_or_default()
        .to_string_lossy()
        .to_string();

    let parent_path = if folder_path == source_folder {
        None
    } else {
        Path::new(folder_path).parent()
            .map(|p| p.to_string_lossy().to_string())
    };

    let folder = IndexedFolder {
        path: folder_path.to_string(),
        parent_path,
        source_folder: source_folder.to_string(),
        name: folder_name,
        depth,
        file_count: existing_paths.len() as i64,
        subfolder_count: 0,
        indexed_at: now,
    };
    storage::upsert_folder_with_conn(&tx, &folder)?;

    tx.commit()?;
    Ok(())
}

/// 全量递归扫描源文件夹
/// 使用单连接 + 事务分批提交，避免几十万次 get_connection() 调用
pub fn scan_source_folder(source_folder: &str) -> Result<ScanResult, Box<dyn std::error::Error + Send + Sync>> {
    use walkdir::WalkDir;

    let source_path = Path::new(source_folder);
    if !source_path.is_dir() {
        return Err(format!("源文件夹不存在: {}", source_folder).into());
    }

    // 读取 ignored_folders 配置
    let ignored_folders = crate::config_api::storage::load_config()
        .map(|c| c.ignored_folders)
        .unwrap_or_default();

    let now = Utc::now().to_rfc3339();
    let mut scanned_files: u64 = 0;
    let mut scanned_folders: u64 = 0;

    // 单连接复用，避免每个文件都 get_connection()
    let conn = get_connection()?;
    let mut batch_count: u64 = 0;

    // 开启第一个事务
    conn.execute_batch("BEGIN")?;

    // 递归遍历
    for entry in WalkDir::new(source_folder).into_iter().filter_entry(|e| {
        // WalkDir filter_entry：返回 false 会跳过该目录及其所有子目录
        if let Some(name) = e.file_name().to_str() {
            if e.file_type().is_dir() {
                // 跳过隐藏目录
                if name.starts_with('.') {
                    return false;
                }
                // 跳过 ignored_folders
                if ignored_folders.iter().any(|ig| ig == name) {
                    return false;
                }
            }
        }
        true
    }).filter_map(|e| e.ok()) {
        let entry_path = entry.path();

        if entry_path.is_dir() {
            let dir_str = entry_path.to_string_lossy().to_string();
            let depth = entry_path.strip_prefix(source_path)
                .map(|rel| rel.components().count() as i32)
                .unwrap_or(0);

            let folder_name = entry_path.file_name()
                .unwrap_or_default()
                .to_string_lossy()
                .to_string();

            let parent_path = if dir_str == source_folder {
                None
            } else {
                entry_path.parent()
                    .map(|p| p.to_string_lossy().to_string())
            };

            let folder = IndexedFolder {
                path: dir_str,
                parent_path,
                source_folder: source_folder.to_string(),
                name: folder_name,
                depth,
                file_count: 0, // 后面批量更新
                subfolder_count: 0,
                indexed_at: now.clone(),
            };
            let _ = storage::upsert_folder_with_conn(&conn, &folder);
            scanned_folders += 1;
        } else {
            // 文件
            let ext = entry_path.extension()
                .and_then(|e| e.to_str())
                .unwrap_or("")
                .to_lowercase();

            let file_type = classify_extension(&ext);

            let path_str = entry_path.to_string_lossy().to_string();
            let folder_str = entry_path.parent()
                .map(|p| p.to_string_lossy().to_string())
                .unwrap_or_default();

            let metadata = match fs::metadata(entry_path) {
                Ok(m) => m,
                Err(_) => continue,
            };

            let modified_at = metadata.modified()
                .map(|t| DateTime::<Utc>::from(t).to_rfc3339())
                .unwrap_or_else(|_| now.clone());

            // 使用同一连接检查 mtime
            let mut stmt = conn.prepare_cached(
                "SELECT modified_at FROM file_index WHERE current_path = ?1"
            )?;
            let existing_mtime: Option<String> = stmt.query_row(params![path_str], |row| row.get(0)).ok();
            if existing_mtime.as_deref() == Some(&modified_at) {
                scanned_files += 1;
                continue;
            }

            let created_at = metadata.created()
                .map(|t| DateTime::<Utc>::from(t).to_rfc3339())
                .unwrap_or_else(|_| now.clone());

            let file_name = entry_path.file_name()
                .unwrap_or_default()
                .to_string_lossy()
                .to_string();

            // 不计算指纹 — 全量扫描的目的是快速建索引，指纹可以后续按需计算
            let indexed_file = IndexedFile {
                uuid: uuid::Uuid::new_v4().to_string(),
                fingerprint: String::new(),
                current_path: Some(path_str),
                folder_path: folder_str,
                file_name,
                file_type,
                extension: ext,
                file_size: metadata.len() as i64,
                created_at,
                modified_at,
                indexed_at: now.clone(),
                source_url: None,
            };

            let _ = storage::fast_upsert_file_with_conn(&conn, &indexed_file);
            scanned_files += 1;
        }

        // 每 500 条提交一次事务，释放写锁让其他操作有机会执行
        batch_count += 1;
        if batch_count >= 500 {
            conn.execute_batch("COMMIT; BEGIN")?;
            batch_count = 0;
        }
    }

    // 提交最后一批
    conn.execute_batch("COMMIT")?;

    Ok(ScanResult {
        scanned_files,
        scanned_folders,
    })
}

/// 单文件索引：上传/下载完成后立即将文件编入索引，避免扫描整个目录
/// source_url: 下载来源 URL（仅下载任务传入，上传和扫描传 None）
pub fn index_single_file(file_path: &str, source_folder: &str, source_url: Option<&str>) -> Result<IndexedFile, Box<dyn std::error::Error + Send + Sync>> {
    let entry_path = Path::new(file_path);
    if !entry_path.is_file() {
        return Err(format!("文件不存在: {}", file_path).into());
    }

    let now = Utc::now().to_rfc3339();

    let ext = entry_path.extension()
        .and_then(|e| e.to_str())
        .unwrap_or("")
        .to_lowercase();

    let file_type = classify_extension(&ext);

    let metadata = fs::metadata(entry_path)?;

    let modified_at = metadata.modified()
        .map(|t| DateTime::<Utc>::from(t).to_rfc3339())
        .unwrap_or_else(|_| now.clone());

    let created_at = metadata.created()
        .map(|t| DateTime::<Utc>::from(t).to_rfc3339())
        .unwrap_or_else(|_| now.clone());

    // 如果已索引且 mtime 未变，直接返回
    if let Ok(Some(existing)) = storage::get_file_by_path(file_path) {
        if existing.modified_at == modified_at {
            return Ok(existing);
        }
    }

    let file_name = entry_path.file_name()
        .unwrap_or_default()
        .to_string_lossy()
        .to_string();

    let folder_path = entry_path.parent()
        .map(|p| p.to_string_lossy().to_string())
        .unwrap_or_default();

    let indexed_file = IndexedFile {
        uuid: uuid::Uuid::new_v4().to_string(),
        fingerprint: String::new(),
        current_path: Some(file_path.to_string()),
        folder_path: folder_path.clone(),
        file_name,
        file_type,
        extension: ext,
        file_size: metadata.len() as i64,
        created_at,
        modified_at,
        indexed_at: now.clone(),
        source_url: source_url.map(|s| s.to_string()),
    };

    storage::upsert_file(&indexed_file)?;

    // 确保文件所在文件夹也在 folder_index 中
    let depth = if folder_path == source_folder {
        0
    } else {
        let source_path = Path::new(source_folder);
        Path::new(&folder_path).strip_prefix(source_path)
            .map(|rel| rel.components().count() as i32)
            .unwrap_or(0)
    };

    let folder_name = Path::new(&folder_path)
        .file_name()
        .unwrap_or_default()
        .to_string_lossy()
        .to_string();

    let parent_path = if folder_path == source_folder {
        None
    } else {
        Path::new(&folder_path).parent()
            .map(|p| p.to_string_lossy().to_string())
    };

    let folder = IndexedFolder {
        path: folder_path,
        parent_path,
        source_folder: source_folder.to_string(),
        name: folder_name,
        depth,
        file_count: 0, // 不精确更新，下次全量扫描会修正
        subfolder_count: 0,
        indexed_at: now,
    };
    let _ = storage::upsert_folder(&folder);

    Ok(indexed_file)
}
