// 收藏模块 — 「收藏 / 精选」标记
pub mod models;
mod storage;
mod handlers;

use actix_web::web;

/// 注册所有收藏相关路由
pub fn routes(cfg: &mut web::ServiceConfig) {
    cfg.service(web::resource("/toggle").route(web::post().to(handlers::toggle)))
       .service(web::resource("/list").route(web::get().to(handlers::list)))
       .service(web::resource("/status").route(web::get().to(handlers::status)));
}
