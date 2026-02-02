// 预览操作模块 - 文件预览、缩略图生成、内容服务等
pub mod models;
mod files;
mod thumbnail;
mod content;
mod utils;

use actix_web::web;

/// 注册所有预览相关路由
pub fn routes(cfg: &mut web::ServiceConfig) {
    cfg.service(web::resource("/files").route(web::get().to(files::get_files)))
       .service(web::resource("/thumbnail").route(web::get().to(thumbnail::get_thumbnail)))
       .service(web::resource("/content/{path:.*}").route(web::get().to(content::serve_file)));
}
