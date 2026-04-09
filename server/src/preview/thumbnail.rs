// 缩略图生成功能（从gallery/handlers.rs迁移）
use actix_web::{web, HttpResponse, Result};
use std::path::Path;
use std::io::Cursor;
use image::ImageFormat;
use super::models::*;
use super::utils::{extract_video_first_frame, extract_audio_cover, extract_clip_thumbnail, extract_image_thumbnail_ffmpeg, extract_pdf_thumbnail};

/// GET /api/preview/thumbnail?path=<file_path>&size=<size>
/// GET /api/preview/thumbnail?uuid=<uuid>&size=<size>
/// 生成并返回图片/视频缩略图，支持通过 UUID 或路径查询
pub async fn get_thumbnail(query: web::Query<std::collections::HashMap<String, String>>) -> Result<HttpResponse> {
    // 优先使用 UUID 查询
    let file_path_resolved = if let Some(uuid) = query.get("uuid") {
        let file = crate::indexer::storage::get_file_by_uuid(uuid)
            .map_err(|e| actix_web::error::ErrorInternalServerError(format!("数据库错误: {}", e)))?
            .ok_or_else(|| actix_web::error::ErrorNotFound("UUID 对应的文件未找到"))?;
        file.current_path
            .ok_or_else(|| actix_web::error::ErrorNotFound("文件已被删除或移动"))?
    } else {
        query.get("path")
            .ok_or_else(|| actix_web::error::ErrorBadRequest("缺少 path 或 uuid 参数"))?
            .clone()
    };

    let size: u32 = query.get("size")
        .and_then(|s| s.parse().ok())
        .unwrap_or(300); // 默认300px

    let path = Path::new(&file_path_resolved);
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
    let is_audio = AUDIO_EXTENSIONS.contains(&extension.as_str());

    if !is_video && !is_image && !is_clip && !is_pdf && !is_audio {
        return Err(actix_web::error::ErrorBadRequest("不支持的媒体格式"));
    }

    // 根据文件类型读取图片或提取视频首帧
    let img = if is_audio {
        // 音频：尝试提取嵌入的专辑封面
        match extract_audio_cover(path) {
            Some(img) => img,
            None => return Err(actix_web::error::ErrorNotFound("音频文件没有嵌入封面")),
        }
    } else if is_video {
        extract_video_first_frame(path)?
    } else if is_clip {
        // CLIP 文件：从内嵌 SQLite 提取缩略图
        extract_clip_thumbnail(path)?
    } else if is_pdf {
        // PDF 文件：用 MuPDF 渲染第一页
        match extract_pdf_thumbnail(path) {
            Ok(img) => img,
            Err(e) => {
                eprintln!("[thumbnail] PDF 渲染失败 ({:?}): {}", path, e);
                return Err(actix_web::error::ErrorBadRequest("PDF 缩略图生成失败"));
            }
        }
    } else {
        // 先尝试 image 库直接打开，失败则 fallback 到 ffmpeg
        // （用于 HEIC/AVIF 等格式，以及超大图内存超限的情况）
        match image::open(path) {
            Ok(img) => img,
            Err(e) => {
                eprintln!("[thumbnail] image::open 失败 ({:?}): {}", path, e);
                // 直接让 ffmpeg 缩放到目标尺寸，避免超大图再次触发内存超限
                extract_image_thumbnail_ffmpeg(path, size)?
            }
        }
    };

    // 生成缩略图 (保持宽高比)
    let thumbnail = img.thumbnail(size, size);

    // 将缩略图编码为JPEG格式
    // JPEG 不支持 alpha 通道，统一转为 RGB8（兼容 RGBA/RGBA16 等带透明度的图像）
    let thumbnail_rgb = image::DynamicImage::ImageRgb8(thumbnail.into_rgb8());
    let mut buffer = Cursor::new(Vec::new());
    thumbnail_rgb.write_to(&mut buffer, ImageFormat::Jpeg)
        .map_err(|e| actix_web::error::ErrorInternalServerError(format!("无法编码图片: {}", e)))?;

    Ok(HttpResponse::Ok()
        .content_type("image/jpeg")
        // UUID-based thumbnails are immutable — cache aggressively
        // Browser won't re-request the same UUID+size combination
        .insert_header(("Cache-Control", "public, max-age=31536000, immutable"))
        .body(buffer.into_inner()))
}
