// 下载传输模块 - 处理文件下载任务的创建、管理等操作
pub mod models;
pub mod detector;
mod task;
pub mod downloaders;
pub mod auth;

use actix_web::web;

/// 注册所有下载相关路由
pub fn routes(cfg: &mut web::ServiceConfig) {
    cfg
        // URL 检测
        .service(web::resource("/detect").route(web::post().to(task::detect_url)))
        // 任务管理
        .service(web::resource("/task").route(web::post().to(task::create_task)))
        .service(web::resource("/tasks").route(web::get().to(task::get_tasks)))
        .service(
            web::resource("/task/{id}")
                .route(web::get().to(task::get_task_status))
                .route(web::delete().to(task::cancel_task))
        )
        // 历史记录
        .service(web::resource("/history").route(web::delete().to(task::clear_history)));
}
