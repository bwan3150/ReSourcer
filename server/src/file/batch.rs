// 批量文件操作：移动、软删除
use actix_web::{web, HttpResponse, Result};

use super::models::{
    BatchFileFailure, BatchFileOperationResponse, BatchFileSuccess, BatchDeleteFilesRequest,
    BatchMoveFilesRequest,
};
use super::ops::{delete_one, move_one};

pub(crate) fn batch_status(success_count: usize, failure_count: usize) -> &'static str {
    if failure_count == 0 {
        "success"
    } else if success_count == 0 {
        "error"
    } else {
        "partial"
    }
}

/// POST /api/file/batch/move
/// 批量移动文件到同一目标文件夹
pub async fn batch_move_files(req: web::Json<BatchMoveFilesRequest>) -> Result<HttpResponse> {
    if req.uuids.is_empty() {
        return Err(actix_web::error::ErrorBadRequest("uuids 不能为空"));
    }

    let target_folder = req.target_folder.clone();
    let uuids = req.uuids.clone();

    let (succeeded, failed) = tokio::task::spawn_blocking(move || {
        let mut succeeded = Vec::new();
        let mut failed = Vec::new();
        for uuid in uuids {
            match move_one(&uuid, &target_folder, None) {
                Ok(new_path) => succeeded.push(BatchFileSuccess {
                    uuid: uuid.clone(),
                    new_path,
                }),
                Err(e) => failed.push(BatchFileFailure {
                    uuid,
                    error: e.message().to_string(),
                }),
            }
        }
        (succeeded, failed)
    })
    .await
    .map_err(|e| actix_web::error::ErrorInternalServerError(format!("批量移动失败: {}", e)))?;

    let success_count = succeeded.len();
    let failure_count = failed.len();

    Ok(HttpResponse::Ok().json(BatchFileOperationResponse {
        status: batch_status(success_count, failure_count).to_string(),
        success_count,
        failure_count,
        succeeded,
        failed,
    }))
}

/// POST /api/file/batch/delete
/// 批量软删除：将文件移动到源文件夹回收站
pub async fn batch_delete_files(req: web::Json<BatchDeleteFilesRequest>) -> Result<HttpResponse> {
    if req.uuids.is_empty() {
        return Err(actix_web::error::ErrorBadRequest("uuids 不能为空"));
    }

    let uuids = req.uuids.clone();

    let (succeeded, failed) = tokio::task::spawn_blocking(move || {
        let mut succeeded = Vec::new();
        let mut failed = Vec::new();
        for uuid in uuids {
            match delete_one(&uuid) {
                Ok(new_path) => succeeded.push(BatchFileSuccess {
                    uuid: uuid.clone(),
                    new_path,
                }),
                Err(e) => failed.push(BatchFileFailure {
                    uuid,
                    error: e.message().to_string(),
                }),
            }
        }
        (succeeded, failed)
    })
    .await
    .map_err(|e| actix_web::error::ErrorInternalServerError(format!("批量删除失败: {}", e)))?;

    let success_count = succeeded.len();
    let failure_count = failed.len();

    Ok(HttpResponse::Ok().json(BatchFileOperationResponse {
        status: batch_status(success_count, failure_count).to_string(),
        success_count,
        failure_count,
        succeeded,
        failed,
    }))
}

#[cfg(test)]
mod tests {
    use super::batch_status;

    #[test]
    fn batch_status_all_success() {
        assert_eq!(batch_status(3, 0), "success");
    }

    #[test]
    fn batch_status_all_failed() {
        assert_eq!(batch_status(0, 2), "error");
    }

    #[test]
    fn batch_status_partial() {
        assert_eq!(batch_status(2, 1), "partial");
    }

    #[test]
    fn batch_status_empty_counts_is_success() {
        // 空列表在 handler 层已拒绝；status 辅助函数本身视作成功
        assert_eq!(batch_status(0, 0), "success");
    }
}
