// API handler 实现
use actix_web::{web, HttpResponse, Result};
use std::sync::{Arc, RwLock};
use super::models::*;
use super::storage;
use super::scanner;

/// POST /api/indexer/scan — 后台全量扫描源文件夹
/// 参数 force=true 时先清除旧索引再全量重建
pub async fn scan(
    req: web::Json<ScanRequest>,
    scan_status: web::Data<Arc<RwLock<ScanStatus>>>,
) -> Result<HttpResponse> {
    let source_folder = req.source_folder.clone();
    let force = req.force;

    // 检查是否正在扫描
    {
        let status = scan_status.read().unwrap();
        if status.is_scanning {
            return Ok(HttpResponse::Ok().json(serde_json::json!({
                "status": "already_scanning",
                "scanned_files": status.scanned_files,
                "scanned_folders": status.scanned_folders,
            })));
        }
    }

    // 标记开始扫描
    {
        let mut status = scan_status.write().unwrap();
        status.is_scanning = true;
        status.scanned_files = 0;
        status.scanned_folders = 0;
    }

    let status_clone = scan_status.get_ref().clone();
    tokio::spawn(async move {
        let result = tokio::task::spawn_blocking(move || {
            // force 模式：先清除该源文件夹下的所有文件索引
            if force {
                match storage::clear_file_index_for_source(&source_folder) {
                    Ok(deleted) => eprintln!("强制重建：已清除 {} 条文件索引", deleted),
                    Err(e) => eprintln!("清除文件索引失败: {}", e),
                }
            }
            scanner::scan_source_folder(&source_folder)
        }).await;

        let mut status = status_clone.write().unwrap();
        match result {
            Ok(Ok(scan_result)) => {
                status.scanned_files = scan_result.scanned_files;
                status.scanned_folders = scan_result.scanned_folders;
            }
            Ok(Err(e)) => {
                eprintln!("扫描失败: {}", e);
            }
            Err(e) => {
                eprintln!("扫描任务 panic: {}", e);
            }
        }
        status.is_scanning = false;
    });

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "status": "started"
    })))
}

/// GET /api/indexer/status — 返回扫描进度
pub async fn status(
    scan_status: web::Data<Arc<RwLock<ScanStatus>>>,
) -> Result<HttpResponse> {
    let status = scan_status.read().unwrap();
    Ok(HttpResponse::Ok().json(&*status))
}

/// 文件查询结果（Send 安全）
enum FilesResult {
    Ok(PaginatedFilesResponse),
    Err(String),
}

/// GET /api/indexer/files — 惰性索引分页查询
pub async fn files(
    query: web::Query<FilesQuery>,
) -> Result<HttpResponse> {
    let folder_path = query.folder_path.clone();
    let offset = query.offset.unwrap_or(0);
    let limit = query.limit.unwrap_or(50).min(200); // 限制最大 200 条，防止内存暴涨
    let file_type = query.file_type.clone();
    let sort = query.sort.clone();

    let result = tokio::task::spawn_blocking(move || -> FilesResult {
        // 检查文件夹是否已索引
        let indexed = match storage::is_folder_indexed(&folder_path) {
            Ok(v) => v,
            Err(e) => return FilesResult::Err(format!("数据库错误: {}", e)),
        };

        if !indexed {
            // 首次访问：同步扫描建索引（前台，执行 mark_missing）
            let source_folder = find_source_folder(&folder_path)
                .unwrap_or_else(|| folder_path.clone());

            if let Err(e) = scanner::scan_folder(&folder_path, &source_folder, false) {
                eprintln!("首次扫描失败: {}", e);
                return FilesResult::Ok(PaginatedFilesResponse {
                    files: vec![],
                    total: 0,
                    offset,
                    limit,
                    has_more: false,
                });
            }
        } else if scanner::needs_rescan(&folder_path) {
            // 有索引但需要更新 → 返回旧数据 + 后台增量更新
            // skip_mark_missing=true：后台扫描只新增/更新，不标记缺失，避免竞态导致文件"消失"
            let folder_clone = folder_path.clone();
            let source = find_source_folder(&folder_path)
                .unwrap_or_else(|| folder_path.clone());
            std::thread::spawn(move || {
                let _ = scanner::scan_folder(&folder_clone, &source, true);
            });
        }

        // 从索引分页返回
        match storage::get_files_paginated(
            &folder_path, offset, limit,
            file_type.as_deref(),
            sort.as_deref(),
        ) {
            Ok((files, total)) => FilesResult::Ok(PaginatedFilesResponse {
                files,
                total,
                offset,
                limit,
                has_more: offset + limit < total,
            }),
            Err(e) => FilesResult::Err(format!("查询失败: {}", e)),
        }
    }).await
        .map_err(|e| actix_web::error::ErrorInternalServerError(format!("任务执行失败: {}", e)))?;

    match result {
        FilesResult::Ok(response) => Ok(HttpResponse::Ok().json(response)),
        FilesResult::Err(msg) => Err(actix_web::error::ErrorInternalServerError(msg)),
    }
}

/// GET /api/indexer/file — UUID 查询单个文件
pub async fn file_by_uuid(
    query: web::Query<FileByUuidQuery>,
) -> Result<HttpResponse> {
    let uuid = query.uuid.clone();

    let result = tokio::task::spawn_blocking(move || {
        storage::get_file_by_uuid(&uuid)
    }).await
        .map_err(|e| actix_web::error::ErrorInternalServerError(format!("任务执行失败: {}", e)))?
        .map_err(|e| actix_web::error::ErrorInternalServerError(format!("数据库错误: {}", e)))?;

    match result {
        Some(file) => Ok(HttpResponse::Ok().json(file)),
        None => Err(actix_web::error::ErrorNotFound("文件未找到")),
    }
}

