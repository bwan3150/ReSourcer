// 上传任务管理功能（从transfer/upload.rs迁移）
use actix_web::{web, HttpResponse, Result};
use actix_multipart::Multipart;
use super::models::*;
use super::TaskManager;
use super::storage;
use futures_util::StreamExt;

/// POST /api/transfer/upload/task
/// 上传文件（支持批量）- 使用流式处理，边读边写
pub async fn upload_file(
    mut payload: Multipart,
    task_manager: web::Data<TaskManager>,
) -> Result<HttpResponse> {
    let mut task_ids = Vec::new();
    let mut target_folder = String::new();

    // 解析 multipart 数据，每个文件立即处理
    while let Some(item) = payload.next().await {
        let mut field = item?;
        let content_disposition = field.content_disposition();

        // 获取字段名
        let field_name = content_disposition
            .get_name()
            .ok_or_else(|| actix_web::error::ErrorBadRequest("字段名缺失"))?;

        if field_name == "target_folder" {
            // 读取目标文件夹
            let mut bytes = web::BytesMut::new();
            while let Some(chunk) = field.next().await {
                let data = chunk?;
                bytes.extend_from_slice(&data);
            }
            target_folder = String::from_utf8(bytes.to_vec())
                .map_err(|_| actix_web::error::ErrorBadRequest("目标文件夹格式错误"))?;
        } else if field_name == "files" {
            // 文件字段
            let file_name = content_disposition
                .get_filename()
                .ok_or_else(|| actix_web::error::ErrorBadRequest("文件名缺失"))?
                .to_string();

            // 检查目标文件夹是否已设置
            if target_folder.is_empty() {
                return Ok(HttpResponse::BadRequest().json(serde_json::json!({
                    "error": "目标文件夹未指定"
                })));
            }

            // 创建任务并后台执行上传
            let task_id = task_manager
                .create_and_upload(
                    file_name.clone(),
                    target_folder.clone(),
                    field,
                )
                .await
                .map_err(|e| actix_web::error::ErrorInternalServerError(e))?;

            task_ids.push(task_id);
        }
    }

    if task_ids.is_empty() {
        return Ok(HttpResponse::BadRequest().json(serde_json::json!({
            "error": "没有文件上传"
        })));
    }

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "task_ids": task_ids,
        "message": format!("成功创建 {} 个上传任务", task_ids.len())
    })))
}

/// GET /api/transfer/upload/tasks
/// 获取活跃任务列表（仅进行中的任务，用于轮询）
pub async fn get_tasks(task_manager: web::Data<TaskManager>) -> Result<HttpResponse> {
    let tasks = task_manager.get_all_tasks().await;

    Ok(HttpResponse::Ok().json(TaskListResponse { tasks }))
}

/// 历史记录查询参数
#[derive(Debug, serde::Deserialize)]
pub struct HistoryQuery {
    pub offset: Option<i64>,
    pub limit: Option<i64>,
    pub status: Option<String>,
}

/// GET /api/transfer/upload/history
/// 分页获取上传历史记录
pub async fn get_history(query: web::Query<HistoryQuery>) -> Result<HttpResponse> {
    let offset = query.offset.unwrap_or(0);
    let limit = query.limit.unwrap_or(50).min(200);
    let status_str = query.status.as_deref();

    let total = storage::count_history(status_str)
        .map_err(|e| actix_web::error::ErrorInternalServerError(e))?;

    let history = storage::load_history_page(offset, limit, status_str)
        .map_err(|e| actix_web::error::ErrorInternalServerError(e))?;

    // 将 HistoryItem 转换为 UploadTask
    let items: Vec<UploadTask> = history.into_iter().map(|item| {
        let status = match item.status.as_str() {
            "completed" => UploadStatus::Completed,
            "failed" => UploadStatus::Failed,
            _ => UploadStatus::Failed,
        };
        let progress = if status == UploadStatus::Completed { 100.0 } else { 0.0 };
        UploadTask {
            id: item.id,
            file_name: item.file_name,
            file_size: item.file_size,
            target_folder: item.target_folder,
            status,
            progress,
            uploaded_size: item.file_size,
            error: item.error,
            created_at: item.created_at,
        }
    }).collect();

    let has_more = (offset + limit) < total;

    Ok(HttpResponse::Ok().json(HistoryResponse {
        items,
        total,
        offset,
        limit,
        has_more,
    }))
}

/// GET /api/transfer/upload/task/{task_id}
/// 获取单个任务状态
pub async fn get_task(
    task_id: web::Path<String>,
    task_manager: web::Data<TaskManager>,
) -> Result<HttpResponse> {
    match task_manager.get_task(&task_id).await {
        Some(task) => Ok(HttpResponse::Ok().json(task)),
        None => Ok(HttpResponse::NotFound().json(serde_json::json!({
            "error": "任务不存在"
        }))),
    }
}

/// DELETE /api/transfer/upload/task/{task_id}
/// 删除单个任务（活跃任务或历史记录）
pub async fn delete_task(
    task_id: web::Path<String>,
    task_manager: web::Data<TaskManager>,
) -> Result<HttpResponse> {
    // 先尝试删除活跃任务
    if task_manager.delete_task(&task_id).await {
        return Ok(HttpResponse::Ok().json(serde_json::json!({
            "message": "任务已删除"
        })));
    }

    // 如果不是活跃任务，尝试从历史记录中删除
    match storage::remove_from_history(&task_id) {
        Ok(_) => Ok(HttpResponse::Ok().json(serde_json::json!({
            "message": "历史记录已删除"
        }))),
        Err(_) => Ok(HttpResponse::NotFound().json(serde_json::json!({
            "error": "任务不存在"
        }))),
    }
}

/// POST /api/transfer/upload/tasks/clear
/// 清除所有已完成/失败的任务（历史记录）
pub async fn clear_finished_tasks(
    _task_manager: web::Data<TaskManager>,
) -> Result<HttpResponse> {
    // 获取历史记录数量
    let history_count = match storage::load_history() {
        Ok(history) => history.len(),
        Err(_) => 0,
    };

    // 清空历史记录
    match storage::clear_history() {
        Ok(_) => Ok(HttpResponse::Ok().json(serde_json::json!({
            "message": format!("已清除 {} 个历史记录", history_count),
            "cleared_count": history_count
        }))),
        Err(e) => Ok(HttpResponse::InternalServerError().json(serde_json::json!({
            "error": format!("清除失败: {}", e)
        }))),
    }
}
