// 打开文件夹功能
use actix_web::{web, HttpResponse, Result};
use std::path::Path;
use super::models::OpenFolderRequest;

/// POST /api/folder/open
/// 打开文件所在文件夹
pub async fn open_folder(req: web::Json<OpenFolderRequest>) -> Result<HttpResponse> {
    let path = Path::new(&req.path);

    if !path.exists() {
        return Ok(HttpResponse::NotFound().json(serde_json::json!({
            "error": "文件不存在"
        })));
    }

    // 获取文件所在目录
    let folder = if path.is_dir() {
        path.to_path_buf()
    } else {
        path.parent()
            .ok_or_else(|| actix_web::error::ErrorInternalServerError("无法获取父目录"))?
            .to_path_buf()
    };

    // 根据操作系统打开文件夹
    #[cfg(target_os = "macos")]
    {
        std::process::Command::new("open")
            .arg(&folder)
            .spawn()
            .map_err(|e| actix_web::error::ErrorInternalServerError(e))?;
    }

    #[cfg(target_os = "windows")]
    {
        std::process::Command::new("explorer")
            .arg(&folder)
            .spawn()
            .map_err(|e| actix_web::error::ErrorInternalServerError(e))?;
    }

    #[cfg(target_os = "linux")]
    {
        std::process::Command::new("xdg-open")
            .arg(&folder)
            .spawn()
            .map_err(|e| actix_web::error::ErrorInternalServerError(e))?;
    }

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "status": "success"
    })))
}
