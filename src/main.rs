use actix_web::{middleware, web, App, HttpServer};

mod classifier;
mod downloader;
mod uploader;
mod settings;
mod static_files;

use static_files::serve_static;

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    // 打印启动信息
    println!("====================================");
    println!("  🛠️  Personal Toolkit Server");
    println!("====================================");
    println!("📍 服务地址: http://localhost:1234");
    println!();
    println!("📦 可用模块:");
    println!("  - 📁 资源分类器 /classifier/");
    println!("  - ⬇️  视频下载器 /downloader/");
    println!("  - 📱 文件上传器 /uploader/");
    println!();

    // 检查 yt-dlp 是否可用
    if downloader::check_ytdlp_available() {
        match downloader::get_version() {
            Ok(version) => println!("✅ yt-dlp 版本: {}", version),
            Err(e) => println!("⚠️  yt-dlp 检查失败: {}", e),
        }
    } else {
        println!("⚠️  yt-dlp 未找到，下载器功能将不可用");
    }

    println!("====================================");
    println!("🚀 正在启动服务器...");
    println!("🌐 正在打开浏览器...");
    println!("====================================");

    // 延迟打开浏览器
    tokio::spawn(async {
        tokio::time::sleep(tokio::time::Duration::from_millis(1500)).await;
        if let Err(e) = open::that("http://localhost:1234") {
            eprintln!("❌ 无法自动打开浏览器: {}", e);
            println!("请手动访问: http://localhost:1234");
        }
    });

    HttpServer::new(|| {
        App::new()
            .wrap(middleware::Logger::default())
            // 设置 API 路由
            .service(web::scope("/api/settings").configure(settings::routes))
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