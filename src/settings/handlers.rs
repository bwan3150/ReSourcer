use actix_web::{web, HttpResponse, Result};
use std::fs;
use std::path::Path;
use super::models::*;
use crate::classifier::config::{load_config, save_config};

// 注册所有设置相关路由
pub fn routes(cfg: &mut web::ServiceConfig) {
    cfg.service(web::resource("/state").route(web::get().to(get_state)))
       .service(web::resource("/folders").route(web::get().to(get_folders)))
       .service(web::resource("/save").route(web::post().to(save_settings)))
       .service(web::resource("/folder/create").route(web::post().to(create_folder)))
       // 源文件夹管理API
       .service(web::resource("/sources/list").route(web::get().to(list_source_folders)))
       .service(web::resource("/sources/add").route(web::post().to(add_source_folder)))
       .service(web::resource("/sources/remove").route(web::post().to(remove_source_folder)))
       .service(web::resource("/sources/switch").route(web::post().to(switch_source_folder)));
}

// 获取配置状态
pub async fn get_state() -> Result<HttpResponse> {
    let state = load_config().map_err(|e| {
        actix_web::error::ErrorInternalServerError(format!("无法加载配置: {}", e))
    })?;

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "source_folder": state.source_folder,
        "hidden_folders": state.hidden_folders,
        "backup_source_folders": state.backup_source_folders
    })))
}

// 获取指定源文件夹下的子文件夹列表
pub async fn get_folders(query: web::Query<std::collections::HashMap<String, String>>) -> Result<HttpResponse> {
    let source_folder = query.get("source_folder");

    if source_folder.is_none() {
        return Ok(HttpResponse::Ok().json(Vec::<FolderInfo>::new()));
    }

    let source_folder = source_folder.unwrap();
    let source_path = Path::new(source_folder);

    if !source_path.exists() || !source_path.is_dir() {
        return Ok(HttpResponse::Ok().json(Vec::<FolderInfo>::new()));
    }

    // 加载配置以获取隐藏文件夹列表
    let state = load_config().unwrap_or_else(|_| crate::classifier::config::get_default_state());

    let mut folders = Vec::new();

    if let Ok(entries) = fs::read_dir(source_path) {
        for entry in entries.flatten() {
            if let Ok(metadata) = entry.metadata() {
                if metadata.is_dir() {
                    let folder_name = entry.file_name().to_string_lossy().to_string();
                    // 跳过隐藏文件夹（以.开头的）
                    if !folder_name.starts_with('.') {
                        let hidden = state.hidden_folders.contains(&folder_name);
                        folders.push(FolderInfo {
                            name: folder_name,
                            hidden,
                        });
                    }
                }
            }
        }
    }

    folders.sort_by(|a, b| a.name.cmp(&b.name));
    Ok(HttpResponse::Ok().json(folders))
}

// 保存设置(创建文件夹并保存配置)
pub async fn save_settings(req: web::Json<SaveSettingsRequest>) -> Result<HttpResponse> {
    let mut state = load_config().map_err(|e| {
        actix_web::error::ErrorInternalServerError(format!("无法加载配置: {}", e))
    })?;

    // 更新源文件夹
    state.source_folder = req.source_folder.clone();
    state.hidden_folders = req.hidden_folders.clone();

    // 验证源文件夹存在
    let source_path = Path::new(&state.source_folder);
    if !source_path.exists() {
        return Ok(HttpResponse::BadRequest().json(serde_json::json!({
            "error": "Source folder does not exist"
        })));
    }

    // 创建所有需要的分类文件夹
    for category in &req.categories {
        let folder_path = source_path.join(category);
        if !folder_path.exists() {
            fs::create_dir_all(&folder_path)?;
        }
    }

    // 保存配置
    save_config(&state).map_err(|e| {
        actix_web::error::ErrorInternalServerError(format!("无法保存配置: {}", e))
    })?;

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "status": "success"
    })))
}

// 创建单个文件夹
pub async fn create_folder(req: web::Json<CreateFolderRequest>) -> Result<HttpResponse> {
    let state = load_config().map_err(|e| {
        actix_web::error::ErrorInternalServerError(format!("无法加载配置: {}", e))
    })?;

    // 验证源文件夹存在
    let source_path = Path::new(&state.source_folder);
    if !source_path.exists() {
        return Ok(HttpResponse::BadRequest().json(serde_json::json!({
            "error": "Source folder does not exist"
        })));
    }

    // 创建文件夹
    let folder_path = source_path.join(&req.folder_name);
    if !folder_path.exists() {
        fs::create_dir_all(&folder_path)?;
    }

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "status": "success"
    })))
}

// ========== 源文件夹管理API ==========

// 列出所有源文件夹(当前+备用)
pub async fn list_source_folders() -> Result<HttpResponse> {
    let state = load_config().map_err(|e| {
        actix_web::error::ErrorInternalServerError(format!("无法加载配置: {}", e))
    })?;

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "current": state.source_folder,
        "backups": state.backup_source_folders
    })))
}

// 添加备用源文件夹
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

// 移除备用源文件夹
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

// 切换源文件夹
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
