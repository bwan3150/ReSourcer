// 源文件夹管理功能
use actix_web::{web, HttpResponse, Result};
use std::path::Path;
use crate::config_api::storage::{load_config, save_config};
use super::models::*;

/// GET /api/config/sources
/// 列出所有源文件夹(当前+备用)
pub async fn list_source_folders() -> Result<HttpResponse> {
    let state = load_config().map_err(|e| {
        actix_web::error::ErrorInternalServerError(format!("无法加载配置: {}", e))
    })?;

    Ok(HttpResponse::Ok().json(SourceFoldersResponse {
        current: state.source_folder,
        backups: state.backup_source_folders,
    }))
}

/// POST /api/config/sources/add
/// 添加备用源文件夹
pub async fn add_source_folder(req: web::Json<AddSourceFolderRequest>) -> Result<HttpResponse> {
    let mut state = load_config().map_err(|e| {
        actix_web::error::ErrorInternalServerError(format!("无法加载配置: {}", e))
    })?;

    let folder_path = req.folder_path.trim();

    // 验证路径存在
    if !Path::new(folder_path).exists() {
        return Ok(HttpResponse::BadRequest().json(serde_json::json!({
            "error": "文件夹不存在"
        })));
    }

    // 检查是否已存在
    if state.source_folder == folder_path || state.backup_source_folders.contains(&folder_path.to_string()) {
        return Ok(HttpResponse::BadRequest().json(serde_json::json!({
            "error": "该文件夹已添加"
        })));
    }

    // 添加到备用列表
    state.backup_source_folders.push(folder_path.to_string());

    save_config(&state).map_err(|e| {
        actix_web::error::ErrorInternalServerError(format!("无法保存配置: {}", e))
    })?;

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "status": "success"
    })))
}

/// POST /api/config/sources/remove
/// 移除备用源文件夹
pub async fn remove_source_folder(req: web::Json<RemoveSourceFolderRequest>) -> Result<HttpResponse> {
    let mut state = load_config().map_err(|e| {
        actix_web::error::ErrorInternalServerError(format!("无法加载配置: {}", e))
    })?;

    let folder_path = req.folder_path.trim();

    // 不能删除当前活动的源文件夹
    if state.source_folder == folder_path {
        return Ok(HttpResponse::BadRequest().json(serde_json::json!({
            "error": "无法删除当前活动的源文件夹"
        })));
    }

    // 从备用列表中移除
    state.backup_source_folders.retain(|f| f != folder_path);

    save_config(&state).map_err(|e| {
        actix_web::error::ErrorInternalServerError(format!("无法保存配置: {}", e))
    })?;

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "status": "success"
    })))
}

/// POST /api/config/sources/switch
/// 切换源文件夹
pub async fn switch_source_folder(req: web::Json<SwitchSourceFolderRequest>) -> Result<HttpResponse> {
    let mut state = load_config().map_err(|e| {
        actix_web::error::ErrorInternalServerError(format!("无法加载配置: {}", e))
    })?;

    let folder_path = req.folder_path.trim();

    // 验证路径存在
    if !Path::new(folder_path).exists() {
        return Ok(HttpResponse::BadRequest().json(serde_json::json!({
            "error": "文件夹不存在"
        })));
    }

    // 检查是否在备用列表中
    if !state.backup_source_folders.contains(&folder_path.to_string()) && state.source_folder != folder_path {
        return Ok(HttpResponse::BadRequest().json(serde_json::json!({
            "error": "该文件夹不在源文件夹列表中"
        })));
    }

    // 如果当前源文件夹不为空,将其加入备用列表
    if !state.source_folder.is_empty() && state.source_folder != folder_path {
        if !state.backup_source_folders.contains(&state.source_folder) {
            state.backup_source_folders.push(state.source_folder.clone());
        }
    }

    // 从备用列表中移除新的活动源
    state.backup_source_folders.retain(|f| f != folder_path);

    // 切换到新的源文件夹
    state.source_folder = folder_path.to_string();

    save_config(&state).map_err(|e| {
        actix_web::error::ErrorInternalServerError(format!("无法保存配置: {}", e))
    })?;

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "status": "success"
    })))
}
