use actix_web::{web, HttpResponse, Result};
use actix_multipart::Multipart;
use super::models::*;
use super::task_manager::TaskManager;
use futures_util::StreamExt;

/// 注册所有上传器相关路由
pub fn routes(cfg: &mut web::ServiceConfig) {
    cfg.service(web::resource("/upload").route(web::post().to(upload_file)))
        .service(web::resource("/tasks").route(web::get().to(get_tasks)))
        .service(web::resource("/task/{task_id}").route(web::get().to(get_task)))
        .service(web::resource("/task/{task_id}").route(web::delete().to(delete_task)));
}

/// POST /api/uploader/upload
/// 上传文件（支持批量）- 使用流式处理，边读边写
async fn upload_file(
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

/// GET /api/uploader/tasks
/// 获取所有上传任务
async fn get_tasks(task_manager: web::Data<TaskManager>) -> Result<HttpResponse> {
    let tasks = task_manager.get_all_tasks().await;
    Ok(HttpResponse::Ok().json(TaskListResponse { tasks }))
}

/// GET /api/uploader/task/{task_id}
/// 获取单个任务状态
async fn get_task(
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

/// DELETE /api/uploader/task/{task_id}
/// 删除任务
async fn delete_task(
    task_id: web::Path<String>,
    task_manager: web::Data<TaskManager>,
) -> Result<HttpResponse> {
    if task_manager.delete_task(&task_id).await {
        Ok(HttpResponse::Ok().json(serde_json::json!({
            "message": "任务已删除"
        })))
    } else {
        Ok(HttpResponse::NotFound().json(serde_json::json!({
            "error": "任务不存在"
        })))
    }
}
