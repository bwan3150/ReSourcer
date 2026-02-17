// 文件内容服务功能（从classifier/handlers.rs迁移serve_file）
use actix_files::NamedFile;
use actix_web::{web, Result};

/// GET /api/preview/content/{path:.*}
/// 提供文件服务（支持Range请求，流式传输）
///
/// 使用 NamedFile 替代手动读取，优势：
/// - 流式分块传输，不会将整个文件读入内存
/// - 自动处理 Range 请求（206 Partial Content）
/// - 自动检测 Content-Type
/// - 支持条件请求（If-Modified-Since / ETag）
pub async fn serve_file(
    path: web::Path<String>,
    _req: actix_web::HttpRequest,
) -> Result<NamedFile> {
    let file_path = percent_encoding::percent_decode_str(&path)
        .decode_utf8_lossy()
        .to_string();

    Ok(NamedFile::open_async(file_path).await?)
}
