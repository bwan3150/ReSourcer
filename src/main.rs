use actix_web::{middleware, web, App, HttpServer};
use serde::Deserialize;

mod classifier;
mod downloader;
mod uploader;
mod static_files;

use static_files::{serve_static, ConfigAsset};

#[derive(Deserialize)]
struct DependencyInfo {
    version: String,
    last_checked: String,
}

#[derive(Deserialize)]
struct Dependencies {
    #[serde(rename = "yt-dlp")]
    yt_dlp: DependencyInfo,
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    // 打印启动信息
    println!();
    println!(r#"  ____       ____                              "#);
    println!(r#" |  _ \ ___ / ___|  ___  _   _ _ __ ___ ___ _ __"#);
    println!(r#" | |_) / _ \\___ \ / _ \| | | | '__/ __/ _ \ '__|"#);
    println!(r#" |  _ <  __/ ___) | (_) | |_| | | | (_|  __/ |  "#);
    println!(r#" |_| \_\___|____/ \___/ \__,_|_|  \___\___|_|  "#);
    println!();

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
    println!("  ┌─────────────────────────────────────────┐");
    println!("  │ Service URL: http://localhost:1234     │");

    let version_line = format!("  │ yt-dlp version: {:<24}│", ytdlp_version);
    println!("{}", version_line);

    println!("  └─────────────────────────────────────────┘");
    println!();

    // 延迟打开浏览器
    tokio::spawn(async {
        tokio::time::sleep(tokio::time::Duration::from_millis(1500)).await;
        if let Err(e) = open::that("http://localhost:1234") {
            eprintln!("  Failed to open browser: {}", e);
            println!("  Please visit manually: http://localhost:1234");
        }
    });

    HttpServer::new(|| {
        App::new()
            .wrap(middleware::Logger::default())
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