use actix_web::{web, HttpResponse, Result};
use std::fs;
use std::path::{Path, PathBuf};
use super::models::*;

/// 注册文件系统相关路由
pub fn routes(cfg: &mut web::ServiceConfig) {
    cfg.service(web::resource("/browse").route(web::post().to(browse_directory)))
       .service(web::resource("/create").route(web::post().to(create_directory)));
}

/// 获取用户主目录
fn get_home_directory() -> PathBuf {
    let home = std::env::var("HOME")
        .or_else(|_| std::env::var("USERPROFILE"))
        .unwrap_or_else(|_| ".".to_string());
    PathBuf::from(home)
}

/// 浏览目录
pub async fn browse_directory(req: web::Json<BrowseRequest>) -> Result<HttpResponse> {
    // 确定要浏览的路径
    let target_path = if let Some(path) = &req.path {
        PathBuf::from(path)
    } else {
        get_home_directory()
    };

    // 安全检查:确保路径存在且是目录
    if !target_path.exists() {
        return Ok(HttpResponse::BadRequest().json(serde_json::json!({
            "error": "路径不存在"
        })));
    }

    if !target_path.is_dir() {
        return Ok(HttpResponse::BadRequest().json(serde_json::json!({
            "error": "路径不是目录"
        })));
    }

    // 读取目录内容
    let mut items = Vec::new();

    match fs::read_dir(&target_path) {
        Ok(entries) => {
            for entry in entries.flatten() {
                if let Ok(metadata) = entry.metadata() {
                    let name = entry.file_name().to_string_lossy().to_string();

                    // 跳过隐藏文件(以.开头的)
                    if name.starts_with('.') {
                        continue;
                    }

                    let path = entry.path().to_string_lossy().to_string();
                    let is_directory = metadata.is_dir();

                    items.push(DirectoryItem {
                        name,
                        path,
                        is_directory,
                    });
                }
            }
        }
        Err(e) => {
            return Ok(HttpResponse::InternalServerError().json(serde_json::json!({
                "error": format!("无法读取目录: {}", e)
            })));
        }
    }

    // 按类型和名称排序(文件夹在前)
    items.sort_by(|a, b| {
        match (a.is_directory, b.is_directory) {
            (true, false) => std::cmp::Ordering::Less,
            (false, true) => std::cmp::Ordering::Greater,
            _ => a.name.to_lowercase().cmp(&b.name.to_lowercase()),
        }
    });

    // 获取父目录路径
    let parent_path = target_path.parent().map(|p| p.to_string_lossy().to_string());

    Ok(HttpResponse::Ok().json(BrowseResponse {
        current_path: target_path.to_string_lossy().to_string(),
        parent_path,
        items,
    }))
}

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
