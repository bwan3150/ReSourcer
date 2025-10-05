use actix_web::{web, HttpResponse, Result};
use super::models::*;

// 注册所有下载器相关路由
pub fn routes(cfg: &mut web::ServiceConfig) {
    cfg.service(web::resource("/task").route(web::post().to(create_task)))
       .service(web::resource("/tasks").route(web::get().to(get_tasks)))
       .service(web::resource("/task/{id}").route(web::get().to(get_task_status)))
       .service(web::resource("/task/{id}").route(web::delete().to(cancel_task)));
}

// 创建下载任务
async fn create_task(req: web::Json<DownloadRequest>) -> Result<HttpResponse> {
    // TODO: 实现下载任务创建逻辑
    // 1. 生成任务 ID
    // 2. 调用 yt-dlp 开始下载
    // 3. 返回任务信息

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "status": "success",
        "message": "下载任务创建成功（功能待实现）",
        "url": req.url
    })))
}

// 获取所有任务列表
async fn get_tasks() -> Result<HttpResponse> {
    // TODO: 实现获取任务列表逻辑

    Ok(HttpResponse::Ok().json(TaskStatusResponse {
        status: "success".to_string(),
        tasks: vec![],
    }))
}

// 获取单个任务状态
async fn get_task_status(id: web::Path<String>) -> Result<HttpResponse> {
    // TODO: 实现查询任务状态逻辑

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "status": "success",
        "task_id": id.as_str(),
        "message": "任务状态查询（功能待实现）"
    })))
}

// 取消任务
async fn cancel_task(id: web::Path<String>) -> Result<HttpResponse> {
    // TODO: 实现取消任务逻辑

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "status": "success",
        "task_id": id.as_str(),
        "message": "任务已取消（功能待实现）"
    })))
}
