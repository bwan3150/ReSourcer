use actix_web::{web, HttpResponse, Result};
use super::models::*;

// 注册所有上传器相关路由
pub fn routes(cfg: &mut web::ServiceConfig) {
    cfg.service(web::resource("/upload").route(web::post().to(upload_file)))
       .service(web::resource("/devices").route(web::get().to(get_devices)))
       .service(web::resource("/connect").route(web::post().to(connect_device)));
}

// 上传文件
async fn upload_file() -> Result<HttpResponse> {
    // TODO: 实现文件上传逻辑
    // 1. 接收 multipart 数据
    // 2. 保存到指定目录
    // 3. 返回上传结果

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "status": "success",
        "message": "文件上传功能（待实现）"
    })))
}

// 获取已连接设备列表
async fn get_devices() -> Result<HttpResponse> {
    // TODO: 实现获取设备列表逻辑

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "status": "success",
        "devices": []
    })))
}

// 连接新设备
async fn connect_device() -> Result<HttpResponse> {
    // TODO: 实现设备连接逻辑（二维码扫描后）

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "status": "success",
        "message": "设备连接功能（待实现）"
    })))
}
