use actix_web::{web, HttpResponse, Result};
use std::fs;
use std::path::Path;
use super::models::*;
use crate::classifier::config::{load_config, save_config, get_config_path, ensure_config_dir};

// 注册所有设置相关路由
pub fn routes(cfg: &mut web::ServiceConfig) {
    cfg.service(web::resource("/config").route(web::get().to(get_config)))
       .service(web::resource("/folder").route(web::post().to(set_folder)))
       .service(web::resource("/folders").route(web::get().to(get_folders)))
       .service(web::resource("/folder/create").route(web::post().to(create_folder)))
       .service(web::resource("/folder/toggle").route(web::post().to(toggle_folder)))
       .service(web::resource("/preset/apply").route(web::post().to(apply_preset)));
}

// 获取配置
async fn get_config() -> Result<HttpResponse> {
    let config_file = get_config_path().join("settings.json");

    if !config_file.exists() {
        return Ok(HttpResponse::Ok().json(SettingsConfig {
            main_folder: String::new(),
            categories: Vec::new(),
            hidden_categories: Vec::new(),
        }));
    }

    let content = fs::read_to_string(&config_file)?;
    let config: SettingsConfig = serde_json::from_str(&content)?;

    Ok(HttpResponse::Ok().json(config))
}

// 设置主文件夹
async fn set_folder(req: web::Json<SetFolderRequest>) -> Result<HttpResponse> {
    ensure_config_dir().map_err(actix_web::error::ErrorInternalServerError)?;

    let folder_path = Path::new(&req.path);
    if !folder_path.exists() {
        return Ok(HttpResponse::BadRequest().json(serde_json::json!({
            "error": "Folder does not exist"
        })));
    }

    let config_file = get_config_path().join("settings.json");
    let mut config = if config_file.exists() {
        let content = fs::read_to_string(&config_file)?;
        serde_json::from_str(&content)?
    } else {
        SettingsConfig {
            main_folder: String::new(),
            categories: Vec::new(),
            hidden_categories: Vec::new(),
        }
    };

    config.main_folder = req.path.clone();

    // 同时更新 classifier 配置
    let mut app_state = load_config().map_err(actix_web::error::ErrorInternalServerError)?;
    app_state.source_folder = req.path.clone();
    save_config(&app_state).map_err(actix_web::error::ErrorInternalServerError)?;

    let content = serde_json::to_string_pretty(&config)?;
    fs::write(&config_file, content)?;

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "status": "success"
    })))
}

// 获取文件夹列表
async fn get_folders() -> Result<HttpResponse> {
    let config_file = get_config_path().join("settings.json");

    if !config_file.exists() {
        return Ok(HttpResponse::Ok().json(FoldersResponse {
            folders: Vec::new(),
            hidden: Vec::new(),
        }));
    }

    let content = fs::read_to_string(&config_file)?;
    let mut config: SettingsConfig = serde_json::from_str(&content)?;

    if config.main_folder.is_empty() {
        return Ok(HttpResponse::Ok().json(FoldersResponse {
            folders: Vec::new(),
            hidden: config.hidden_categories,
        }));
    }

    // 扫描实际的子文件夹
    let mut folders = Vec::new();
    if let Ok(entries) = fs::read_dir(&config.main_folder) {
        for entry in entries.flatten() {
            if let Ok(metadata) = entry.metadata() {
                if metadata.is_dir() {
                    if let Some(name) = entry.file_name().to_str() {
                        folders.push(name.to_string());
                    }
                }
            }
        }
    }

    folders.sort();
    config.categories = folders.clone();

    // 保存更新后的配置
    let content = serde_json::to_string_pretty(&config)?;
    fs::write(&config_file, content)?;

    Ok(HttpResponse::Ok().json(FoldersResponse {
        folders,
        hidden: config.hidden_categories,
    }))
}

// 创建文件夹
async fn create_folder(req: web::Json<CreateFolderRequest>) -> Result<HttpResponse> {
    let config_file = get_config_path().join("settings.json");

    if !config_file.exists() {
        return Ok(HttpResponse::BadRequest().json(serde_json::json!({
            "error": "Please set main folder first"
        })));
    }

    let content = fs::read_to_string(&config_file)?;
    let config: SettingsConfig = serde_json::from_str(&content)?;

    if config.main_folder.is_empty() {
        return Ok(HttpResponse::BadRequest().json(serde_json::json!({
            "error": "Main folder not set"
        })));
    }

    let folder_path = Path::new(&config.main_folder).join(&req.name);
    fs::create_dir_all(&folder_path)?;

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "status": "success"
    })))
}

// 切换文件夹显示/隐藏
async fn toggle_folder(req: web::Json<ToggleFolderRequest>) -> Result<HttpResponse> {
    let config_file = get_config_path().join("settings.json");

    if !config_file.exists() {
        return Ok(HttpResponse::BadRequest().json(serde_json::json!({
            "error": "Config not found"
        })));
    }

    let content = fs::read_to_string(&config_file)?;
    let mut config: SettingsConfig = serde_json::from_str(&content)?;

    if req.hide {
        if !config.hidden_categories.contains(&req.name) {
            config.hidden_categories.push(req.name.clone());
        }
    } else {
        config.hidden_categories.retain(|n| n != &req.name);
    }

    let content = serde_json::to_string_pretty(&config)?;
    fs::write(&config_file, content)?;

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "status": "success"
    })))
}

// 应用预设
async fn apply_preset(req: web::Json<ApplyPresetRequest>) -> Result<HttpResponse> {
    let config_file = get_config_path().join("settings.json");

    if !config_file.exists() {
        return Ok(HttpResponse::BadRequest().json(serde_json::json!({
            "error": "Please set main folder first"
        })));
    }

    let content = fs::read_to_string(&config_file)?;
    let config: SettingsConfig = serde_json::from_str(&content)?;

    if config.main_folder.is_empty() {
        return Ok(HttpResponse::BadRequest().json(serde_json::json!({
            "error": "Main folder not set"
        })));
    }

    for folder_name in &req.folders {
        let folder_path = Path::new(&config.main_folder).join(folder_name);
        if !folder_path.exists() {
            fs::create_dir_all(&folder_path)?;
        }
    }

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "status": "success",
        "created": req.folders.len()
    })))
}
