// 文件内容服务功能（从classifier/handlers.rs迁移serve_file）
use actix_web::{web, HttpResponse, Result};
use std::path::Path;
use std::fs;

/// GET /api/preview/content/{path:.*}
/// 提供文件服务（支持Range请求）
pub async fn serve_file(
    path: web::Path<String>,
    req: actix_web::HttpRequest,
) -> Result<HttpResponse> {
    let file_path = percent_encoding::percent_decode_str(&path)
        .decode_utf8_lossy()
        .to_string();

    if !Path::new(&file_path).exists() {
        return Ok(HttpResponse::NotFound().body("File not found"));
    }

    let mime_type = mime_guess::from_path(&file_path)
        .first_or_octet_stream()
        .to_string();

    // 获取文件大小
    let metadata = fs::metadata(&file_path)?;
    let file_size = metadata.len();

    // 检查是否有 Range 请求
    if let Some(range_header) = req.headers().get(actix_web::http::header::RANGE) {
        if let Ok(range_str) = range_header.to_str() {
            // 解析 Range 头，格式: bytes=start-end
            if range_str.starts_with("bytes=") {
                let range_str = &range_str[6..];
                let parts: Vec<&str> = range_str.split('-').collect();

                if parts.len() == 2 {
                    let start: u64 = parts[0].parse().unwrap_or(0);
                    let end: u64 = if parts[1].is_empty() {
                        file_size - 1
                    } else {
                        parts[1].parse().unwrap_or(file_size - 1).min(file_size - 1)
                    };

                    if start <= end && end < file_size {
                        // 读取指定范围的文件内容
                        let mut file = std::fs::File::open(&file_path)?;
                        use std::io::{Seek, SeekFrom, Read};
                        file.seek(SeekFrom::Start(start))?;

                        let content_length = (end - start + 1) as usize;
                        let mut buffer = vec![0u8; content_length];
                        file.read_exact(&mut buffer)?;

                        return Ok(HttpResponse::PartialContent()
                            .content_type(mime_type.clone())
                            .insert_header(("Accept-Ranges", "bytes"))
                            .insert_header(("Content-Range", format!("bytes {}-{}/{}", start, end, file_size)))
                            .insert_header(("Content-Length", content_length.to_string()))
                            .body(buffer));
                    }
                }
            }
        }
    }

    // 没有 Range 请求或解析失败，返回完整文件
    let content = fs::read(&file_path)?;
    Ok(HttpResponse::Ok()
        .content_type(mime_type)
        .insert_header(("Accept-Ranges", "bytes"))
        .insert_header(("Content-Length", file_size.to_string()))
        .body(content))
}
