// 文件重命名功能
use actix_web::{web, HttpResponse, Result};
use std::path::Path;
use std::fs;
use super::models::{RenameFileRequest, FileOperationResponse};
use super::utils::get_unique_path;

/// POST /api/file/rename
/// 重命名文件（通过 UUID 标识）
pub async fn rename_file(req: web::Json<RenameFileRequest>) -> Result<HttpResponse> {
    // 通过 UUID 查询索引获取当前路径
    let indexed = crate::indexer::storage::get_file_by_uuid(&req.uuid)
        .map_err(|e| actix_web::error::ErrorInternalServerError(format!("查询索引失败: {}", e)))?
        .ok_or_else(|| actix_web::error::ErrorNotFound("UUID 对应的文件不存在"))?;

    let current_path = indexed.current_path
        .ok_or_else(|| actix_web::error::ErrorNotFound("文件路径为空"))?;
    let file_path = Path::new(&current_path);

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

    // 更新文件索引
    let new_path_str = new_path.to_string_lossy().to_string();
    let folder_str = parent_dir.to_string_lossy().to_string();
    let new_file_name = new_path.file_name()
        .unwrap_or_default()
        .to_string_lossy()
        .to_string();
    let _ = crate::indexer::storage::update_file_path(
        &req.uuid, &new_path_str, &folder_str, &new_file_name,
    );

    Ok(HttpResponse::Ok().json(FileOperationResponse {
        status: "success".to_string(),
        uuid: Some(req.uuid.clone()),
        new_path: Some(new_path_str),
    }))
}
