// 源文件夹管理功能 - 直接使用 storage 层的 DB 操作函数
use actix_web::{web, HttpResponse, Result};
use std::path::Path;
use std::sync::{Arc, RwLock};
use crate::config_api::storage;
use crate::indexer::models::ScanStatus;
use crate::indexer::{scanner, storage as indexer_storage};
use super::models::*;

/// GET /api/config/sources
/// 列出所有源文件夹(当前+备用)
pub async fn list_source_folders() -> Result<HttpResponse> {
    let folders = storage::list_source_folders().map_err(|e| {
        actix_web::error::ErrorInternalServerError(format!("无法加载源文件夹: {}", e))
    })?;

    let mut current = String::new();
    let mut backups = Vec::new();

    for (path, is_selected) in folders {
        if is_selected {
            current = path;
        } else {
            backups.push(path);
        }
    }

    Ok(HttpResponse::Ok().json(SourceFoldersResponse {
        current,
        backups,
    }))
}

/// POST /api/config/sources/add
/// 添加备用源文件夹
pub async fn add_source_folder(req: web::Json<AddSourceFolderRequest>) -> Result<HttpResponse> {
    let folder_path = req.folder_path.trim();

    // 验证路径存在
    if !Path::new(folder_path).exists() {
        return Ok(HttpResponse::BadRequest().json(serde_json::json!({
            "error": "文件夹不存在"
        })));
    }

    // 直接调用 storage 层的 DB 操作（内部已处理重复检查）
    if let Err(e) = storage::add_source_folder(folder_path) {
        if e.kind() == std::io::ErrorKind::AlreadyExists {
            return Ok(HttpResponse::BadRequest().json(serde_json::json!({
                "error": "该文件夹已添加"
            })));
        }
        return Err(actix_web::error::ErrorInternalServerError(
            format!("添加源文件夹失败: {}", e)
        ));
    }

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "status": "success"
    })))
}

/// POST /api/config/sources/remove
/// 移除备用源文件夹
pub async fn remove_source_folder(req: web::Json<RemoveSourceFolderRequest>) -> Result<HttpResponse> {
    let folder_path = req.folder_path.trim();

    // 检查是否是当前活动的源文件夹
    let selected = storage::get_selected_source_folder().map_err(|e| {
        actix_web::error::ErrorInternalServerError(format!("无法查询当前源文件夹: {}", e))
    })?;

    if let Some(ref current) = selected {
        if current == folder_path {
            return Ok(HttpResponse::BadRequest().json(serde_json::json!({
                "error": "无法删除当前活动的源文件夹"
            })));
        }
    }

    // 直接调用 storage 层的 DB 操作
    storage::remove_source_folder(folder_path).map_err(|e| {
        actix_web::error::ErrorInternalServerError(format!("删除源文件夹失败: {}", e))
    })?;

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "status": "success"
    })))
}

/// POST /api/config/sources/switch
/// 切换源文件夹（切换后自动检测是否需要索引）
pub async fn switch_source_folder(
    req: web::Json<SwitchSourceFolderRequest>,
    scan_status: web::Data<Arc<RwLock<ScanStatus>>>,
) -> Result<HttpResponse> {
    let folder_path = req.folder_path.trim().to_string();

    // 验证路径存在
    if !Path::new(&folder_path).exists() {
        return Ok(HttpResponse::BadRequest().json(serde_json::json!({
            "error": "文件夹不存在"
        })));
    }

    // 直接调用 storage 层的 DB 操作（内部处理 is_selected 切换）
    if let Err(e) = storage::select_source_folder(&folder_path) {
        if e.kind() == std::io::ErrorKind::NotFound {
            return Ok(HttpResponse::BadRequest().json(serde_json::json!({
                "error": "该文件夹不在源文件夹列表中"
            })));
        }
        return Err(actix_web::error::ErrorInternalServerError(
            format!("切换源文件夹失败: {}", e)
        ));
    }

    // 检查新源文件夹是否已被索引，未索引则后台自动启动扫描
    let already_indexed = indexer_storage::is_source_folder_indexed(&folder_path)
        .unwrap_or(false);

    if !already_indexed {
        let is_scanning = {
            let status = scan_status.read().unwrap();
            status.is_scanning
        };

        if !is_scanning {
            // 标记开始扫描
            {
                let mut status = scan_status.write().unwrap();
                status.is_scanning = true;
                status.scanned_files = 0;
                status.scanned_folders = 0;
            }

            let status_clone = scan_status.get_ref().clone();
            let source = folder_path.clone();
            tokio::spawn(async move {
                let result = tokio::task::spawn_blocking(move || {
                    scanner::scan_source_folder(&source)
                }).await;

                let mut status = status_clone.write().unwrap();
                match result {
                    Ok(Ok(scan_result)) => {
                        status.scanned_files = scan_result.scanned_files;
                        status.scanned_folders = scan_result.scanned_folders;
                    }
                    Ok(Err(e)) => {
                        eprintln!("自动索引失败: {}", e);
                    }
                    Err(e) => {
                        eprintln!("自动索引任务 panic: {}", e);
                    }
                }
                status.is_scanning = false;
            });
        }
    }

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "status": "success"
    })))
}
