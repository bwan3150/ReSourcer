// 文件移动功能
use actix_web::{web, HttpResponse, Result};
use std::path::Path;
use std::fs;
use super::models::{MoveFileRequest, FileOperationResponse};
use super::utils::get_unique_path;

/// POST /api/file/move
/// 移动文件到其他文件夹（通过 UUID 标识）
pub async fn move_file(req: web::Json<MoveFileRequest>) -> Result<HttpResponse> {
    // 通过 UUID 查询索引获取当前路径
    let indexed = crate::indexer::storage::get_file_by_uuid(&req.uuid)
        .map_err(|e| actix_web::error::ErrorInternalServerError(format!("查询索引失败: {}", e)))?
        .ok_or_else(|| actix_web::error::ErrorNotFound("UUID 对应的文件不存在"))?;

    let current_path = indexed.current_path
        .ok_or_else(|| actix_web::error::ErrorNotFound("文件路径为空"))?;
    let file_path = Path::new(&current_path);
    let target_folder = Path::new(&req.target_folder);

    // 检查文件是否存在
    if !file_path.exists() || !file_path.is_file() {
        return Err(actix_web::error::ErrorNotFound("文件不存在"));
    }

    // 检查目标文件夹是否存在
    if !target_folder.exists() || !target_folder.is_dir() {
        return Err(actix_web::error::ErrorNotFound("目标文件夹不存在"));
    }

    // 获取文件名（如果提供了new_name则使用它，否则使用原文件名）
    let file_name = if let Some(new_name) = &req.new_name {
        new_name.clone()
    } else {
        file_path.file_name()
            .ok_or_else(|| actix_web::error::ErrorBadRequest("无法获取文件名"))?
            .to_string_lossy()
            .to_string()
    };

    // 构建目标路径,处理重名
    let target_path = get_unique_path(target_folder, &file_name);

    // 移动文件
    fs::rename(file_path, &target_path)
        .map_err(|e| actix_web::error::ErrorInternalServerError(format!("移动失败: {}", e)))?;

    // 更新文件索引
    let new_path_str = target_path.to_string_lossy().to_string();
    let new_folder_str = target_folder.to_string_lossy().to_string();
    let new_file_name = target_path.file_name()
        .unwrap_or_default()
        .to_string_lossy()
        .to_string();
    let _ = crate::indexer::storage::update_file_path(
        &req.uuid, &new_path_str, &new_folder_str, &new_file_name,
    );

    Ok(HttpResponse::Ok().json(FileOperationResponse {
        status: "success".to_string(),
        uuid: Some(req.uuid.clone()),
        new_path: Some(new_path_str),
    }))
}
