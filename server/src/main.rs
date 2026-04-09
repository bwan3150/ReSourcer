use actix_web::{web, App, HttpResponse, HttpServer, Result};
use std::net::UdpSocket;
use std::sync::{Arc, RwLock};

// API模块 - 面向开发者的系统操作
mod file;
mod folder;
mod transfer;
mod config_api;
mod preview;
mod browser;
mod indexer;
mod tag;
mod metrics;
mod playlist;

// 工具模块
mod static_files;
mod auth;
mod logger;
mod database;
pub mod tools;
mod updater;

use static_files::read_config_file;

/// 全局配置 API - 所有模块共用
async fn get_global_config() -> Result<HttpResponse> {
    let config = config_api::storage::load_config()
        .map_err(|e| actix_web::error::ErrorInternalServerError(format!("无法加载配置: {}", e)))?;

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "source_folder": config.source_folder,
        "hidden_folders": config.hidden_folders,
    })))
}

/// 健康检查 API - 不需要认证
async fn health_check() -> Result<HttpResponse> {
    Ok(HttpResponse::Ok().json(serde_json::json!({
        "status": "ok",
        "service": "ReSourcer"
    })))
}

/// App 配置 API - 读取 app.json（包含 Android/iOS 下载链接）
async fn get_app_config() -> Result<HttpResponse> {
    use serde::Deserialize;

    #[derive(Deserialize)]
    struct AppConfig {
        version: String,
        android_url: String,
        ios_url: String,
        github_url: String,
    }

    if let Some(data) = read_config_file("app.json") {
        match serde_json::from_slice::<AppConfig>(&data) {
            Ok(config) => {
                Ok(HttpResponse::Ok().json(serde_json::json!({
                    "version": config.version,
                    "android_url": config.android_url,
                    "ios_url": config.ios_url,
                    "github_url": config.github_url,
                })))
            }
            Err(e) => {
                Ok(HttpResponse::InternalServerError().json(serde_json::json!({
                    "error": format!("无法解析 app.json: {}", e)
                })))
            }
        }
    } else {
        Ok(HttpResponse::NotFound().json(serde_json::json!({
            "error": "app.json 未找到"
        })))
    }
}

