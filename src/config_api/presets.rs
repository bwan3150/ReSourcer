// 预设管理功能
use actix_web::{web, HttpResponse, Result};
use super::models::{PresetRequest, PresetLoadResponse};

/// POST /api/config/preset/load
/// 加载预设
pub async fn load_preset(req: web::Json<PresetRequest>) -> Result<HttpResponse> {
    let presets = crate::config_api::storage::load_presets().unwrap_or_default();

    if let Some(preset) = presets.iter().find(|p| p.name == req.name) {
        Ok(HttpResponse::Ok().json(PresetLoadResponse {
            status: "success".to_string(),
            categories: preset.categories.clone(),
            preset_name: preset.name.clone(),
        }))
    } else {
        Ok(HttpResponse::BadRequest().json(serde_json::json!({
            "error": "预设不存在"
        })))
    }
}

/// POST /api/config/preset/save
/// 保存预设 - 预设是只读的，从 config/presets.json 读取
pub async fn save_preset(_req: web::Json<PresetRequest>) -> Result<HttpResponse> {
    Ok(HttpResponse::BadRequest().json(serde_json::json!({
        "error": "预设是只读的，从 config/presets.json 加载"
    })))
}

/// DELETE /api/config/preset/delete
/// 删除预设 - 预设是只读的，从 config/presets.json 读取
pub async fn delete_preset(_req: web::Json<PresetRequest>) -> Result<HttpResponse> {
    Ok(HttpResponse::BadRequest().json(serde_json::json!({
        "error": "预设是只读的，从 config/presets.json 加载"
    })))
}
