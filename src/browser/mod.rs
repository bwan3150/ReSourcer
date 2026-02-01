// 文件系统浏览模块 - 浏览和创建目录
pub mod models;
mod browse;
mod create;

use actix_web::web;

/// 注册文件系统相关路由
pub fn routes(cfg: &mut web::ServiceConfig) {
    cfg.service(web::resource("/browse").route(web::post().to(browse::browse_directory)))
       .service(web::resource("/create").route(web::post().to(create::create_directory)));
}
