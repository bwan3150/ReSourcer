// 文件操作模块 - 文件的重命名、移动、信息获取
pub mod models;
mod rename;
mod move_file;
mod info;
mod utils;

use actix_web::web;

/// 注册所有文件操作相关路由
pub fn routes(cfg: &mut web::ServiceConfig) {
    cfg.service(web::resource("/rename").route(web::post().to(rename::rename_file)))
       .service(web::resource("/move").route(web::post().to(move_file::move_file)))
       .service(web::resource("/info").route(web::get().to(info::get_file_info)));
}
