// 下载任务管理功能（从transfer/download.rs迁移）
use actix_web::{web, HttpResponse, Result};
use std::path::Path;
use super::models::*;
use super::TaskManager;
use super::detector;
use super::storage;

// TaskManager 的共享状态类型
pub type TaskManagerState = web::Data<TaskManager>;

/// POST /api/transfer/download/detect
/// 检测 URL 对应的平台和下载器
pub async fn detect_url(req: web::Json<DetectRequest>) -> Result<HttpResponse> {
    let result = detector::detect(&req.url);
    Ok(HttpResponse::Ok().json(result))
}

/// POST /api/transfer/download/task
/// 创建下载任务（包含认证验证）
pub async fn create_task(
    req: web::Json<DownloadRequest>,
    task_manager: TaskManagerState,
) -> Result<HttpResponse> {
    // 1. 检测 URL 的平台和下载器
    let detect_result = detector::detect(&req.url);

    // 2. 确定使用的下载器（用户可覆盖）
    let downloader = req.downloader.clone()
        .unwrap_or(detect_result.downloader.clone());

    // 3. 验证 save_folder（如果非空）
    if !req.save_folder.is_empty() {
        let config = storage::load_config()
            .map_err(|e| actix_web::error::ErrorInternalServerError(e))?;

        if config.source_folder.is_empty() {
            return Ok(HttpResponse::BadRequest().json(serde_json::json!({
                "error": "请先在设置中配置源文件夹"
            })));
        }

        let target_folder = Path::new(&config.source_folder).join(&req.save_folder);

        // 检查文件夹是否存在（不自动创建）
        if !target_folder.exists() {
            return Ok(HttpResponse::BadRequest().json(serde_json::json!({
                "error": format!("目标文件夹不存在: {}", req.save_folder)
            })));
        }

        // 确保是目录而非文件
        if !target_folder.is_dir() {
            return Ok(HttpResponse::BadRequest().json(serde_json::json!({
                "error": format!("目标路径不是文件夹: {}", req.save_folder)
            })));
        }
    }

    // 4. 构建完整的保存路径
    let config = storage::load_config()
        .map_err(|e| actix_web::error::ErrorInternalServerError(e))?;

    let save_path = if req.save_folder.is_empty() {
        config.source_folder.clone()
    } else {
        Path::new(&config.source_folder)
            .join(&req.save_folder)
            .to_string_lossy()
            .to_string()
    };

    // 5. 创建下载任务
    let task_id = task_manager
        .create_task(
            req.url.clone(),
            detect_result.platform,
            downloader,
            save_path,
            req.format.clone(),
        )
        .await
        .map_err(|e| actix_web::error::ErrorInternalServerError(e))?;

    Ok(HttpResponse::Ok().json(CreateTaskResponse {
        status: "success".to_string(),
        task_id,
        message: "下载任务已创建".to_string(),
    }))
}

/// GET /api/transfer/download/tasks
/// 获取所有任务列表（进行中的任务 + 历史记录）
pub async fn get_tasks(task_manager: TaskManagerState) -> Result<HttpResponse> {
    let mut tasks = task_manager.get_all_tasks().await;

    // 加载历史记录并转换为任务格式
    if let Ok(history) = storage::load_history() {
        for item in history {
            // 将字符串转换为 Platform 枚举
            let platform = match item.platform.as_str() {
                "YouTube" => Platform::YouTube,
                "Bilibili" => Platform::Bilibili,
                "X" => Platform::X,
                "TikTok" => Platform::TikTok,
                "Pixiv" => Platform::Pixiv,
                "Xiaohongshu" => Platform::Xiaohongshu,
                _ => Platform::Unknown,
            };

            // 将字符串转换为 TaskStatus 枚举
            let status = match item.status.as_str() {
                "completed" => TaskStatus::Completed,
                "failed" => TaskStatus::Failed,
                "cancelled" => TaskStatus::Cancelled,
                _ => TaskStatus::Failed,
            };

            let progress = if status == TaskStatus::Completed { 100.0 } else { 0.0 };

            tasks.push(DownloadTask {
                id: item.id,
                url: item.url,
                platform,
                downloader: DownloaderType::YtDlp,
                status,
                progress,
                speed: None,
                eta: None,
                save_folder: String::new(),
                file_name: item.file_name,
                file_path: item.file_path,
                error: item.error,
                created_at: item.created_at,
            });
        }
    }

    Ok(HttpResponse::Ok().json(TaskListResponse {
        status: "success".to_string(),
        tasks,
    }))
}

/// GET /api/transfer/download/task/{id}
/// 获取单个任务状态（用于前端轮询）
pub async fn get_task_status(
    task_id: web::Path<String>,
    task_manager: TaskManagerState,
) -> Result<HttpResponse> {
    let task = task_manager.get_task(&task_id).await;

    match task {
        Some(t) => Ok(HttpResponse::Ok().json(TaskResponse {
            status: "success".to_string(),
            task: t,
        })),
        None => Ok(HttpResponse::NotFound().json(serde_json::json!({
            "error": "任务不存在"
        }))),
    }
}

/// DELETE /api/transfer/download/task/{id}
/// 取消进行中的任务或删除历史记录
pub async fn cancel_task(
    task_id: web::Path<String>,
    task_manager: TaskManagerState,
) -> Result<HttpResponse> {
    // 先尝试取消进行中的任务
    match task_manager.cancel_task(&task_id).await {
        Ok(_) => {
            return Ok(HttpResponse::Ok().json(serde_json::json!({
                "status": "success",
                "message": "任务已取消"
            })));
        }
        Err(_) => {
            // 如果不是进行中的任务，尝试从历史记录中删除
            match storage::remove_from_history(&task_id) {
                Ok(_) => {
                    return Ok(HttpResponse::Ok().json(serde_json::json!({
                        "status": "success",
                        "message": "任务已删除"
                    })));
                }
                Err(_) => {
                    return Ok(HttpResponse::NotFound().json(serde_json::json!({
                        "error": "任务不存在"
                    })));
                }
            }
        }
    }
}

/// DELETE /api/transfer/download/history
/// 清空历史记录（进行中的任务不受影响）
pub async fn clear_history() -> Result<HttpResponse> {
    storage::clear_history()
        .map_err(|e| actix_web::error::ErrorInternalServerError(e))?;

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "status": "success",
        "message": "历史记录已清空"
    })))
}
