// 传输操作模块 - 包含下载和上传子模块
pub mod download;
pub mod upload;

use actix_web::web;

/// 注册所有传输相关路由
pub fn routes(cfg: &mut web::ServiceConfig) {
    // 下载子模块路由
    cfg.service(web::scope("/download").configure(download::routes));
    // 上传子模块路由
    cfg.service(web::scope("/upload").configure(upload::routes));
}
