use actix_web::{web, HttpResponse, Result};
use std::fs;
use std::path::Path;
use super::models::*;
use super::config::{load_config, save_config, SUPPORTED_EXTENSIONS};

// 注册所有分类器相关路由
pub fn routes(cfg: &mut web::ServiceConfig) {
    cfg.service(web::resource("/state").route(web::get().to(get_state)))
       .service(web::resource("/folders").route(web::get().to(get_folders)))
       .service(web::resource("/settings/save").route(web::post().to(save_settings)))
       .service(web::resource("/folder/create").route(web::post().to(create_folder)))
       .service(web::resource("/files").route(web::get().to(get_files)))
       .service(web::resource("/move").route(web::post().to(move_file)))
       .service(web::resource("/preset/save").route(web::post().to(save_preset)))
       .service(web::resource("/preset/load").route(web::post().to(load_preset)))
       .service(web::resource("/preset/delete").route(web::delete().to(delete_preset)))
       .service(web::resource("/file/{path:.*}").route(web::get().to(serve_file)));
}

// 获取应用状态
pub async fn get_state() -> Result<HttpResponse> {
    let state = load_config().map_err(|e| {
        actix_web::error::ErrorInternalServerError(format!("无法加载配置: {}", e))
    })?;

    Ok(HttpResponse::Ok().json(state))
}


// 保存预设
pub async fn save_preset(req: web::Json<SavePresetRequest>) -> Result<HttpResponse> {
    let mut state = load_config().map_err(|e| {
        actix_web::error::ErrorInternalServerError(format!("无法加载配置: {}", e))
    })?;

    // 查找是否已存在同名预设
    if let Some(preset) = state.presets.iter_mut().find(|p| p.name == req.name) {
        preset.categories = req.categories.clone();
    } else {
        state.presets.push(Preset {
            name: req.name.clone(),
            categories: req.categories.clone(),
        });
    }

    state.current_preset = req.name.clone();

    save_config(&state).map_err(|e| {
        actix_web::error::ErrorInternalServerError(format!("无法保存配置: {}", e))
    })?;

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "status": "success",
        "state": state
    })))
}

// 加载预设
pub async fn load_preset(req: web::Json<PresetRequest>) -> Result<HttpResponse> {
    let mut state = load_config().map_err(|e| {
        actix_web::error::ErrorInternalServerError(format!("无法加载配置: {}", e))
    })?;

    if let Some(preset) = state.presets.iter().find(|p| p.name == req.name) {
        state.current_preset = req.name.clone();

        save_config(&state).map_err(|e| {
            actix_web::error::ErrorInternalServerError(format!("无法保存配置: {}", e))
        })?;

        Ok(HttpResponse::Ok().json(serde_json::json!({
            "status": "success",
            "categories": preset.categories.clone(),
            "preset_name": preset.name.clone()
        })))
    } else {
        Ok(HttpResponse::BadRequest().json(serde_json::json!({
            "error": "Preset not found"
        })))
    }
}

// 删除预设
pub async fn delete_preset(req: web::Json<PresetRequest>) -> Result<HttpResponse> {
    let mut state = load_config().map_err(|e| {
        actix_web::error::ErrorInternalServerError(format!("无法加载配置: {}", e))
    })?;

    state.presets.retain(|p| p.name != req.name);

    if state.current_preset == req.name {
        state.current_preset = state.presets.first()
            .map(|p| p.name.clone())
            .unwrap_or_default();
    }

    save_config(&state).map_err(|e| {
        actix_web::error::ErrorInternalServerError(format!("无法保存配置: {}", e))
    })?;

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "status": "success",
        "state": state
    })))
}

// 获取待分类文件列表
pub async fn get_files() -> Result<HttpResponse> {
    let state = load_config().map_err(|e| {
        actix_web::error::ErrorInternalServerError(format!("无法加载配置: {}", e))
    })?;
    
    if state.source_folder.is_empty() {
        return Ok(HttpResponse::Ok().json(Vec::<FileInfo>::new()));
    }
    
    let mut files = Vec::new();
    
    if let Ok(entries) = fs::read_dir(&state.source_folder) {
        for entry in entries.flatten() {
            if let Ok(metadata) = entry.metadata() {
                if metadata.is_file() {
                    let path = entry.path();
                    if let Some(extension) = path.extension() {
                        if SUPPORTED_EXTENSIONS.contains(&extension.to_str().unwrap_or("")) {
                            let file_type = if matches!(
                                extension.to_str().unwrap_or("").to_lowercase().as_str(),
                                "mp4" | "mov" | "avi" | "mkv" | "webm"
                            ) {
                                "video".to_string()
                            } else {
                                "image".to_string()
                            };
                            
                            files.push(FileInfo {
                                name: entry.file_name().to_string_lossy().to_string(),
                                path: path.to_string_lossy().to_string(),
                                file_type,
                            });
                        }
                    }
                }
            }
        }
    }
    
    files.sort_by(|a, b| a.name.cmp(&b.name));
    Ok(HttpResponse::Ok().json(files))
}

