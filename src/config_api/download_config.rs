// 下载器配置管理
use actix_web::{web, HttpResponse, Result};
use crate::config_api::models::{DownloadConfigResponse as ConfigResponse, SaveDownloadConfigRequest as SaveConfigRequest};

/// GET /api/config/download
/// 获取下载器配置和认证状态
pub async fn get_download_config() -> Result<HttpResponse> {
    let config = crate::config_api::storage::load_config()
        .map_err(|e| actix_web::error::ErrorInternalServerError(e))?;

    let auth_status = crate::transfer::download::auth::check_all_auth_status();

    // 读取 yt-dlp 版本
    use crate::static_files::ConfigAsset;
    use serde::Deserialize;

    #[derive(Deserialize)]
    struct DependencyInfo {
        version: String,
    }

    #[derive(Deserialize)]
    struct Dependencies {
        #[serde(rename = "yt-dlp")]
        yt_dlp: DependencyInfo,
    }

    let ytdlp_version = if let Some(config_file) = ConfigAsset::get("dependencies.json") {
        match serde_json::from_slice::<Dependencies>(&config_file.data) {
            Ok(deps) => deps.yt_dlp.version,
            Err(_) => "unknown".to_string(),
        }
    } else {
        "unknown".to_string()
    };

    Ok(HttpResponse::Ok().json(ConfigResponse {
        source_folder: config.source_folder,
        hidden_folders: config.hidden_folders,
        use_cookies: config.use_cookies,
        auth_status,
        ytdlp_version,
    }))
}

/// POST /api/config/download
/// 保存下载器配置
pub async fn save_download_config(req: web::Json<SaveConfigRequest>) -> Result<HttpResponse> {
    // 加载现有配置
    let mut config = crate::config_api::storage::load_config()
        .map_err(|e| actix_web::error::ErrorInternalServerError(e))?;

    // 更新下载器相关字段
    config.source_folder = req.source_folder.clone();
    config.hidden_folders = req.hidden_folders.clone();
    config.use_cookies = req.use_cookies;

    // 保存配置
    crate::config_api::storage::save_config(&config)
        .map_err(|e| actix_web::error::ErrorInternalServerError(e))?;

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "status": "success"
    })))
}
