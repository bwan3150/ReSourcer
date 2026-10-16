// 文件操作模块 - 文件的重命名、移动、信息获取
pub mod models;
mod rename;
mod move_file;
mod delete;
mod batch;
mod ops;
mod info;
mod metadata;
mod utils;

use actix_web::web;

/// 注册所有文件操作相关路由
pub fn routes(cfg: &mut web::ServiceConfig) {
    cfg.service(web::resource("/rename").route(web::post().to(rename::rename_file)))
       .service(web::resource("/move").route(web::post().to(move_file::move_file)))
       .service(web::resource("/delete").route(web::post().to(delete::delete_file)))
       .service(web::resource("/batch/move").route(web::post().to(batch::batch_move_files)))
       .service(web::resource("/batch/delete").route(web::post().to(batch::batch_delete_files)))
       .service(web::resource("/info").route(web::get().to(info::get_file_info)))
       .service(web::resource("/metadata").route(web::get().to(metadata::get_file_metadata)));
}
