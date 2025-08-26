use actix_web::{web, HttpResponse, Result};
use std::fs;
use std::path::Path;
use std::env;
use crate::models::*;
use crate::config::{get_default_state, SUPPORTED_EXTENSIONS};

// 获取应用状态
pub async fn get_state() -> Result<HttpResponse> {
    let state_str = fs::read_to_string("app_state.json")
        .unwrap_or_else(|_| {
            let mut default_state = get_default_state();
            
            // 如果文件不存在，使用当前目录作为源文件夹
            if default_state.source_folder.is_empty() {
                default_state.source_folder = env::current_dir()
                    .map(|p| p.to_string_lossy().to_string())
                    .unwrap_or_else(|_| String::new());
            }
            
            let json = serde_json::to_string_pretty(&default_state).unwrap();
            // 保存默认状态
            let _ = fs::write("app_state.json", &json);
            json
        });
    
    let mut state: AppState = serde_json::from_str(&state_str)?;
    
    // 如果源文件夹为空，使用当前目录
    if state.source_folder.is_empty() {
        state.source_folder = env::current_dir()
            .map(|p| p.to_string_lossy().to_string())
            .unwrap_or_else(|_| String::new());
        
        // 更新保存的状态
        let state_str = serde_json::to_string_pretty(&state)?;
        let _ = fs::write("app_state.json", state_str);
    }
    
    Ok(HttpResponse::Ok().json(state))
}

// 更新源文件夹
pub async fn update_folder(req: web::Json<UpdateFolderRequest>) -> Result<HttpResponse> {
    let state_str = fs::read_to_string("app_state.json")
        .unwrap_or_else(|_| serde_json::to_string(&get_default_state()).unwrap());
    let mut state: AppState = serde_json::from_str(&state_str)?;
    
    state.source_folder = req.source_folder.clone();
    
    let state_str = serde_json::to_string_pretty(&state)?;
    fs::write("app_state.json", state_str)?;
    
    Ok(HttpResponse::Ok().json(serde_json::json!({
        "status": "success"
    })))
}

// 保存预设
pub async fn save_preset(req: web::Json<SavePresetRequest>) -> Result<HttpResponse> {
    let state_str = fs::read_to_string("app_state.json")
        .unwrap_or_else(|_| serde_json::to_string(&get_default_state()).unwrap());
    let mut state: AppState = serde_json::from_str(&state_str)?;
    
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
    
    let state_str = serde_json::to_string_pretty(&state)?;
    fs::write("app_state.json", state_str)?;
    
    Ok(HttpResponse::Ok().json(serde_json::json!({
        "status": "success",
        "state": state
    })))
}

// 加载预设
pub async fn load_preset(req: web::Json<PresetRequest>) -> Result<HttpResponse> {
    let state_str = fs::read_to_string("app_state.json")
        .unwrap_or_else(|_| serde_json::to_string(&get_default_state()).unwrap());
    let mut state: AppState = serde_json::from_str(&state_str)?;
    
    if let Some(preset) = state.presets.iter().find(|p| p.name == req.name) {
        state.current_preset = req.name.clone();
        
        let state_str = serde_json::to_string_pretty(&state)?;
        fs::write("app_state.json", state_str)?;
        
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
    let state_str = fs::read_to_string("app_state.json")
        .unwrap_or_else(|_| serde_json::to_string(&get_default_state()).unwrap());
    let mut state: AppState = serde_json::from_str(&state_str)?;
    
    state.presets.retain(|p| p.name != req.name);
    
    if state.current_preset == req.name {
        state.current_preset = state.presets.first()
            .map(|p| p.name.clone())
            .unwrap_or_default();
    }
    
    let state_str = serde_json::to_string_pretty(&state)?;
    fs::write("app_state.json", state_str)?;
    
    Ok(HttpResponse::Ok().json(serde_json::json!({
        "status": "success",
        "state": state
    })))
}

// 获取待分类文件列表
pub async fn get_files() -> Result<HttpResponse> {
    let state_str = fs::read_to_string("app_state.json")
        .unwrap_or_else(|_| serde_json::to_string(&get_default_state()).unwrap());
    let state: AppState = serde_json::from_str(&state_str)?;
    
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
    let state_str = fs::read_to_string("app_state.json")
        .unwrap_or_else(|_| serde_json::to_string(&get_default_state()).unwrap());
    let state: AppState = serde_json::from_str(&state_str)?;
    
    let source_path = Path::new(&req.file_path);
    if !source_path.exists() {
        return Ok(HttpResponse::BadRequest().json(serde_json::json!({
            "error": "Source file does not exist"
        })));
    }
    
    // 如果category为空，表示移回源文件夹根目录
    let target_dir = if req.category.is_empty() {
        Path::new(&state.source_folder).to_path_buf()
    } else {
        Path::new(&state.source_folder).join(&req.category)
    };
    
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
    
    // 如果目标文件已存在，添加序号
    let mut final_path = target_path.clone();
    let mut counter = 1;
    while final_path.exists() {
        let stem = Path::new(&target_file_name).file_stem().unwrap().to_string_lossy();
        let ext = Path::new(&target_file_name).extension()
            .map(|e| format!(".{}", e.to_string_lossy()))
            .unwrap_or_default();
        final_path = target_dir.join(format!("{}_{}{}", stem, counter, ext));
        counter += 1;
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