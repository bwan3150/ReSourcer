use actix_web::{middleware, web, App, HttpResponse, HttpServer, Result};
use std::net::UdpSocket;

mod classifier;
mod downloader;
mod uploader;
mod gallery;
mod static_files;
mod auth;
mod filesystem;
mod settings;

use static_files::serve_static;

/// 全局配置 API - 所有模块共用
async fn get_global_config() -> Result<HttpResponse> {
    let config = classifier::config::load_config()
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
    use static_files::ConfigAsset;
    use serde::Deserialize;

    #[derive(Deserialize)]
    struct AppConfig {
        version: String,
        android_url: String,
        ios_url: String,
        github_url: String,
    }

    if let Some(config_file) = ConfigAsset::get("app.json") {
        match serde_json::from_slice::<AppConfig>(&config_file.data) {
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

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    // 获取本机局域网 IP
    fn get_local_ip() -> Option<String> {
        let socket = UdpSocket::bind("0.0.0.0:0").ok()?;
        socket.connect("8.8.8.8:80").ok()?;
        socket.local_addr().ok().map(|addr| addr.ip().to_string())
    }

    let local_ip = get_local_ip().unwrap_or_else(|| "0.0.0.0".to_string());

    // 打印启动信息
    println!();
    println!(r#"  ____       ____                              "#);
    println!(r#" |  _ \ ___ / ___|  ___  _   _ _ __ ___ ___ _ __"#);
    println!(r#" | |_) / _ \\___ \ / _ \| | | | '__/ __/ _ \ '__|"#);
    println!(r#" |  _ <  __/ ___) | (_) | |_| | | | (_|  __/ |  "#);
    println!(r#" |_| \_\___|____/ \___/ \__,_|_|  \___\___|_|  "#);
    println!();

    // 初始化下载器任务管理器
    let download_task_manager = web::Data::new(downloader::TaskManager::new());

    // 初始化上传器任务管理器
    let upload_task_manager = web::Data::new(uploader::TaskManager::new());

    // 生成 API Key (优先使用环境变量，否则生成随机 UUID)
    let api_key = std::env::var("API_KEY").unwrap_or_else(|_| {
        uuid::Uuid::new_v4().to_string()
    });

    // 生成登录 URL（带 API Key）
    let login_url = format!("http://{}:1234/login.html?key={}", local_ip, api_key);

    // 生成 QR Code
    use qrcode::QrCode;
    use qrcode::render::unicode;
    let qr_code = QrCode::new(&login_url).unwrap();
    let qr_string = qr_code.render::<unicode::Dense1x2>()
        .dark_color(unicode::Dense1x2::Light)
        .light_color(unicode::Dense1x2::Dark)
        .build();

    // 服务信息框
    println!("  ┌──────────────────────────────────────────────┐");
    let service_line = format!("  │ Service URL:    http://{}:1234   ", local_ip);
    println!("{:<47}│", service_line);
    println!("  │ API Key:                                     │");
    let key_line = format!("  │ {:<45}│", api_key);
    println!("{}", key_line);
    println!("  └──────────────────────────────────────────────┘");
    println!();

    // 打印 QR Code
    for line in qr_string.lines() {
        println!("  {}", line);
    }
    println!();

    // 延迟打开浏览器(使用带API Key的登录URL)
    let browser_url = login_url.clone();
    tokio::spawn(async move {
        tokio::time::sleep(tokio::time::Duration::from_millis(1500)).await;
        if let Err(e) = open::that(&browser_url) {
            eprintln!("  Failed to open browser: {}", e);
            println!("  Please visit manually: {}", browser_url);
        }
    });

    let api_key_data = web::Data::new(api_key.clone());

    HttpServer::new(move || {
        App::new()
            .wrap(middleware::Logger::default())
            // 全局 API Key 验证中间件
            .wrap(auth::middleware::ApiKeyAuth::new(api_key.clone()))
            // 注入 API Key 和任务管理器
            .app_data(api_key_data.clone())
            .app_data(download_task_manager.clone())
            .app_data(upload_task_manager.clone())
            // 健康检查 API（不需要认证）
            .route("/api/health", web::get().to(health_check))
            // 认证 API 路由
            .service(web::scope("/api/auth").configure(auth::routes))
            // 全局配置 API（所有模块共用）
            .route("/api/config", web::get().to(get_global_config))
            // App 配置 API（Android/iOS 下载链接）
            .route("/api/app", web::get().to(get_app_config))
            // 画廊 API 路由
            .service(web::scope("/api/gallery").configure(gallery::routes))
            // 分类器 API 路由
            .service(web::scope("/api/classifier").configure(classifier::routes))
            // 设置 API 路由
            .service(web::scope("/api/settings").configure(settings::routes))
            // 下载器 API 路由
            .service(web::scope("/api/downloader").configure(downloader::routes))
            // 上传器 API 路由
            .service(web::scope("/api/uploader").configure(uploader::routes))
            // 文件系统浏览 API 路由
            .service(web::scope("/api/filesystem").configure(filesystem::routes))
            // 静态文件服务（嵌入式）
            .route("/", web::get().to(serve_static))
            .route("/{filename:.*}", web::get().to(serve_static))
    })
    .bind("0.0.0.0:1234")?
    .run()
    .await
}
