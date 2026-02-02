// 认证管理功能
use actix_web::{web, HttpResponse, Result};

/// POST /api/config/credentials/{platform}
/// 上传认证信息
pub async fn upload_credentials(
    platform: web::Path<String>,
    body: String,
) -> Result<HttpResponse> {
    eprintln!("[上传认证] 平台: {}, 内容长度: {} bytes", platform, body.len());

    match platform.as_str() {
        "x" => {
            eprintln!("[上传认证] 保存 X cookies...");
            crate::transfer::download::auth::x::save_cookies(&body)
                .map_err(|e| {
                    eprintln!("[上传认证] 保存失败: {}", e);
                    actix_web::error::ErrorInternalServerError(e)
                })?;
            eprintln!("[上传认证] X cookies 保存成功");
        },
        "pixiv" => {
            eprintln!("[上传认证] 保存 Pixiv token...");
            crate::transfer::download::auth::pixiv::save_token(&body)
                .map_err(|e| {
                    eprintln!("[上传认证] 保存失败: {}", e);
                    actix_web::error::ErrorInternalServerError(e)
                })?;
            eprintln!("[上传认证] Pixiv token 保存成功");
        },
        _ => {
            eprintln!("[上传认证] 不支持的平台: {}", platform);
            return Ok(HttpResponse::BadRequest().json(serde_json::json!({
                "error": "不支持的平台"
            })));
        }
    }

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "status": "success",
        "message": "认证信息已保存"
    })))
}

/// DELETE /api/config/credentials/{platform}
/// 删除认证信息
pub async fn delete_credentials(platform: web::Path<String>) -> Result<HttpResponse> {
    match platform.as_str() {
        "x" => {
            crate::transfer::download::auth::x::delete_cookies()
                .map_err(|e| actix_web::error::ErrorInternalServerError(e))?;
        },
        "pixiv" => {
            crate::transfer::download::auth::pixiv::delete_all()
                .map_err(|e| actix_web::error::ErrorInternalServerError(e))?;
        },
        _ => {
            return Ok(HttpResponse::BadRequest().json(serde_json::json!({
                "error": "不支持的平台"
            })));
        }
    }

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "status": "success",
        "message": "认证信息已删除"
    })))
}
