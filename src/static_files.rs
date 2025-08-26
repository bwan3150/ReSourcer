use actix_web::{HttpRequest, HttpResponse, Result};
use rust_embed::RustEmbed;

// 嵌入static目录中的所有文件
#[derive(RustEmbed)]
#[folder = "static/"]
pub struct Asset;

// 从嵌入的资源中提供静态文件
pub async fn serve_static(req: HttpRequest) -> Result<HttpResponse> {
    let path = req.match_info().query("filename");
    let path = if path.is_empty() { "index.html" } else { path };
    
    match Asset::get(path) {
        Some(content) => {
            let mime_type = mime_guess::from_path(path)
                .first_or_octet_stream()
                .to_string();
            
            Ok(HttpResponse::Ok()
                .content_type(mime_type)
                .body(content.data.into_owned()))
        }
        None => Ok(HttpResponse::NotFound().body("404 Not Found")),
    }
}