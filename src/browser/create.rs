// 创建目录功能（从browser/handlers.rs迁移）
use actix_web::{web, HttpResponse, Result};
use std::fs;
use std::path::Path;
use super::models::CreateDirectoryRequest;

/// POST /api/browser/create
/// 创建新目录
pub async fn create_directory(req: web::Json<CreateDirectoryRequest>) -> Result<HttpResponse> {
    let parent_path = Path::new(&req.parent_path);

    // 安全检查:确保父目录存在
    if !parent_path.exists() || !parent_path.is_dir() {
        return Ok(HttpResponse::BadRequest().json(serde_json::json!({
            "error": "父目录不存在"
        })));
    }

    // 验证目录名称(防止路径遍历攻击)
    if req.directory_name.contains('/') || req.directory_name.contains('\\')
        || req.directory_name == ".." || req.directory_name == "." {
        return Ok(HttpResponse::BadRequest().json(serde_json::json!({
            "error": "无效的目录名称"
        })));
    }

    let new_dir_path = parent_path.join(&req.directory_name);

    // 检查目录是否已存在
    if new_dir_path.exists() {
        return Ok(HttpResponse::BadRequest().json(serde_json::json!({
            "error": "目录已存在"
        })));
    }

    // 创建目录
    match fs::create_dir(&new_dir_path) {
        Ok(_) => Ok(HttpResponse::Ok().json(serde_json::json!({
            "status": "success",
            "path": new_dir_path.to_string_lossy()
        }))),
        Err(e) => Ok(HttpResponse::InternalServerError().json(serde_json::json!({
            "error": format!("无法创建目录: {}", e)
        })))
    }
}
