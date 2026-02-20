// 缩略图生成功能（从gallery/handlers.rs迁移）
use actix_web::{web, HttpResponse, Result};
use std::path::Path;
use std::io::Cursor;
use image::ImageFormat;
use super::models::*;
use super::utils::{extract_video_first_frame, extract_clip_thumbnail, extract_image_frame_ffmpeg, extract_pdf_thumbnail};

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
    let is_clip = extension == CLIP_EXTENSION;
    let is_pdf = extension == PDF_EXTENSION;

    if !is_video && !is_image && !is_clip && !is_pdf {
        return Err(actix_web::error::ErrorBadRequest("不支持的媒体格式"));
    }

    // 根据文件类型读取图片或提取视频首帧
    let img = if is_video {
        extract_video_first_frame(path)?
    } else if is_clip {
        // CLIP 文件：从内嵌 SQLite 提取缩略图
        extract_clip_thumbnail(path)?
    } else if is_pdf {
        // PDF 文件：用 MuPDF 渲染第一页
        extract_pdf_thumbnail(path)?
    } else {
        // 先尝试 image 库直接打开，失败则 fallback 到 ffmpeg（用于 HEIC/AVIF 等格式）
        match image::open(path) {
            Ok(img) => img,
            Err(_) => extract_image_frame_ffmpeg(path)?,
        }
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
