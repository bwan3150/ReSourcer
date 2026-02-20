// 文件内容服务功能（从classifier/handlers.rs迁移serve_file）
use actix_files::NamedFile;
use actix_web::{web, Result};
use std::path::Path;

use super::models::CLIP_EXTENSION;
use super::utils::{get_ffmpeg_path, extract_clip_thumbnail};

/// 不被 AVPlayer 原生支持、需要转码的视频格式
const TRANSCODE_VIDEO_EXTENSIONS: &[&str] = &["wmv", "flv", "avi"];

/// GET /api/preview/content/{path:.*}
/// 提供文件服务（支持Range请求，流式传输）
///
/// 使用 NamedFile 替代手动读取，优势：
/// - 流式分块传输，不会将整个文件读入内存
/// - 自动处理 Range 请求（206 Partial Content）
/// - 自动检测 Content-Type
/// - 支持条件请求（If-Modified-Since / ETag）
///
/// 对于 AVPlayer 不支持的视频格式（WMV/FLV/AVI），自动转码为 MP4
/// 转码结果缓存在原文件所在目录的 .transcoded/ 子文件夹中
///
/// 对于 .clip (Clip Studio Paint) 文件，提取内嵌 PNG 预览图并缓存返回
pub async fn serve_file(
    path: web::Path<String>,
    query: web::Query<std::collections::HashMap<String, String>>,
    _req: actix_web::HttpRequest,
) -> Result<NamedFile> {
    let file_path = percent_encoding::percent_decode_str(&path)
        .decode_utf8_lossy()
        .to_string();

    let source_path = Path::new(&file_path);

    // 检查是否需要转码（通过 transcode 查询参数或文件扩展名自动判断）
    let extension = source_path
        .extension()
        .and_then(|e| e.to_str())
        .unwrap_or("")
        .to_lowercase();

    // .clip 文件：提取内嵌 PNG 预览图（缓存到 .transcoded/ 目录）
    if extension == CLIP_EXTENSION && source_path.exists() {
        let parent = source_path.parent()
            .ok_or_else(|| actix_web::error::ErrorInternalServerError("无法获取文件所在目录"))?;
        let transcode_dir = parent.join(".transcoded");
        let stem = source_path.file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or("output");
        let cache_path = transcode_dir.join(format!("{}.png", stem));

        // 如果缓存存在且比源文件新，直接返回
        if cache_path.exists() {
            let src_modified = std::fs::metadata(source_path)
                .and_then(|m| m.modified()).ok();
            let cache_modified = std::fs::metadata(&cache_path)
                .and_then(|m| m.modified()).ok();
            if let (Some(src_t), Some(cache_t)) = (src_modified, cache_modified) {
                if cache_t >= src_t {
                    return Ok(NamedFile::open_async(&cache_path).await?);
                }
            }
        }

        // 提取预览图并缓存
        std::fs::create_dir_all(&transcode_dir)
            .map_err(|e| actix_web::error::ErrorInternalServerError(
                format!("无法创建转码目录: {}", e)
            ))?;

        let img = extract_clip_thumbnail(source_path)?;
        img.save_with_format(&cache_path, image::ImageFormat::Png)
            .map_err(|e| actix_web::error::ErrorInternalServerError(
                format!("无法保存 CLIP 预览图: {}", e)
            ))?;

        return Ok(NamedFile::open_async(&cache_path).await?);
    }

    let needs_transcode = query.get("transcode").map(|v| v == "mp4").unwrap_or(false)
        || TRANSCODE_VIDEO_EXTENSIONS.contains(&extension.as_str());

    if needs_transcode && source_path.exists() {
        // 转码后的 MP4 存放在原文件所在目录的 .transcoded/ 子文件夹
        let parent = source_path.parent()
            .ok_or_else(|| actix_web::error::ErrorInternalServerError("无法获取文件所在目录"))?;
        let transcode_dir = parent.join(".transcoded");

        // 生成输出文件名：原文件名（不含扩展名）.mp4
        let stem = source_path.file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or("output");
        let cache_path = transcode_dir.join(format!("{}.mp4", stem));

        // 如果缓存文件存在且比源文件新，直接返回
        if cache_path.exists() {
            let src_modified = std::fs::metadata(source_path)
                .and_then(|m| m.modified())
                .ok();
            let cache_modified = std::fs::metadata(&cache_path)
                .and_then(|m| m.modified())
                .ok();

            if let (Some(src_t), Some(cache_t)) = (src_modified, cache_modified) {
                if cache_t >= src_t {
                    return Ok(NamedFile::open_async(&cache_path).await?);
                }
            }
        }

        // 确保 .transcoded/ 目录存在
        std::fs::create_dir_all(&transcode_dir)
            .map_err(|e| actix_web::error::ErrorInternalServerError(
                format!("无法创建转码目录: {}", e)
            ))?;

        // 使用 ffmpeg 转码为 MP4
        let ffmpeg_path = get_ffmpeg_path();
        let output = std::process::Command::new(&ffmpeg_path)
            .args(&[
                "-i", &file_path,
                "-c:v", "libx264",
                "-preset", "fast",
                "-crf", "23",
                "-c:a", "aac",
                "-b:a", "128k",
                "-movflags", "+faststart",  // 将 moov atom 移到文件头部，支持流式播放
                "-y",
                cache_path.to_str().unwrap(),
            ])
            .output()
            .map_err(|e| {
                actix_web::error::ErrorInternalServerError(format!("FFmpeg 转码失败: {}", e))
            })?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            let _ = std::fs::remove_file(&cache_path);
            return Err(actix_web::error::ErrorInternalServerError(
                format!("视频转码失败: {}", stderr)
            ));
        }

        return Ok(NamedFile::open_async(&cache_path).await?);
    }

    Ok(NamedFile::open_async(file_path).await?)
}
