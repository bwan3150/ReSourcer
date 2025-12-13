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
       .service(web::resource("/file/{path:.*}").route(web::get().to(serve_file)))
       // 源文件夹管理API
       .service(web::resource("/sources/add").route(web::post().to(add_source_folder)))
       .service(web::resource("/sources/remove").route(web::post().to(remove_source_folder)))
       .service(web::resource("/sources/switch").route(web::post().to(switch_source_folder)))
       // 分类排序API
       .service(web::resource("/categories/reorder").route(web::post().to(reorder_categories)));
}

// 获取应用状态
pub async fn get_state() -> Result<HttpResponse> {
    let state = load_config().map_err(|e| {
        actix_web::error::ErrorInternalServerError(format!("无法加载配置: {}", e))
    })?;

    // 从文件加载预设
    let presets = super::config::load_presets().unwrap_or_default();

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "source_folder": state.source_folder,
        "hidden_folders": state.hidden_folders,
        "presets": presets
    })))
}


// 保存预设 - 现在预设是只读的，从 config/presets.json 读取，不再支持保存
pub async fn save_preset(_req: web::Json<PresetRequest>) -> Result<HttpResponse> {
    Ok(HttpResponse::BadRequest().json(serde_json::json!({
        "error": "Presets are read-only and loaded from config/presets.json"
    })))
}

// 加载预设 - 现在预设是只读的，从 config/presets.json 读取
pub async fn load_preset(req: web::Json<PresetRequest>) -> Result<HttpResponse> {
    let presets = super::config::load_presets().unwrap_or_default();

    if let Some(preset) = presets.iter().find(|p| p.name == req.name) {
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

// 删除预设 - 现在预设是只读的，从 config/presets.json 读取，不再支持删除
pub async fn delete_preset(_req: web::Json<PresetRequest>) -> Result<HttpResponse> {
    Ok(HttpResponse::BadRequest().json(serde_json::json!({
        "error": "Presets are read-only and loaded from config/presets.json"
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

    // 检查目标文件夹是否存在（不自动创建）
    if !target_dir.exists() {
        return Ok(HttpResponse::BadRequest().json(serde_json::json!({
            "error": format!("目标文件夹不存在: {}", target_dir.display())
        })));
    }

    // 确保是目录而非文件
    if !target_dir.is_dir() {
        return Ok(HttpResponse::BadRequest().json(serde_json::json!({
            "error": format!("目标路径不是文件夹: {}", target_dir.display())
        })));
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
pub async fn serve_file(
    path: web::Path<String>,
    req: actix_web::HttpRequest,
) -> Result<HttpResponse> {
    let file_path = percent_encoding::percent_decode_str(&path)
        .decode_utf8_lossy()
        .to_string();

    if !Path::new(&file_path).exists() {
        return Ok(HttpResponse::NotFound().body("File not found"));
    }

    let mime_type = mime_guess::from_path(&file_path)
        .first_or_octet_stream()
        .to_string();

    // 获取文件大小
    let metadata = fs::metadata(&file_path)?;
    let file_size = metadata.len();

    // 检查是否有 Range 请求
    if let Some(range_header) = req.headers().get(actix_web::http::header::RANGE) {
        if let Ok(range_str) = range_header.to_str() {
            // 解析 Range 头，格式: bytes=start-end
            if range_str.starts_with("bytes=") {
                let range_str = &range_str[6..];
                let parts: Vec<&str> = range_str.split('-').collect();

                if parts.len() == 2 {
                    let start: u64 = parts[0].parse().unwrap_or(0);
                    let end: u64 = if parts[1].is_empty() {
                        file_size - 1
                    } else {
                        parts[1].parse().unwrap_or(file_size - 1).min(file_size - 1)
                    };

                    if start <= end && end < file_size {
                        // 读取指定范围的文件内容
                        let mut file = std::fs::File::open(&file_path)?;
                        use std::io::{Seek, SeekFrom, Read};
                        file.seek(SeekFrom::Start(start))?;

                        let content_length = (end - start + 1) as usize;
                        let mut buffer = vec![0u8; content_length];
                        file.read_exact(&mut buffer)?;

                        return Ok(HttpResponse::PartialContent()
                            .content_type(mime_type.clone())
                            .insert_header(("Accept-Ranges", "bytes"))
                            .insert_header(("Content-Range", format!("bytes {}-{}/{}", start, end, file_size)))
                            .insert_header(("Content-Length", content_length.to_string()))
                            .body(buffer));
                    }
                }
            }
        }
    }

    // 没有 Range 请求或解析失败，返回完整文件
    let content = fs::read(&file_path)?;
    Ok(HttpResponse::Ok()
        .content_type(mime_type)
        .insert_header(("Accept-Ranges", "bytes"))
        .insert_header(("Content-Length", file_size.to_string()))
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

                        // 统计文件夹中的文件数量
                        let folder_path = entry.path();
                        let file_count = count_files_in_folder(&folder_path);

                        folders.push(FolderInfo {
                            name: folder_name,
                            hidden,
                            file_count,
                        });
                    }
                }
            }
        }
    }

    // 按照保存的顺序排序，如果没有保存的顺序则按名称排序
    let category_order = super::config::get_category_order(source_folder);
    if !category_order.is_empty() {
        folders.sort_by(|a, b| {
            let pos_a = category_order.iter().position(|x| x == &a.name);
            let pos_b = category_order.iter().position(|x| x == &b.name);

            match (pos_a, pos_b) {
                (Some(pa), Some(pb)) => pa.cmp(&pb),
                (Some(_), None) => std::cmp::Ordering::Less,
                (None, Some(_)) => std::cmp::Ordering::Greater,
                (None, None) => a.name.cmp(&b.name),
            }
        });
    } else {
        folders.sort_by(|a, b| a.name.cmp(&b.name));
    }

    Ok(HttpResponse::Ok().json(folders))
}

/// 统计文件夹中的支持文件数量
fn count_files_in_folder(folder_path: &Path) -> usize {
    let mut count = 0;

    if let Ok(entries) = fs::read_dir(folder_path) {
        for entry in entries.flatten() {
            if let Ok(metadata) = entry.metadata() {
                if metadata.is_file() {
                    let path = entry.path();
                    if let Some(extension) = path.extension() {
                        if SUPPORTED_EXTENSIONS.contains(&extension.to_str().unwrap_or("")) {
                            count += 1;
                        }
                    }
                }
            }
        }
    }

    count
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
// ========== 源文件夹管理API ==========

// 添加备用源文件夹
pub async fn add_source_folder(req: web::Json<AddSourceFolderRequest>) -> Result<HttpResponse> {
    let mut state = load_config().map_err(|e| {
        actix_web::error::ErrorInternalServerError(format!("无法加载配置: {}", e))
    })?;

    let folder_path = req.folder_path.trim();

    // 验证路径存在
    if !Path::new(folder_path).exists() {
        return Ok(HttpResponse::BadRequest().json(serde_json::json!({
            "error": "文件夹不存在"
        })));
    }

    // 检查是否已存在
    if state.source_folder == folder_path || state.backup_source_folders.contains(&folder_path.to_string()) {
        return Ok(HttpResponse::BadRequest().json(serde_json::json!({
            "error": "该文件夹已添加"
        })));
    }

    // 添加到备用列表
    state.backup_source_folders.push(folder_path.to_string());

    save_config(&state).map_err(|e| {
        actix_web::error::ErrorInternalServerError(format!("无法保存配置: {}", e))
    })?;

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "status": "success"
    })))
}

// 移除备用源文件夹
pub async fn remove_source_folder(req: web::Json<RemoveSourceFolderRequest>) -> Result<HttpResponse> {
    let mut state = load_config().map_err(|e| {
        actix_web::error::ErrorInternalServerError(format!("无法加载配置: {}", e))
    })?;

    let folder_path = req.folder_path.trim();

    // 不能删除当前活动的源文件夹
    if state.source_folder == folder_path {
        return Ok(HttpResponse::BadRequest().json(serde_json::json!({
            "error": "无法删除当前活动的源文件夹"
        })));
    }

    // 从备用列表中移除
    state.backup_source_folders.retain(|f| f != folder_path);

    save_config(&state).map_err(|e| {
        actix_web::error::ErrorInternalServerError(format!("无法保存配置: {}", e))
    })?;

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "status": "success"
    })))
}

