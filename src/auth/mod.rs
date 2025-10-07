pub mod middleware;

use actix_web::web;
use actix_web::{HttpRequest, HttpResponse, Result};
use serde::Deserialize;

#[derive(Deserialize)]
pub struct VerifyRequest {
    pub api_key: String,
}

/// 验证 API Key（POST 带 JSON body）
pub async fn verify_key(
    req: web::Json<VerifyRequest>,
    api_key: web::Data<String>,
) -> Result<HttpResponse> {
    if req.api_key == **api_key {
        Ok(HttpResponse::Ok().json(serde_json::json!({
            "valid": true
        })))
    } else {
        Ok(HttpResponse::Unauthorized().json(serde_json::json!({
            "valid": false,
            "error": "Invalid API Key"
        })))
    }
}

/// 检查当前请求的 API Key 是否有效（GET 使用 Cookie）
/// 这个端点需要通过中间件验证，所以如果能访问到就说明 key 有效
pub async fn check_key(_req: HttpRequest) -> Result<HttpResponse> {
    // 能访问到这里说明已经通过了 middleware 的验证
    Ok(HttpResponse::Ok().json(serde_json::json!({
        "valid": true
    })))
}

/// 配置认证路由
pub fn routes(cfg: &mut web::ServiceConfig) {
    cfg.service(
        web::resource("/verify")
            .route(web::post().to(verify_key))
    )
    .service(
        web::resource("/check")
            .route(web::get().to(check_key))
    );
}
