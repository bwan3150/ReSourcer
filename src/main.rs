use actix_files::Files;
use actix_web::{middleware, web, App, HttpResponse, HttpServer, Result};
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::Path;
use std::env;

#[derive(Serialize, Deserialize)]
struct AppState {
    source_folder: String,
    current_preset: String,
    presets: Vec<Preset>,
}

#[derive(Serialize, Deserialize, Clone)]
struct Preset {
    name: String,
    categories: Vec<String>,
}

#[derive(Serialize)]
struct FileInfo {
    name: String,
    path: String,
    file_type: String,
}

#[derive(Deserialize)]
struct MoveRequest {
    file_path: String,
    category: String,
    new_name: Option<String>,
}

#[derive(Deserialize)]
struct PresetRequest {
    name: String,
}

#[derive(Deserialize)]
struct SavePresetRequest {
    name: String,
    categories: Vec<String>,
}

#[derive(Deserialize)]
struct UpdateFolderRequest {
    source_folder: String,
}

// 默认应用状态 - 使用当前目录作为默认源文件夹
fn get_default_state() -> AppState {
    // 获取当前工作目录
    let current_dir = env::current_dir()
        .map(|p| p.to_string_lossy().to_string())
        .unwrap_or_else(|_| String::new());
    
    AppState {
        source_folder: current_dir,
        current_preset: "Art Resources".to_string(),
        presets: vec![
            Preset {
                name: "Art Resources".to_string(),
                categories: vec![
                    "Character Design".to_string(),
                    "Backgrounds".to_string(),
                    "Color Reference".to_string(),
                    "Composition".to_string(),
                    "Anatomy".to_string(),
                    "Lighting".to_string(),
                ],
            },
            Preset {
                name: "Photography".to_string(),
                categories: vec![
                    "Portraits".to_string(),
                    "Landscapes".to_string(),
                    "Street".to_string(),
                    "Architecture".to_string(),
                    "Nature".to_string(),
                    "Black & White".to_string(),
                ],
            },
            Preset {
                name: "Design Assets".to_string(),
                categories: vec![
                    "UI/UX".to_string(),
                    "Icons".to_string(),
                    "Patterns".to_string(),
                    "Textures".to_string(),
                    "Mockups".to_string(),
                    "Fonts".to_string(),
                ],
            },
        ],
    }
}

// 获取应用状态
async fn get_state() -> Result<HttpResponse> {
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
async fn update_folder(req: web::Json<UpdateFolderRequest>) -> Result<HttpResponse> {
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
async fn save_preset(req: web::Json<SavePresetRequest>) -> Result<HttpResponse> {
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
async fn load_preset(req: web::Json<PresetRequest>) -> Result<HttpResponse> {
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
async fn delete_preset(req: web::Json<PresetRequest>) -> Result<HttpResponse> {
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
async fn get_files() -> Result<HttpResponse> {
    let state_str = fs::read_to_string("app_state.json")
        .unwrap_or_else(|_| serde_json::to_string(&get_default_state()).unwrap());
    let state: AppState = serde_json::from_str(&state_str)?;
    
    if state.source_folder.is_empty() {
        return Ok(HttpResponse::Ok().json(Vec::<FileInfo>::new()));
    }
    
    let mut files = Vec::new();
    let supported_extensions = vec![
        "png", "jpg", "jpeg", "webp", "gif", "bmp",
        "PNG", "JPG", "JPEG", "WEBP", "GIF", "BMP",
        "mp4", "mov", "avi", "mkv", "webm",
        "MP4", "MOV", "AVI", "MKV", "WEBM",
        "heic", "HEIC", "heif", "HEIF"
    ];
    
    if let Ok(entries) = fs::read_dir(&state.source_folder) {
        for entry in entries.flatten() {
            if let Ok(metadata) = entry.metadata() {
                if metadata.is_file() {
                    let path = entry.path();
                    if let Some(extension) = path.extension() {
                        if supported_extensions.contains(&extension.to_str().unwrap_or("")) {
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
async fn move_file(req: web::Json<MoveRequest>) -> Result<HttpResponse> {
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
async fn serve_file(path: web::Path<String>) -> Result<HttpResponse> {
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

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    // 获取当前目录
    let current_dir = env::current_dir()
        .map(|p| p.to_string_lossy().to_string())
        .unwrap_or_else(|_| "Unknown".to_string());
    
    println!("====================================");
    println!("    Resource Classifier");
    println!("====================================");
    println!("Current directory: {}", current_dir);
    println!("Starting server at: http://localhost:1234");
    println!("Opening browser automatically...");
    println!("====================================");
    
    // 在新线程中延迟打开浏览器
    tokio::spawn(async {
        tokio::time::sleep(tokio::time::Duration::from_millis(1500)).await;
        if let Err(e) = open::that("http://localhost:1234") {
            eprintln!("Failed to open browser: {}", e);
            println!("Please open your browser and navigate to: http://localhost:1234");
        }
    });
    
    HttpServer::new(|| {
        App::new()
            .wrap(middleware::Logger::default())
            .route("/api/state", web::get().to(get_state))
            .route("/api/folder", web::post().to(update_folder))
            .route("/api/files", web::get().to(get_files))
            .route("/api/move", web::post().to(move_file))
            .route("/api/preset/save", web::post().to(save_preset))
            .route("/api/preset/load", web::post().to(load_preset))
            .route("/api/preset/delete", web::delete().to(delete_preset))
            .route("/api/file/{path:.*}", web::get().to(serve_file))
            .service(Files::new("/", "./static").index_file("index.html"))
    })
    .bind("127.0.0.1:1234")?
    .run()
    .await
}
