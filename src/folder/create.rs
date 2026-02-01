// 文件夹创建功能
use actix_web::{web, HttpResponse, Result};
use std::fs;
use std::path::Path;
use super::models::CreateFolderRequest;

/// POST /api/folder/create
/// 创建新文件夹 - 整合了 classifier/folder/create, downloader/create-folder, settings/folder/create
pub async fn create_folder(req: web::Json<CreateFolderRequest>) -> Result<HttpResponse> {
    let folder_name = &req.folder_name;

    // 验证文件夹名称
    if folder_name.is_empty() || folder_name.contains('/') || folder_name.contains('\\') {
        return Ok(HttpResponse::BadRequest().json(serde_json::json!({
            "error": "无效的文件夹名称"
        })));
    }

    let config = crate::config_api::storage::load_config()
        .map_err(|e| actix_web::error::ErrorInternalServerError(format!("无法加载配置: {}", e)))?;

    // 验证源文件夹存在
    let source_path = Path::new(&config.source_folder);
    if !source_path.exists() {
        return Ok(HttpResponse::BadRequest().json(serde_json::json!({
            "error": "源文件夹不存在"
        })));
    }

    // 创建文件夹
    let folder_path = source_path.join(folder_name);

    if folder_path.exists() {
        return Ok(HttpResponse::BadRequest().json(serde_json::json!({
            "error": "文件夹已存在"
        })));
    }

    fs::create_dir_all(&folder_path)
        .map_err(|e| actix_web::error::ErrorInternalServerError(
            format!("无法创建文件夹: {}", e)
        ))?;

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "status": "success",
        "message": "文件夹创建成功",
        "folder_name": folder_name
    })))
}
