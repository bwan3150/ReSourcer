// 上传传输模块 - 处理文件上传任务的创建、管理等操作
pub mod models;
mod task;
pub mod storage;
mod task_manager;
mod chunk;

// 导出 TaskManager
pub use task_manager::TaskManager;
// 导出分片上传会话管理器
pub use chunk::ChunkUploadManager;

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
        )
        // 历史记录分页
        .service(web::resource("/history").route(web::get().to(task::get_history)))
        // 分片上传策略
        .service(web::resource("/policy").route(web::get().to(chunk::get_upload_policy)))
        // 分片上传：初始化 / 上传分片 / 状态 / 完成 / 取消（literal 前缀，避免路由冲突）
        .service(web::resource("/chunk/init").route(web::post().to(chunk::init_chunk_upload)))
        .service(web::resource("/chunk/part/{upload_id}/{index}").route(web::post().to(chunk::upload_chunk_part)))
        .service(web::resource("/chunk/status/{upload_id}").route(web::get().to(chunk::get_chunk_status)))
        .service(web::resource("/chunk/complete/{upload_id}").route(web::post().to(chunk::complete_chunk_upload)))
        .service(web::resource("/chunk/abort/{upload_id}").route(web::post().to(chunk::abort_chunk_upload)));
}
