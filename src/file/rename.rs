// 文件重命名功能
use actix_web::{web, HttpResponse, Result};
use std::path::Path;
use std::fs;
use super::models::{RenameFileRequest, FileOperationResponse};
use super::utils::get_unique_path;

/// POST /api/file/rename
/// 重命名文件
pub async fn rename_file(req: web::Json<RenameFileRequest>) -> Result<HttpResponse> {
    let file_path = Path::new(&req.file_path);

    // 检查文件是否存在
    if !file_path.exists() || !file_path.is_file() {
        return Err(actix_web::error::ErrorNotFound("文件不存在"));
    }

    // 获取父目录
    let parent_dir = file_path.parent()
        .ok_or_else(|| actix_web::error::ErrorBadRequest("无法获取文件目录"))?;

    // 构建新文件路径,处理重名
    let new_path = get_unique_path(parent_dir, &req.new_name);

    // 重命名文件
    fs::rename(file_path, &new_path)
        .map_err(|e| actix_web::error::ErrorInternalServerError(format!("重命名失败: {}", e)))?;

    Ok(HttpResponse::Ok().json(FileOperationResponse {
        status: "success".to_string(),
        new_path: Some(new_path.to_string_lossy().to_string()),
    }))
}
