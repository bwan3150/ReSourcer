// 缩略图生成功能（从gallery/handlers.rs迁移）
use actix_web::{web, HttpResponse, Result};
use std::path::Path;
use std::io::Cursor;
use image::ImageFormat;
use super::models::*;
use super::utils::extract_video_first_frame;

/// GET /api/preview/thumbnail?path=<file_path>&size=<size>
/// 生成并返回图片/视频缩略图
pub async fn get_thumbnail(query: web::Query<std::collections::HashMap<String, String>>) -> Result<HttpResponse> {
    let file_path = query.get("path")
        .ok_or_else(|| actix_web::error::ErrorBadRequest("缺少 path 参数"))?;

    let size: u32 = query.get("size")
        .and_then(|s| s.parse().ok())
        .unwrap_or(300); // 默认300px

    let path = Path::new(file_path);
    if !path.exists() || !path.is_file() {
        return Err(actix_web::error::ErrorNotFound("文件不存在"));
    }

    // 获取扩展名判断文件类型
    let extension = path
        .extension()
        .and_then(|e| e.to_str())
        .unwrap_or("")
        .to_lowercase();

    // 判断文件类型
    let is_video = VIDEO_EXTENSIONS.contains(&extension.as_str());
    let is_image = extension == GIF_EXTENSION || IMAGE_EXTENSIONS.contains(&extension.as_str());

    if !is_video && !is_image {
        return Err(actix_web::error::ErrorBadRequest("不支持的媒体格式"));
    }

    // 根据文件类型读取图片或提取视频首帧
    let img = if is_video {
        extract_video_first_frame(path)?
    } else {
        image::open(path)
            .map_err(|e| actix_web::error::ErrorInternalServerError(format!("无法读取图片: {}", e)))?
    };

    // 生成缩略图 (保持宽高比)
    let thumbnail = img.thumbnail(size, size);

    // 将缩略图编码为JPEG格式
    let mut buffer = Cursor::new(Vec::new());
    thumbnail.write_to(&mut buffer, ImageFormat::Jpeg)
        .map_err(|e| actix_web::error::ErrorInternalServerError(format!("无法编码图片: {}", e)))?;

    Ok(HttpResponse::Ok()
        .content_type("image/jpeg")
        .body(buffer.into_inner()))
}
