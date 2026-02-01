// 上传传输模块 - 处理文件上传任务的创建、管理等操作
pub mod models;
mod task;
pub mod storage;
mod task_manager;

// 导出 TaskManager
pub use task_manager::TaskManager;

use actix_web::web;

/// 注册所有上传相关路由
pub fn routes(cfg: &mut web::ServiceConfig) {
    cfg.service(web::resource("/task").route(web::post().to(task::upload_file)))
        .service(web::resource("/tasks").route(web::get().to(task::get_tasks)))
        .service(web::resource("/tasks/clear").route(web::post().to(task::clear_finished_tasks)))
        .service(
            web::resource("/task/{task_id}")
                .route(web::get().to(task::get_task))
                .route(web::delete().to(task::delete_task))
        );
}
