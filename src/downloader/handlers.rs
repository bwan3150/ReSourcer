// API 路由处理器：实现所有下载器相关的 HTTP 端点
use actix_web::{web, HttpResponse, Result};
use std::fs;
use std::path::Path;
use super::models::*;
use super::config::ConfigData;
use super::task_manager::TaskManager;

// TaskManager 的共享状态类型
pub type TaskManagerState = web::Data<TaskManager>;

// ============================================================================
// URL 检测
// ============================================================================

/// POST /api/downloader/detect
/// 检测 URL 对应的平台和下载器
async fn detect_url(req: web::Json<DetectRequest>) -> Result<HttpResponse> {
    let result = super::detector::detect(&req.url);
    Ok(HttpResponse::Ok().json(result))
}

// ============================================================================
// 配置管理
// ============================================================================

/// GET /api/downloader/config
/// 获取配置和认证状态
async fn get_config() -> Result<HttpResponse> {
    let config = super::config::load_config()
        .map_err(|e| actix_web::error::ErrorInternalServerError(e))?;

    let auth_status = super::auth::check_all_auth_status();

    Ok(HttpResponse::Ok().json(ConfigResponse {
        source_folder: config.source_folder,
        hidden_folders: config.hidden_folders,
        use_cookies: config.use_cookies,
        auth_status,
    }))
}

/// POST /api/downloader/config
/// 保存配置
async fn save_config(req: web::Json<SaveConfigRequest>) -> Result<HttpResponse> {
    let config = ConfigData {
        source_folder: req.source_folder.clone(),
        hidden_folders: req.hidden_folders.clone(),
        use_cookies: req.use_cookies,
    };

    super::config::save_config(&config)
        .map_err(|e| actix_web::error::ErrorInternalServerError(e))?;

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "status": "success"
    })))
}

// ============================================================================
// 文件夹管理
// ============================================================================

/// GET /api/downloader/folders
/// 获取可用的文件夹列表（与 classifier 逻辑相同）
async fn get_folders(query: web::Query<std::collections::HashMap<String, String>>) -> Result<HttpResponse> {
    let source_folder = query.get("source_folder");

    if source_folder.is_none() {
        // 如果没有提供 source_folder，尝试从配置读取
        let config = super::config::load_config().ok();
        if let Some(cfg) = config {
            if !cfg.source_folder.is_empty() {
                return get_folders_from_path(&cfg.source_folder, &cfg.hidden_folders);
            }
        }
        return Ok(HttpResponse::Ok().json(Vec::<FolderInfo>::new()));
    }

    let source_folder = source_folder.unwrap();
    let config = super::config::load_config().unwrap_or_else(|_| ConfigData {
        source_folder: String::new(),
        hidden_folders: vec![],
        use_cookies: false,
    });

    get_folders_from_path(source_folder, &config.hidden_folders)
}

/// 辅助函数：从路径获取文件夹列表
fn get_folders_from_path(source_folder: &str, hidden_folders: &[String]) -> Result<HttpResponse> {
    let source_path = Path::new(source_folder);

    if !source_path.exists() || !source_path.is_dir() {
        return Ok(HttpResponse::Ok().json(Vec::<FolderInfo>::new()));
    }

    let mut folders = Vec::new();

    if let Ok(entries) = fs::read_dir(source_path) {
        for entry in entries.flatten() {
            if let Ok(metadata) = entry.metadata() {
                if metadata.is_dir() {
                    let folder_name = entry.file_name().to_string_lossy().to_string();
                    // 跳过隐藏文件夹（以.开头的）
                    if !folder_name.starts_with('.') {
                        let hidden = hidden_folders.contains(&folder_name);
                        folders.push(FolderInfo {
                            name: folder_name,
                            hidden,
                        });
                    }
                }
            }
        }
    }

    folders.sort_by(|a, b| a.name.cmp(&b.name));
    Ok(HttpResponse::Ok().json(folders))
}

// ============================================================================
// 任务管理
// ============================================================================

