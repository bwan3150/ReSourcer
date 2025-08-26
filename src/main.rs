use actix_web::{middleware, web, App, HttpServer};
use std::env;

mod models;
mod config;
mod handlers;
mod static_files;

use handlers::*;
use static_files::serve_static;

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    // 获取当前目录
    let current_dir = env::current_dir()
        .map(|p| p.to_string_lossy().to_string())
        .unwrap_or_else(|_| "Unknown".to_string());
    
    println!("====================================");
    println!("  Toolkit ReClassifier");
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
            // 使用嵌入的静态资源
            .route("/", web::get().to(serve_static))
            .route("/{filename:.*}", web::get().to(serve_static))
    })
    .bind("0.0.0.0:1234")?
    .run()
    .await
}