use actix_web::{HttpRequest, HttpResponse, Result};
use rust_embed::RustEmbed;

// 嵌入static目录中的所有文件
#[derive(RustEmbed)]
#[folder = "static/"]
pub struct Asset;

// 嵌入config目录中的所有文件
#[derive(RustEmbed)]
#[folder = "config/"]
pub struct ConfigAsset;

// 从嵌入的资源中提供静态文件
pub async fn serve_static(req: HttpRequest) -> Result<HttpResponse> {
    let raw_path = req.match_info().query("filename");

    // 构建实际路径
    let path = if raw_path.is_empty() {
        "index.html".to_string()
    } else if raw_path.ends_with('/') {
        format!("{}index.html", raw_path)
    } else {
        raw_path.to_string()
    };

    // 先尝试直接访问
    let result = Asset::get(&path);

    // 如果找不到，尝试添加 index.html
    let content = if result.is_none() && !path.ends_with(".html") && !path.ends_with(".js") && !path.ends_with(".css") {
        let index_path = format!("{}/index.html", path);
        Asset::get(&index_path)
    } else {
        result
    };

    match content {
        Some(content) => {
            let mime_type = mime_guess::from_path(&path)
                .first_or_octet_stream()
                .to_string();

            Ok(HttpResponse::Ok()
                .content_type(mime_type)
                .body(content.data.into_owned()))
        }
        None => Ok(HttpResponse::NotFound().body("404 Not Found")),
    }
}