// 切换源文件夹
pub async fn switch_source_folder(req: web::Json<SwitchSourceFolderRequest>) -> Result<HttpResponse> {
    let mut state = load_config().map_err(|e| {
        actix_web::error::ErrorInternalServerError(format!("无法加载配置: {}", e))
    })?;

    let folder_path = req.folder_path.trim();

    // 验证路径存在
    if !Path::new(folder_path).exists() {
        return Ok(HttpResponse::BadRequest().json(serde_json::json!({
            "error": "文件夹不存在"
        })));
    }

    // 检查是否在备用列表中
    if !state.backup_source_folders.contains(&folder_path.to_string()) && state.source_folder != folder_path {
        return Ok(HttpResponse::BadRequest().json(serde_json::json!({
            "error": "该文件夹不在源文件夹列表中"
        })));
    }

    // 如果当前源文件夹不为空,将其加入备用列表
    if !state.source_folder.is_empty() && state.source_folder != folder_path {
        if !state.backup_source_folders.contains(&state.source_folder) {
            state.backup_source_folders.push(state.source_folder.clone());
        }
    }

    // 从备用列表中移除新的活动源
    state.backup_source_folders.retain(|f| f != folder_path);

    // 切换到新的源文件夹
    state.source_folder = folder_path.to_string();

    save_config(&state).map_err(|e| {
        actix_web::error::ErrorInternalServerError(format!("无法保存配置: {}", e))
    })?;

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "status": "success"
    })))
}
// 保存分类顺序
pub async fn reorder_categories(req: web::Json<ReorderCategoriesRequest>) -> Result<HttpResponse> {
    // 保存指定源文件夹的分类顺序
    super::config::set_category_order(&req.source_folder, req.category_order.clone())
        .map_err(|e| {
            actix_web::error::ErrorInternalServerError(format!("无法保存分类顺序: {}", e))
        })?;

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "status": "success"
    })))
}