/// 初始化配置文件：缺失的自动生成默认值
fn init_config_files() {
    use std::fs;

    let config_dir = static_files::app_dir().join("config");
    let _ = fs::create_dir_all(&config_dir);

    // app.json
    let app_path = config_dir.join("app.json");
    if !app_path.exists() {
        let default = serde_json::json!({
            "version": "0.3.0-beta",
            "android_url": "",
            "ios_url": "https://www.pgyer.com/resourcer-ios",
            "github_url": "https://github.com/bwan3150/ReSourcer"
        });
        let _ = fs::write(&app_path, serde_json::to_string_pretty(&default).unwrap());
        eprintln!("[init] 已生成 config/app.json");
    }

    // secret.json — 自动生成随机 API Key
    let secret_path = config_dir.join("secret.json");
    if !secret_path.exists() {
        let key = uuid::Uuid::new_v4().to_string();
        let default = serde_json::json!({ "apikey": key });
        let _ = fs::write(&secret_path, serde_json::to_string_pretty(&default).unwrap());
        eprintln!("[init] 已生成 config/secret.json (API Key: {})", key);
    }

    // tools.json — 由 tools 模块的 load_tools_config() 自动处理
    let _ = tools::load_tools_config();
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    // 初始化配置文件（缺失的自动生成）
    init_config_files();

    // 初始化数据库
    if let Err(e) = database::init_db() {
        eprintln!("数据库初始化失败: {}", e);
        return Err(std::io::Error::new(std::io::ErrorKind::Other, e.to_string()));
    }

    // 获取本机局域网 IP
    fn get_local_ip() -> Option<String> {
        let socket = UdpSocket::bind("0.0.0.0:0").ok()?;
        socket.connect("8.8.8.8:80").ok()?;
        socket.local_addr().ok().map(|addr| addr.ip().to_string())
    }

    let local_ip = get_local_ip().unwrap_or_else(|| "0.0.0.0".to_string());

    // 打印启动信息
    println!();
    println!(r#"╔══════════════════════════════════════════════════════════════════════════════╗"#);
    println!(r#"║                                                                              ║"#);
    println!(r#"║  ██████╗ ███████╗███████╗ ██████╗ ██╗   ██╗██████╗  ██████╗███████╗██████╗   ║"#);
    println!(r#"║  ██╔══██╗██╔════╝██╔════╝██╔═══██╗██║   ██║██╔══██╗██╔════╝██╔════╝██╔══██╗  ║"#);
    println!(r#"║  ██████╔╝█████╗  ███████╗██║   ██║██║   ██║██████╔╝██║     █████╗  ██████╔╝  ║"#);
    println!(r#"║  ██╔══██╗██╔══╝  ╚════██║██║   ██║██║   ██║██╔══██╗██║     ██╔══╝  ██╔══██╗  ║"#);
    println!(r#"║  ██║  ██║███████╗███████║╚██████╔╝╚██████╔╝██║  ██║╚██████╗███████╗██║  ██║  ║"#);
    println!(r#"║  ╚═╝  ╚═╝╚══════╝╚══════╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═╝ ╚═════╝╚══════╝╚═╝  ╚═╝  ║"#);
    println!(r#"║                                                                              ║"#);
    println!(r#"║                                 S E R V E R                                  ║"#);
    println!(r#"╚══════════════════════════════════════════════════════════════════════════════╝"#);
    println!();

    // 系统预检：检查数据库和必要工具，缺失则自动下载
    tools::preflight_check();

    // 初始化下载器任务管理器
    let download_task_manager = web::Data::new(transfer::download::TaskManager::new());

    // 初始化上传器任务管理器
    let upload_task_manager = web::Data::new(transfer::upload::TaskManager::new());

    // 初始化扫描状态（索引模块共享）
    let scan_status = web::Data::new(Arc::new(RwLock::new(indexer::models::ScanStatus::default())));

    // 初始化性能指标采集
    let metrics_state = web::Data::new(Arc::new(RwLock::new(metrics::models::MetricsState::new())));
    metrics::collector::start_collector(metrics_state.get_ref().clone());

    // 读取 API Key (优先级: secret.json > 环境变量 > 随机生成)
    fn load_api_key_from_secret() -> Option<String> {
        use std::fs;
        use serde::Deserialize;

        #[derive(Deserialize)]
        struct SecretConfig {
            apikey: String,
        }

        let secret_path = crate::static_files::app_dir().join("config").join("secret.json");
        let content = fs::read_to_string(&secret_path).ok()?;
        let config: SecretConfig = serde_json::from_str(&content).ok()?;
        Some(config.apikey)
    }

    let api_key = load_api_key_from_secret()
        .or_else(|| std::env::var("API_KEY").ok())
        .unwrap_or_else(|| uuid::Uuid::new_v4().to_string());

    // 服务信息
    let url = format!("http://{}:1234", local_ip);
    println!("┌──────────────────────────────────────────────────────────────────────────────┐");
    println!("│  API:  {:<69}│", url);
    println!("│  Key:  {:<69}│", api_key);
    println!("└──────────────────────────────────────────────────────────────────────────────┘");
    println!();

    let api_key_data = web::Data::new(api_key.clone());

    HttpServer::new(move || {
        // CORS: 允许任意来源访问 API（前端可能部署在不同域/端口）
        let cors = actix_cors::Cors::default()
            .allow_any_origin()
            .allow_any_method()
            .allow_any_header()
            .max_age(3600);

        App::new()
            // 注意 actix-web wrap 顺序：最后 wrap 的最先执行
            // 所以 auth 先，logger 次之，CORS 最后（最先拦截 preflight OPTIONS）
            .wrap(auth::middleware::ApiKeyAuth::new(api_key.clone()))
            .wrap(logger::ColorLogger::new())
            .wrap(cors)
            // 注入 API Key 和任务管理器
            .app_data(api_key_data.clone())
            .app_data(download_task_manager.clone())
            .app_data(upload_task_manager.clone())
            .app_data(scan_status.clone())
            .app_data(metrics_state.clone())
            // 健康检查 API（不需要认证）
            .route("/api/health", web::get().to(health_check))
            // 认证 API 路由
            .service(web::scope("/api/auth").configure(auth::routes))
            // 全局配置 API（所有模块共用）
            .route("/api/config", web::get().to(get_global_config))
            // App 配置 API（版本、下载链接、自更新）
            .service(web::scope("/api/app")
                .route("", web::get().to(get_app_config))
                .route("/check-update", web::get().to(updater::check_update))
                .route("/update", web::post().to(updater::do_update))
            )
            // === 新的API路由 - 面向开发者的系统操作 ===
            // 文件操作 API 路由
            .service(web::scope("/api/file").configure(file::routes))
            // 文件夹操作 API 路由
            .service(web::scope("/api/folder").configure(folder::routes))
            // 传输操作 API 路由（包含 download 和 upload 子模块）
            .service(web::scope("/api/transfer").configure(transfer::routes))
            // 配置操作 API 路由（含 tools 子路由）
            .service(web::scope("/api/config")
                .configure(config_api::routes)
                .configure(tools::routes)
            )
            // 预览操作 API 路由
            .service(web::scope("/api/preview").configure(preview::routes))
            // 文件索引 API 路由
            .service(web::scope("/api/indexer").configure(indexer::routes))
            // 标签 API 路由
            .service(web::scope("/api/tag").configure(tag::routes))
            // 文件系统浏览 API 路由
            .service(web::scope("/api/browser").configure(browser::routes))
            // 播放队列 API 路由
            .service(web::scope("/api/playlist").configure(playlist::routes))
            // 性能指标 API 路由
            .service(web::scope("/api/metrics").configure(metrics::routes))
    })
    .bind("0.0.0.0:1234")?
    .run()
    .await
}
