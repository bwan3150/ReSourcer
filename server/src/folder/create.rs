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

    // 解析父目录：若请求提供了 parent_path 且合法（位于源文件夹内且存在），则在该目录下创建；
    // 否则回退到源文件夹根部，兼容旧客户端
    let base_dir = match &req.parent_path {
        Some(p) if !p.trim().is_empty() => {
            let canon_source = std::fs::canonicalize(source_path).ok();
            let canon_parent = std::fs::canonicalize(Path::new(p)).ok();
            match (canon_source, canon_parent) {
                (Some(cs), Some(cp)) if cp.starts_with(&cs) && cp.is_dir() => cp,
                _ => {
                    return Ok(HttpResponse::BadRequest().json(serde_json::json!({
                        "error": "无效的父目录"
                    })));
                }
            }
        }
        _ => source_path.to_path_buf(),
    };

    // 创建文件夹
    let folder_path = base_dir.join(folder_name);

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