/// POST /api/downloader/task
/// 创建下载任务（包含认证验证）
async fn create_task(
    req: web::Json<DownloadRequest>,
    task_manager: TaskManagerState,
) -> Result<HttpResponse> {
    // 1. 检测 URL 的平台和下载器
    let detect_result = super::detector::detect(&req.url);

    // 2. 确定使用的下载器（用户可覆盖）
    let downloader = req.downloader.clone()
        .unwrap_or(detect_result.downloader.clone());

    // 3. 如果需要认证，检查是否有认证信息
    if detect_result.requires_auth {
        match detect_result.platform {
            Platform::X => {
                if !super::auth::x::has_cookies() {
                    return Ok(HttpResponse::BadRequest().json(serde_json::json!({
                        "error": "X 平台需要认证，请先上传 cookies",
                        "platform": "x",
                        "requires_auth": true
                    })));
                }
            },
            Platform::Pixiv => {
                if !super::auth::pixiv::has_token() {
                    return Ok(HttpResponse::BadRequest().json(serde_json::json!({
                        "error": "Pixiv 平台需要认证，请先上传 token",
                        "platform": "pixiv",
                        "requires_auth": true
                    })));
                }
            },
            _ => {}
        }
    }

    // 4. 验证 save_folder（如果非空）
    if !req.save_folder.is_empty() {
        let config = super::config::load_config()
            .map_err(|e| actix_web::error::ErrorInternalServerError(e))?;

        if config.source_folder.is_empty() {
            return Ok(HttpResponse::BadRequest().json(serde_json::json!({
                "error": "请先在设置中配置源文件夹"
            })));
        }

        let target_folder = Path::new(&config.source_folder).join(&req.save_folder);

        // 如果文件夹不存在，创建它
        if !target_folder.exists() {
            fs::create_dir_all(&target_folder)
                .map_err(|e| actix_web::error::ErrorInternalServerError(
                    format!("无法创建文件夹: {}", e)
                ))?;
        }
    }

    // 5. 构建完整的保存路径
    let config = super::config::load_config()
        .map_err(|e| actix_web::error::ErrorInternalServerError(e))?;

    let save_path = if req.save_folder.is_empty() {
        config.source_folder.clone()
    } else {
        Path::new(&config.source_folder)
            .join(&req.save_folder)
            .to_string_lossy()
            .to_string()
    };

    // 6. 创建下载任务
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

/// GET /api/downloader/tasks
/// 获取所有任务列表
async fn get_tasks(task_manager: TaskManagerState) -> Result<HttpResponse> {
    let tasks = task_manager.get_all_tasks().await;

    Ok(HttpResponse::Ok().json(TaskListResponse {
        status: "success".to_string(),
        tasks,
    }))
}

/// GET /api/downloader/task/:id
/// 获取单个任务状态（用于前端轮询）
async fn get_task_status(
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

/// DELETE /api/downloader/task/:id
/// 取消任务
async fn cancel_task(
    task_id: web::Path<String>,
    task_manager: TaskManagerState,
) -> Result<HttpResponse> {
    task_manager
        .cancel_task(&task_id)
        .await
        .map_err(|e| actix_web::error::ErrorBadRequest(e))?;

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "status": "success",
        "message": "任务已取消"
    })))
}

// ============================================================================
// 认证管理
// ============================================================================

/// POST /api/downloader/credentials/:platform
/// 上传认证信息
async fn upload_credentials(
    platform: web::Path<String>,
    body: String,
) -> Result<HttpResponse> {
    match platform.as_str() {
        "x" => {
            super::auth::x::save_cookies(&body)
                .map_err(|e| actix_web::error::ErrorInternalServerError(e))?;
        },
        "pixiv" => {
            // 假设 body 就是 token
            super::auth::pixiv::save_token(&body)
                .map_err(|e| actix_web::error::ErrorInternalServerError(e))?;
        },
        _ => {
            return Ok(HttpResponse::BadRequest().json(serde_json::json!({
                "error": "不支持的平台"
            })));
        }
    }

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "status": "success",
        "message": "认证信息已保存"
    })))
}

/// DELETE /api/downloader/credentials/:platform
/// 删除认证信息
async fn delete_credentials(platform: web::Path<String>) -> Result<HttpResponse> {
    match platform.as_str() {
        "x" => {
            super::auth::x::delete_cookies()
                .map_err(|e| actix_web::error::ErrorInternalServerError(e))?;
        },
        "pixiv" => {
            super::auth::pixiv::delete_all()
                .map_err(|e| actix_web::error::ErrorInternalServerError(e))?;
        },
        _ => {
            return Ok(HttpResponse::BadRequest().json(serde_json::json!({
                "error": "不支持的平台"
            })));
        }
    }

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "status": "success",
        "message": "认证信息已删除"
    })))
}

// ============================================================================
// 路由注册
// ============================================================================

/// 注册所有下载器相关路由
pub fn routes(cfg: &mut web::ServiceConfig) {
    cfg
        // URL 检测
        .service(web::resource("/detect").route(web::post().to(detect_url)))
        // 配置管理
        .service(web::resource("/config").route(web::get().to(get_config)))
        .service(web::resource("/config").route(web::post().to(save_config)))
        // 文件夹管理
        .service(web::resource("/folders").route(web::get().to(get_folders)))
        // 任务管理
        .service(web::resource("/task").route(web::post().to(create_task)))
        .service(web::resource("/tasks").route(web::get().to(get_tasks)))
        .service(web::resource("/task/{id}").route(web::get().to(get_task_status)))
        .service(web::resource("/task/{id}").route(web::delete().to(cancel_task)))
        // 认证管理
        .service(web::resource("/credentials/{platform}").route(web::post().to(upload_credentials)))
        .service(web::resource("/credentials/{platform}").route(web::delete().to(delete_credentials)));
}
