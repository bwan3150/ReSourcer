use actix_web::{middleware, web, App, HttpResponse, HttpServer, Result};
use serde::Deserialize;
use std::net::UdpSocket;

mod classifier;
mod downloader;
mod uploader;
mod static_files;

use static_files::{serve_static, ConfigAsset};

#[derive(Deserialize)]
struct DependencyInfo {
    version: String,
}

#[derive(Deserialize)]
struct Dependencies {
    #[serde(rename = "yt-dlp")]
    yt_dlp: DependencyInfo,
}

/// 全局配置 API - 所有模块共用
async fn get_global_config() -> Result<HttpResponse> {
    let config = classifier::config::load_config()
        .map_err(|e| actix_web::error::ErrorInternalServerError(format!("无法加载配置: {}", e)))?;

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "source_folder": config.source_folder,
        "hidden_folders": config.hidden_folders,
    })))
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
    let task_manager = web::Data::new(downloader::TaskManager::new());

    // 从嵌入的配置文件读取依赖信息
    let ytdlp_version = if let Some(config_file) = ConfigAsset::get("dependencies.json") {
        match serde_json::from_slice::<Dependencies>(&config_file.data) {
            Ok(deps) => deps.yt_dlp.version,
            Err(_) => "unknown".to_string(),
        }
    } else {
        "unknown".to_string()
    };

    // 服务信息框
    println!("  ┌──────────────────────────────────────────────┐");
    let service_line = format!("  │ Service URL:    http://{}:1234   ", local_ip);
    println!("{:<47}│", service_line);

    let version_line = format!("  │ yt-dlp version: {:<29}│", ytdlp_version);
    println!("{}", version_line);

    println!("  └──────────────────────────────────────────────┘");
    println!();

    // 延迟打开浏览器
    let browser_url = format!("http://{}:1234", local_ip);
    tokio::spawn(async move {
        tokio::time::sleep(tokio::time::Duration::from_millis(1500)).await;
        if let Err(e) = open::that(&browser_url) {
            eprintln!("  Failed to open browser: {}", e);
            println!("  Please visit manually: {}", browser_url);
        }
    });

    HttpServer::new(move || {
        App::new()
            .wrap(middleware::Logger::default())
            // 注入下载器任务管理器
            .app_data(task_manager.clone())
            // 全局配置 API（所有模块共用）
            .route("/api/config", web::get().to(get_global_config))
            // 分类器 API 路由
            .service(web::scope("/api/classifier").configure(classifier::routes))
            // 下载器 API 路由
            .service(web::scope("/api/downloader").configure(downloader::routes))
            // 上传器 API 路由
            .service(web::scope("/api/uploader").configure(uploader::routes))
            // 静态文件服务（嵌入式）
            .route("/", web::get().to(serve_static))
            .route("/{filename:.*}", web::get().to(serve_static))
    })
    .bind("0.0.0.0:1234")?
    .run()
    .await
}
