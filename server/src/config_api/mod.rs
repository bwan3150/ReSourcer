// 配置操作模块 - 处理应用配置、下载器配置、源文件夹、认证等配置相关操作
pub mod models;
pub mod storage;
mod state;
mod sources;
mod download_config;
mod credentials;
mod presets;

use actix_web::web;

/// 注册所有配置相关路由
pub fn routes(cfg: &mut web::ServiceConfig) {
    cfg
        // 配置状态
        .service(web::resource("/state").route(web::get().to(state::get_state)))
        .service(web::resource("/save").route(web::post().to(state::save_settings)))
        // 下载器配置
        .service(web::resource("/download").route(web::get().to(download_config::get_download_config)))
        .service(web::resource("/download").route(web::post().to(download_config::save_download_config)))
        // 源文件夹管理
        .service(web::resource("/sources").route(web::get().to(sources::list_source_folders)))
        .service(web::resource("/sources/add").route(web::post().to(sources::add_source_folder)))
        .service(web::resource("/sources/remove").route(web::post().to(sources::remove_source_folder)))
        .service(web::resource("/sources/switch").route(web::post().to(sources::switch_source_folder)))
        // 认证管理
        .service(
            web::resource("/credentials/{platform}")
                .route(web::post().to(credentials::upload_credentials))
                .route(web::delete().to(credentials::delete_credentials))
        )
        // 预设管理
        .service(web::resource("/preset/load").route(web::post().to(presets::load_preset)))
        .service(web::resource("/preset/save").route(web::post().to(presets::save_preset)))
        .service(web::resource("/preset/delete").route(web::delete().to(presets::delete_preset)));
}
