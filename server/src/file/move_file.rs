// 文件移动功能
use actix_web::{web, HttpResponse, Result};
use super::models::{MoveFileRequest, FileOperationResponse};
use super::ops::move_one;

/// POST /api/file/move
/// 移动文件到其他文件夹（通过 UUID 标识）
pub async fn move_file(req: web::Json<MoveFileRequest>) -> Result<HttpResponse> {
    let uuid = req.uuid.clone();
    let target_folder = req.target_folder.clone();
    let new_name = req.new_name.clone();

    let new_path = tokio::task::spawn_blocking(move || {
        move_one(&uuid, &target_folder, new_name.as_deref())
    })
    .await
    .map_err(|e| actix_web::error::ErrorInternalServerError(format!("移动失败: {}", e)))?
    .map_err(|e| e.into_actix())?;

    Ok(HttpResponse::Ok().json(FileOperationResponse {
        status: "success".to_string(),
        uuid: Some(req.uuid.clone()),
        new_path: Some(new_path),
    }))
}