// 移动文件到指定分类（支持重命名和移回原位置）
pub async fn move_file(req: web::Json<MoveRequest>) -> Result<HttpResponse> {
    let state = load_config().map_err(|e| {
        actix_web::error::ErrorInternalServerError(format!("无法加载配置: {}", e))
    })?;
    
    let source_path = Path::new(&req.file_path);
    if !source_path.exists() {
        return Ok(HttpResponse::BadRequest().json(serde_json::json!({
            "error": "Source file does not exist"
        })));
    }
    
    // 如果category为空，表示移回源文件夹根目录
    let mut target_dir = if req.category.is_empty() {
        Path::new(&state.source_folder).to_path_buf()
    } else {
        Path::new(&state.source_folder).join(&req.category)
    };
    
    // 文件名如已存在，则添加后缀
    let mut dir_counter = 1;
    while target_dir.exists() && !target_dir.is_dir() {
        target_dir = Path::new(&state.source_folder).join(format!("{}_{}", req.category, dir_counter));
        dir_counter += 1;
    }
    
    // 如不存在则创建目录
    if !target_dir.exists() {
        fs::create_dir_all(&target_dir)?;
    }
    
    // 确定目标文件名
    let target_file_name = if let Some(new_name) = &req.new_name {
        let extension = source_path.extension()
            .map(|e| format!(".{}", e.to_string_lossy()))
            .unwrap_or_default();
        format!("{}{}", new_name, extension)
    } else {
        source_path.file_name().unwrap().to_string_lossy().to_string()
    };
    
    let target_path = target_dir.join(&target_file_name);
    
    // 使用括号加数字别名
    let mut final_path = target_path.clone();
    if final_path.exists() {
        let stem = Path::new(&target_file_name).file_stem().unwrap().to_string_lossy();
        let ext = Path::new(&target_file_name).extension()
            .map(|e| format!(".{}", e.to_string_lossy()))
            .unwrap_or_default();
        
        let mut counter = 1;
        loop {
            final_path = target_dir.join(format!("{} ({}){}", stem, counter, ext));
            if !final_path.exists() {
                break;
            }
            counter += 1;
        }
    }
    
    fs::rename(&source_path, &final_path)?;
    
    Ok(HttpResponse::Ok().json(serde_json::json!({
        "status": "success",
        "moved_to": final_path.to_string_lossy(),
        "final_name": final_path.file_name().unwrap().to_string_lossy()
    })))
}

// 提供文件服务
pub async fn serve_file(path: web::Path<String>) -> Result<HttpResponse> {
    let file_path = percent_encoding::percent_decode_str(&path)
        .decode_utf8_lossy()
        .to_string();

    if !Path::new(&file_path).exists() {
        return Ok(HttpResponse::NotFound().body("File not found"));
    }

    let content = fs::read(&file_path)?;
    let mime_type = mime_guess::from_path(&file_path)
        .first_or_octet_stream()
        .to_string();

    Ok(HttpResponse::Ok()
        .content_type(mime_type)
        .body(content))
}

// 获取源文件夹下的所有子文件夹
pub async fn get_folders(query: web::Query<std::collections::HashMap<String, String>>) -> Result<HttpResponse> {
    let source_folder = query.get("source_folder");

    if source_folder.is_none() {
        return Ok(HttpResponse::Ok().json(Vec::<FolderInfo>::new()));
    }

    let source_folder = source_folder.unwrap();
    let source_path = Path::new(source_folder);

    if !source_path.exists() || !source_path.is_dir() {
        return Ok(HttpResponse::Ok().json(Vec::<FolderInfo>::new()));
    }

    // 加载配置以获取隐藏文件夹列表
    let state = load_config().unwrap_or_else(|_| super::config::get_default_state());

    let mut folders = Vec::new();

    if let Ok(entries) = fs::read_dir(source_path) {
        for entry in entries.flatten() {
            if let Ok(metadata) = entry.metadata() {
                if metadata.is_dir() {
                    let folder_name = entry.file_name().to_string_lossy().to_string();
                    // 跳过隐藏文件夹（以.开头的）
                    if !folder_name.starts_with('.') {
                        let hidden = state.hidden_folders.contains(&folder_name);
                        folders.push(FolderInfo {
                            name: folder_name,
                            hidden,
                        });
                    }
                }
            }
        }
    }

    folders.sort_by(|a, b| a.name.cmp(&b.name));
    Ok(HttpResponse::Ok().json(folders))
}

// 保存设置(创建文件夹并保存配置)
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
            "error": "Source folder does not exist"
        })));
    }

    // 创建所有需要的分类文件夹
    for category in &req.categories {
        let folder_path = source_path.join(category);
        if !folder_path.exists() {
            fs::create_dir_all(&folder_path)?;
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

// 创建单个文件夹
pub async fn create_folder(req: web::Json<CreateFolderRequest>) -> Result<HttpResponse> {
    let state = load_config().map_err(|e| {
        actix_web::error::ErrorInternalServerError(format!("无法加载配置: {}", e))
    })?;

    // 验证源文件夹存在
    let source_path = Path::new(&state.source_folder);
    if !source_path.exists() {
        return Ok(HttpResponse::BadRequest().json(serde_json::json!({
            "error": "Source folder does not exist"
        })));
    }

    // 创建文件夹
    let folder_path = source_path.join(&req.folder_name);
    if !folder_path.exists() {
        fs::create_dir_all(&folder_path)?;
    }

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "status": "success"
    })))
}