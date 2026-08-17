// 文件删除功能（软删除：移动到回收站，不做物理删除以防误操作）
use actix_web::{web, HttpResponse, Result};
use std::path::Path;
use std::fs;
use super::models::{DeleteFileRequest, FileOperationResponse, RECYCLE_BIN_NAME};
use super::utils::get_unique_path;

/// POST /api/file/delete
/// 软删除文件：移动到 当前源文件夹/回收站（懒创建）。
/// 不提供物理删除能力，回收站文件仅可再被移动/还原。
pub async fn delete_file(req: web::Json<DeleteFileRequest>) -> Result<HttpResponse> {
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

    // 加载配置获取当前源文件夹
    let config = crate::config_api::storage::load_config()
        .map_err(|e| actix_web::error::ErrorInternalServerError(format!("无法加载配置: {}", e)))?;

    // 回收站目录：当前源文件夹/回收站（懒创建）
    let recycle_dir = Path::new(&config.source_folder).join(RECYCLE_BIN_NAME);
    if !recycle_dir.exists() {
        fs::create_dir_all(&recycle_dir)
            .map_err(|e| actix_web::error::ErrorInternalServerError(format!("无法创建回收站: {}", e)))?;
    }

    // 若文件已在回收站中则拒绝（回收站内不允许再次删除）
    if let Ok(canon_recycle) = fs::canonicalize(&recycle_dir) {
        if let Some(parent) = file_path.parent() {
            if let Ok(canon_parent) = fs::canonicalize(parent) {
                if canon_parent == canon_recycle {
                    return Err(actix_web::error::ErrorBadRequest("文件已在回收站中"));
                }
            }
        }
    }

    // 获取文件名，处理回收站内重名
    let file_name = file_path.file_name()
        .ok_or_else(|| actix_web::error::ErrorBadRequest("无法获取文件名"))?
        .to_string_lossy()
        .to_string();
    let target_path = get_unique_path(&recycle_dir, &file_name);

    // 移动文件到回收站
    fs::rename(file_path, &target_path)
        .map_err(|e| actix_web::error::ErrorInternalServerError(format!("删除失败: {}", e)))?;

    // 更新文件索引
    let new_path_str = target_path.to_string_lossy().to_string();
    let new_folder_str = recycle_dir.to_string_lossy().to_string();
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