/// 文件夹查询结果（Send 安全）
enum FoldersResult {
    Ok(Vec<IndexedFolder>),
    Err(String),
    BadRequest(String),
}

/// GET /api/indexer/folders — 子文件夹查询（直接读文件系统）
pub async fn folders(
    query: web::Query<FoldersQuery>,
) -> Result<HttpResponse> {
    let parent_path = query.parent_path.clone();
    let source_folder = query.source_folder.clone();

    let result = tokio::task::spawn_blocking(move || -> FoldersResult {
        // 读取 ignored_folders 配置
        let ignored_folders = crate::config_api::storage::load_config()
            .map(|c| c.ignored_folders)
            .unwrap_or_default();

        if let Some(ref parent) = parent_path {
            let source = source_folder.as_deref()
                .unwrap_or(parent);
            let source_resolved = find_source_folder(parent)
                .unwrap_or_else(|| source.to_string());

            match read_subfolders_from_fs(parent, &source_resolved, &ignored_folders) {
                Ok(mut folders) => {
                    apply_subfolder_order(&mut folders, parent);
                    FoldersResult::Ok(folders)
                }
                Err(e) => FoldersResult::Err(e),
            }
        } else if let Some(ref source) = source_folder {
            match read_subfolders_from_fs(source, source, &ignored_folders) {
                Ok(mut folders) => {
                    apply_subfolder_order(&mut folders, source);
                    FoldersResult::Ok(folders)
                }
                Err(e) => FoldersResult::Err(e),
            }
        } else {
            FoldersResult::BadRequest("需要 parent_path 或 source_folder 参数".to_string())
        }
    }).await
        .map_err(|e| actix_web::error::ErrorInternalServerError(format!("任务执行失败: {}", e)))?;

    match result {
        FoldersResult::Ok(folders) => Ok(HttpResponse::Ok().json(folders)),
        FoldersResult::Err(msg) => Err(actix_web::error::ErrorInternalServerError(msg)),
        FoldersResult::BadRequest(msg) => Err(actix_web::error::ErrorBadRequest(msg)),
    }
}

/// GET /api/indexer/breadcrumb — 面包屑路径
pub async fn breadcrumb(
    query: web::Query<BreadcrumbQuery>,
) -> Result<HttpResponse> {
    let folder_path = query.folder_path.clone();

    let source_folder = find_source_folder(&folder_path)
        .unwrap_or_else(|| folder_path.clone());

    let crumbs = storage::get_breadcrumb(&folder_path, &source_folder);
    Ok(HttpResponse::Ok().json(crumbs))
}

/// 直接从文件系统读取子文件夹列表，跳过隐藏目录和 ignored_folders
fn read_subfolders_from_fs(parent_path: &str, source_folder: &str, ignored_folders: &[String]) -> Result<Vec<IndexedFolder>, String> {
    use crate::folder::utils::{count_files_in_folder, count_subfolders};

    let dir_path = std::path::Path::new(parent_path);
    if !dir_path.is_dir() {
        return Ok(vec![]);
    }

    let source_path = std::path::Path::new(source_folder);
    let now = chrono::Utc::now().to_rfc3339();

    let entries = std::fs::read_dir(dir_path)
        .map_err(|e| format!("读取目录失败: {}", e))?;

    let mut folders = Vec::new();
    for entry in entries.flatten() {
        let entry_path = entry.path();
        if !entry_path.is_dir() {
            continue;
        }

        let name = match entry_path.file_name().and_then(|n| n.to_str()) {
            Some(n) => n.to_string(),
            None => continue,
        };

        // 跳过隐藏目录
        if name.starts_with('.') {
            continue;
        }

        // 跳过 ignored_folders
        if ignored_folders.iter().any(|ig| ig == &name) {
            continue;
        }

        let depth = entry_path.strip_prefix(source_path)
            .map(|rel| rel.components().count() as i32)
            .unwrap_or(0);

        let file_count = count_files_in_folder(&entry_path) as i64;
        let subfolder_count = count_subfolders(&entry_path, ignored_folders) as i64;

        folders.push(IndexedFolder {
            path: entry_path.to_string_lossy().to_string(),
            parent_path: Some(parent_path.to_string()),
            source_folder: source_folder.to_string(),
            name,
            depth,
            file_count,
            subfolder_count,
            indexed_at: now.clone(),
        });
    }

    Ok(folders)
}

/// 对子文件夹列表应用保存的排序
fn apply_subfolder_order(folders: &mut Vec<IndexedFolder>, parent_path: &str) {
    let order = crate::config_api::storage::get_subfolder_order(parent_path);
    if !order.is_empty() {
        folders.sort_by(|a, b| {
            let pos_a = order.iter().position(|x| x == &a.name);
            let pos_b = order.iter().position(|x| x == &b.name);
            match (pos_a, pos_b) {
                (Some(pa), Some(pb)) => pa.cmp(&pb),
                (Some(_), None) => std::cmp::Ordering::Less,
                (None, Some(_)) => std::cmp::Ordering::Greater,
                (None, None) => a.name.cmp(&b.name),
            }
        });
    } else {
        folders.sort_by(|a, b| a.name.cmp(&b.name));
    }
}

/// 从数据库查找给定路径的源文件夹（委托给 storage 模块）
fn find_source_folder(folder_path: &str) -> Option<String> {
    storage::find_source_folder(folder_path)
}

