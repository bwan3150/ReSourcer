// 文件索引模块 — SQLite 文件索引系统
pub mod models;
pub mod storage;
pub mod scanner;
mod handlers;

use actix_web::web;

/// 注册所有索引相关路由
pub fn routes(cfg: &mut web::ServiceConfig) {
    cfg.service(web::resource("/scan").route(web::post().to(handlers::scan)))
       .service(web::resource("/status").route(web::get().to(handlers::status)))
       .service(web::resource("/files").route(web::get().to(handlers::files)))
       .service(web::resource("/file").route(web::get().to(handlers::file_by_uuid)))
       .service(web::resource("/folders").route(web::get().to(handlers::folders)))
       .service(web::resource("/breadcrumb").route(web::get().to(handlers::breadcrumb)));
}
