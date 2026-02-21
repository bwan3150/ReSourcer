// 标签模块 — 标签 CRUD 与文件-标签关联
pub mod models;
mod storage;
mod handlers;

use actix_web::web;

/// 注册所有标签相关路由
pub fn routes(cfg: &mut web::ServiceConfig) {
    cfg.service(web::resource("/list").route(web::get().to(handlers::list_tags)))
       .service(web::resource("/create").route(web::post().to(handlers::create_tag)))
       .service(web::resource("/update/{id}").route(web::put().to(handlers::update_tag)))
       .service(web::resource("/delete/{id}").route(web::delete().to(handlers::delete_tag)))
       .service(web::resource("/file").route(web::get().to(handlers::get_file_tags))
                                      .route(web::post().to(handlers::set_file_tags)))
       .service(web::resource("/files").route(web::post().to(handlers::get_files_tags)));
}
