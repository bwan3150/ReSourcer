pub mod middleware;

use actix_web::web;
use actix_web::{HttpResponse, Result};
use serde::Deserialize;

#[derive(Deserialize)]
pub struct VerifyRequest {
    pub api_key: String,
}

/// 验证 API Key
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

/// 配置认证路由
pub fn routes(cfg: &mut web::ServiceConfig) {
    cfg.service(
        web::resource("/verify")
            .route(web::post().to(verify_key))
    );
}
