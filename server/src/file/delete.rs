// 文件删除功能（软删除：移动到回收站，不做物理删除以防误操作）
use actix_web::{web, HttpResponse, Result};
use super::models::{DeleteFileRequest, FileOperationResponse};
use super::ops::delete_one;

/// POST /api/file/delete
/// 软删除文件：移动到 当前源文件夹/回收站（懒创建）。
/// 不提供物理删除能力，回收站文件仅可再被移动/还原。
pub async fn delete_file(req: web::Json<DeleteFileRequest>) -> Result<HttpResponse> {
    let uuid = req.uuid.clone();

    let new_path = tokio::task::spawn_blocking(move || delete_one(&uuid))
        .await
        .map_err(|e| actix_web::error::ErrorInternalServerError(format!("删除失败: {}", e)))?
        .map_err(|e| e.into_actix())?;

    Ok(HttpResponse::Ok().json(FileOperationResponse {
        status: "success".to_string(),
        uuid: Some(req.uuid.clone()),
        new_path: Some(new_path),
    }))
}
