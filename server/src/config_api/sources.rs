// 源文件夹管理功能 - 直接使用 storage 层的 DB 操作函数
use actix_web::{web, HttpResponse, Result};
use std::path::Path;
use crate::config_api::storage;
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
/// 切换源文件夹
pub async fn switch_source_folder(req: web::Json<SwitchSourceFolderRequest>) -> Result<HttpResponse> {
    let folder_path = req.folder_path.trim();

    // 验证路径存在
    if !Path::new(folder_path).exists() {
        return Ok(HttpResponse::BadRequest().json(serde_json::json!({
            "error": "文件夹不存在"
        })));
    }

    // 直接调用 storage 层的 DB 操作（内部处理 is_selected 切换）
    if let Err(e) = storage::select_source_folder(folder_path) {
        if e.kind() == std::io::ErrorKind::NotFound {
            return Ok(HttpResponse::BadRequest().json(serde_json::json!({
                "error": "该文件夹不在源文件夹列表中"
            })));
        }
        return Err(actix_web::error::ErrorInternalServerError(
            format!("切换源文件夹失败: {}", e)
        ));
    }

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "status": "success"
    })))
}
