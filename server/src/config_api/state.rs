// 配置状态管理
use actix_web::{web, HttpResponse, Result};
use std::path::Path;
use crate::config_api::storage::{load_config, save_config};
use crate::config_api::models::SaveSettingsRequest;

/// GET /api/config/state
/// 获取配置状态 - 整合了 classifier/state 和 settings/state
pub async fn get_state() -> Result<HttpResponse> {
    let state = load_config().map_err(|e| {
        actix_web::error::ErrorInternalServerError(format!("无法加载配置: {}", e))
    })?;

    // 从文件加载预设
    let presets = crate::config_api::storage::load_presets().unwrap_or_default();

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "source_folder": state.source_folder,
        "hidden_folders": state.hidden_folders,
        "backup_source_folders": state.backup_source_folders,
        "presets": presets
    })))
}

/// POST /api/config/save
/// 保存设置 - 整合了 classifier/settings/save 和 settings/save
pub async fn save_settings(req: web::Json<SaveSettingsRequest>) -> Result<HttpResponse> {
    let mut state = load_config().map_err(|e| {
        actix_web::error::ErrorInternalServerError(format!("无法加载配置: {}", e))
    })?;

    // 更新源文件夹
    state.source_folder = req.source_folder.clone();
    state.hidden_folders = req.hidden_folders.clone();

    // 验证源文件夹存在
    let source_path = Path::new(&state.source_folder);
    if !source_path.exists() {
        return Ok(HttpResponse::BadRequest().json(serde_json::json!({
            "error": "源文件夹不存在"
        })));
    }

    // 创建所有需要的分类文件夹
    for category in &req.categories {
        let folder_path = source_path.join(category);
        if !folder_path.exists() {
            std::fs::create_dir_all(&folder_path)?;
        }
    }

    // 保存配置
    save_config(&state).map_err(|e| {
        actix_web::error::ErrorInternalServerError(format!("无法保存配置: {}", e))
    })?;

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "status": "success"
    })))
}
