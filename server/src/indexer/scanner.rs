// 文件系统扫描 + 移动检测
use std::path::Path;
use std::fs;
use chrono::{DateTime, Utc};
use crate::preview::models::*;
use super::models::{IndexedFile, IndexedFolder};
use super::fingerprint::compute_fingerprint;
use super::storage;

/// 扫描结果
pub struct ScanResult {
    pub scanned_files: u64,
    pub scanned_folders: u64,
}

/// 判断扩展名对应的文件类型
fn classify_extension(ext: &str) -> Option<String> {
    let ext_lower = ext.to_lowercase();
    if IMAGE_EXTENSIONS.contains(&ext_lower.as_str()) {
        Some("image".to_string())
    } else if ext_lower == GIF_EXTENSION {
        Some("gif".to_string())
    } else if VIDEO_EXTENSIONS.contains(&ext_lower.as_str()) {
        Some("video".to_string())
    } else if AUDIO_EXTENSIONS.contains(&ext_lower.as_str()) {
        Some("audio".to_string())
    } else if ext_lower == PDF_EXTENSION {
        Some("pdf".to_string())
    } else if ext_lower == CLIP_EXTENSION {
        Some("image".to_string())
    } else {
        None // 不支持的文件类型，跳过
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

/// 单文件夹扫描（惰性索引核心）
pub fn scan_folder(folder_path: &str, source_folder: &str) -> Result<Vec<IndexedFile>, Box<dyn std::error::Error + Send + Sync>> {
    let dir_path = Path::new(folder_path);
    if !dir_path.is_dir() {
        return Err(format!("路径不是目录: {}", folder_path).into());
    }

    let now = Utc::now().to_rfc3339();
    let mut indexed_files = Vec::new();
    let mut existing_paths = Vec::new();

    // 读取目录中的所有文件
    let entries = fs::read_dir(dir_path)?;
    for entry in entries.flatten() {
        let entry_path = entry.path();

        // 跳过目录和隐藏文件
        if entry_path.is_dir() {
            continue;
        }
        if let Some(name) = entry_path.file_name().and_then(|n| n.to_str()) {
            if name.starts_with('.') {
                continue;
            }
        }

        let ext = entry_path.extension()
            .and_then(|e| e.to_str())
            .unwrap_or("")
            .to_lowercase();

        // 只索引支持的媒体文件
        let file_type = match classify_extension(&ext) {
            Some(ft) => ft,
            None => continue,
        };

        let path_str = entry_path.to_string_lossy().to_string();
        existing_paths.push(path_str.clone());

        let metadata = match fs::metadata(&entry_path) {
            Ok(m) => m,
            Err(_) => continue,
        };

        let modified_at = metadata.modified()
            .map(|t| DateTime::<Utc>::from(t).to_rfc3339())
            .unwrap_or_else(|_| now.clone());

        let created_at = metadata.created()
            .map(|t| DateTime::<Utc>::from(t).to_rfc3339())
            .unwrap_or_else(|_| now.clone());

        // 检查是否已索引且 mtime 未变
        if let Ok(Some(existing)) = storage::get_file_by_path(&path_str) {
            if existing.modified_at == modified_at {
                indexed_files.push(existing);
                continue;
            }
        }

        // 新文件或已修改 → 计算指纹
        let fingerprint = match compute_fingerprint(&entry_path) {
            Ok(fp) => fp,
            Err(_) => continue,
        };

        let file_name = entry_path.file_name()
            .unwrap_or_default()
            .to_string_lossy()
            .to_string();

        // 检查是否是移动过来的文件（指纹匹配的孤儿）
        let file_uuid = if let Ok(Some(orphan)) = storage::find_orphan_by_fingerprint(&fingerprint) {
            // 文件被移动了，复用旧 UUID
            orphan.uuid
        } else {
            uuid::Uuid::new_v4().to_string()
        };

        let indexed_file = IndexedFile {
            uuid: file_uuid,
            fingerprint,
            current_path: Some(path_str),
            folder_path: folder_path.to_string(),
            file_name,
            file_type,
            extension: ext,
            file_size: metadata.len() as i64,
            created_at,
            modified_at,
            indexed_at: now.clone(),
        };

        if let Err(e) = storage::upsert_file(&indexed_file) {
            eprintln!("索引文件失败: {} - {}", indexed_file.current_path.as_deref().unwrap_or(""), e);
            continue;
        }

        indexed_files.push(indexed_file);
    }

    // 标记已不存在的文件
    if let Err(e) = storage::mark_missing(folder_path, &existing_paths) {
        eprintln!("标记缺失文件失败: {}", e);
    }

    // 计算文件夹深度
    let depth = if folder_path == source_folder {
        0
    } else {
        let source_path = Path::new(source_folder);
        Path::new(folder_path).strip_prefix(source_path)
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

    // 更新文件夹索引
    let folder = IndexedFolder {
        path: folder_path.to_string(),
        parent_path,
        source_folder: source_folder.to_string(),
        name: folder_name,
        depth,
        file_count: existing_paths.len() as i64,
        indexed_at: now,
    };
    if let Err(e) = storage::upsert_folder(&folder) {
        eprintln!("更新文件夹索引失败: {}", e);
    }

    Ok(indexed_files)
}

/// 全量递归扫描源文件夹
pub fn scan_source_folder(source_folder: &str) -> Result<ScanResult, Box<dyn std::error::Error + Send + Sync>> {
    use walkdir::WalkDir;

    let source_path = Path::new(source_folder);
    if !source_path.is_dir() {
        return Err(format!("源文件夹不存在: {}", source_folder).into());
    }

    let now = Utc::now().to_rfc3339();
    let mut scanned_files: u64 = 0;
    let mut scanned_folders: u64 = 0;

    // 递归遍历
    for entry in WalkDir::new(source_folder).into_iter().filter_map(|e| e.ok()) {
        let entry_path = entry.path();

        // 跳过隐藏目录/文件
        if let Some(name) = entry_path.file_name().and_then(|n| n.to_str()) {
            if name.starts_with('.') {
                continue;
            }
        }

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
                indexed_at: now.clone(),
            };
            let _ = storage::upsert_folder(&folder);
            scanned_folders += 1;
        } else {
            // 文件
            let ext = entry_path.extension()
                .and_then(|e| e.to_str())
                .unwrap_or("")
                .to_lowercase();

            let file_type = match classify_extension(&ext) {
                Some(ft) => ft,
                None => continue,
            };

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

            // 检查是否已索引且 mtime 未变
            if let Ok(Some(existing)) = storage::get_file_by_path(&path_str) {
                if existing.modified_at == modified_at {
                    scanned_files += 1;
                    continue;
                }
            }

            let created_at = metadata.created()
                .map(|t| DateTime::<Utc>::from(t).to_rfc3339())
                .unwrap_or_else(|_| now.clone());

            let fingerprint = match compute_fingerprint(entry_path) {
                Ok(fp) => fp,
                Err(_) => continue,
            };

            let file_name = entry_path.file_name()
                .unwrap_or_default()
                .to_string_lossy()
                .to_string();

            // 移动检测
            let file_uuid = if let Ok(Some(orphan)) = storage::find_orphan_by_fingerprint(&fingerprint) {
                orphan.uuid
            } else {
                uuid::Uuid::new_v4().to_string()
            };

            let indexed_file = IndexedFile {
                uuid: file_uuid,
                fingerprint,
                current_path: Some(path_str),
                folder_path: folder_str,
                file_name,
                file_type,
                extension: ext,
                file_size: metadata.len() as i64,
                created_at,
                modified_at,
                indexed_at: now.clone(),
            };

            let _ = storage::upsert_file(&indexed_file);
            scanned_files += 1;
        }
    }

    // 批量更新文件计数
    let _ = storage::update_folder_file_counts(source_folder);

    Ok(ScanResult {
        scanned_files,
        scanned_folders,
    })
}
