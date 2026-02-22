// 文件夹操作模块 - 文件夹的列表、创建、排序等
pub mod models;
mod list;
mod create;
mod reorder;
mod open;
pub mod utils;

use actix_web::web;

/// 注册所有文件夹操作相关路由
pub fn routes(cfg: &mut web::ServiceConfig) {
    cfg.service(web::resource("/list").route(web::get().to(list::list_folders)))
       .service(web::resource("/create").route(web::post().to(create::create_folder)))
       .service(web::resource("/reorder").route(web::post().to(reorder::reorder_categories)))
       .service(web::resource("/open").route(web::post().to(open::open_folder)));
}
