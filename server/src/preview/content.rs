// 文件内容服务功能（从classifier/handlers.rs迁移serve_file）
use actix_files::NamedFile;
use actix_web::{web, Result, http::header::{ContentDisposition, DispositionType}};
use std::path::Path;

use super::models::CLIP_EXTENSION;
use super::utils::{get_ffmpeg_path, extract_clip_thumbnail};

/// 不被浏览器/AVPlayer 原生支持、需要转码为 MP4 的视频格式
const TRANSCODE_VIDEO_EXTENSIONS: &[&str] = &["wmv", "flv", "avi", "mkv", "webm"];

/// 需要检查 faststart 的容器格式
const FASTSTART_CHECK_EXTENSIONS: &[&str] = &["mp4", "mov", "m4v"];

/// 可能包含 HEVC hev1 编码的容器格式（iOS AVPlayer 要求 hvc1 tag）
const HEVC_CHECK_EXTENSIONS: &[&str] = &["mp4", "mov", "m4v"];

/// 检测视频文件是否为 HEVC hev1 编码。
/// iOS AVPlayer 只支持 hvc1 tag 的 HEVC，hev1 tag（ffmpeg/非 Apple 编码器默认）会黑屏。
fn is_hevc_hev1(file_path: &str, ffmpeg_path: &std::path::PathBuf) -> bool {
    // ffmpeg -hide_banner -i <file> 会把流信息输出到 stderr
    let output = std::process::Command::new(ffmpeg_path)
        .args(["-hide_banner", "-i", file_path])
        .output();
    match output {
        Ok(o) => {
            let stderr = String::from_utf8_lossy(&o.stderr);
            // 示例：Stream #0:0: Video: hevc (Main) (hev1 / 0x31766568), ...
            // 用 "(hev1" 而非裸的 "hev1"，避免文件路径中含 "hev1" 导致误判
            let lower = stderr.to_lowercase();
            lower.contains("video: hevc") && lower.contains("(hev1")
        }
        Err(_) => false,
    }
}

/// Check if an MP4 file has moov atom before mdat (faststart).
/// Reads the file's top-level atoms sequentially. If mdat comes before moov, it's not faststart.
fn is_faststart(file_path: &Path) -> bool {
    use std::io::{Read, Seek, SeekFrom};
    let Ok(mut f) = std::fs::File::open(file_path) else { return true };
    let Ok(file_size) = f.seek(SeekFrom::End(0)) else { return true };
    let _ = f.seek(SeekFrom::Start(0));

    let mut pos: u64 = 0;
    let mut buf = [0u8; 8];
    while pos < file_size {
        if f.read_exact(&mut buf).is_err() { break }
        let size = u32::from_be_bytes([buf[0], buf[1], buf[2], buf[3]]) as u64;
        let atom_type = &buf[4..8];

        let atom_size = if size == 1 {
            // 64-bit extended size
            let mut ext = [0u8; 8];
            if f.read_exact(&mut ext).is_err() { break }
            u64::from_be_bytes(ext)
        } else if size == 0 {
            file_size - pos // atom extends to end of file
        } else {
            size
        };

        if atom_type == b"moov" { return true }  // moov found first → faststart
        if atom_type == b"mdat" { return false }  // mdat found first → not faststart

        if atom_size < 8 { break }
        pos += atom_size;
        let _ = f.seek(SeekFrom::Start(pos));
    }
    true // edge case: no mdat found, assume OK
}

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
    // 支持通过 UUID 查询文件路径
    let file_path = if let Some(uuid) = query.get("uuid") {
        let file = crate::indexer::storage::get_file_by_uuid(uuid)
            .map_err(|e| actix_web::error::ErrorInternalServerError(format!("数据库错误: {}", e)))?
            .ok_or_else(|| actix_web::error::ErrorNotFound("UUID 对应的文件未找到"))?;
        file.current_path
            .ok_or_else(|| actix_web::error::ErrorNotFound("文件已被删除或移动"))?
    } else {
        percent_encoding::percent_decode_str(&path)
            .decode_utf8_lossy()
            .to_string()
    };

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
                    return Ok(safe_named_file(&cache_path.to_string_lossy()).await?);
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

        return Ok(safe_named_file(&cache_path.to_string_lossy()).await?);
    }

    // 检测 MP4 是否缺少 faststart（moov atom 在 mdat 之后）
    // 缺少 faststart 会导致浏览器无法边下边播，必须下载完整文件才能开始
    if FASTSTART_CHECK_EXTENSIONS.contains(&extension.as_str()) && source_path.exists() && !is_faststart(source_path) {
        let parent = source_path.parent()
            .ok_or_else(|| actix_web::error::ErrorInternalServerError("无法获取文件所在目录"))?;
        let transcode_dir = parent.join(".transcoded");
        let stem = source_path.file_stem().and_then(|s| s.to_str()).unwrap_or("output");
        let cache_path = transcode_dir.join(format!("{}_faststart.mp4", stem));

        // Check if cached version exists and is newer than source
        if cache_path.exists() {
            let src_modified = std::fs::metadata(source_path).and_then(|m| m.modified()).ok();
            let cache_modified = std::fs::metadata(&cache_path).and_then(|m| m.modified()).ok();
            if let (Some(src_t), Some(cache_t)) = (src_modified, cache_modified) {
                if cache_t >= src_t {
                    return Ok(safe_named_file(&cache_path.to_string_lossy()).await?);
                }
            }
        }

        // Remux with faststart (copy streams, no re-encoding, very fast)
        std::fs::create_dir_all(&transcode_dir)
            .map_err(|e| actix_web::error::ErrorInternalServerError(format!("无法创建转码目录: {}", e)))?;

        let ffmpeg_path = get_ffmpeg_path();
        let cache_path_str = cache_path.to_str()
            .ok_or_else(|| actix_web::error::ErrorInternalServerError("缓存路径含非 UTF-8 字符"))?;

        eprintln!("[faststart] remuxing: {}", source_path.display());
        let output = std::process::Command::new(&ffmpeg_path)
            .args(["-i", &file_path, "-c", "copy", "-movflags", "+faststart", "-y", cache_path_str])
            .output()
            .map_err(|e| actix_web::error::ErrorInternalServerError(format!("ffmpeg faststart 失败: {}", e)))?;

        if output.status.success() {
            return Ok(safe_named_file(&cache_path.to_string_lossy()).await?);
        } else {
            let _ = std::fs::remove_file(&cache_path);
            // Fallback to original file
        }
    }

    // 检测 HEVC hev1 → 重封装为 hvc1（iOS AVPlayer 兼容）
    // 只检测可能包含 HEVC 的容器格式，避免对图片/音频等无谓运行 ffmpeg
    if HEVC_CHECK_EXTENSIONS.contains(&extension.as_str()) && source_path.exists() {
        let parent = source_path.parent()
            .ok_or_else(|| actix_web::error::ErrorInternalServerError("无法获取文件所在目录"))?;
        let transcode_dir = parent.join(".transcoded");
        let stem = source_path.file_stem().and_then(|s| s.to_str()).unwrap_or("output");
        let cache_path = transcode_dir.join(format!("{}_hvc1.mp4", stem));
        let skip_marker = transcode_dir.join(format!("{}.not_hev1", stem));

        let src_modified = std::fs::metadata(source_path).and_then(|m| m.modified()).ok();

        // 1. 已重封装的缓存存在且比源文件新 → 直接返回，不再探测
        if cache_path.exists() {
            let cache_modified = std::fs::metadata(&cache_path).and_then(|m| m.modified()).ok();
            if let (Some(src_t), Some(cache_t)) = (src_modified, cache_modified) {
                if cache_t >= src_t {
                    return Ok(safe_named_file(&cache_path.to_string_lossy()).await?);
                }
            }
        }

        // 2. 已确认非 hev1 的标记文件存在且比源文件新 → 跳过探测直接返回原文件
        if skip_marker.exists() {
            let marker_modified = std::fs::metadata(&skip_marker).and_then(|m| m.modified()).ok();
            if let (Some(src_t), Some(marker_t)) = (src_modified, marker_modified) {
                if marker_t >= src_t {
                    // 不是 hev1，直接走下面的正常流程
                    return Ok(safe_named_file(&file_path).await?);
                }
            }
        }

        // 3. 首次请求：运行 ffmpeg 探测，结果持久化避免重复探测
        let ffmpeg_path = get_ffmpeg_path();
        if is_hevc_hev1(&file_path, &ffmpeg_path) {
            std::fs::create_dir_all(&transcode_dir)
                .map_err(|e| actix_web::error::ErrorInternalServerError(
                    format!("无法创建转码目录: {}", e)
                ))?;

            // 只改 tag，不重新编码，速度极快
            let cache_path_str = cache_path.to_str()
                .ok_or_else(|| actix_web::error::ErrorInternalServerError("缓存路径含非 UTF-8 字符"))?;
            let output = std::process::Command::new(&ffmpeg_path)
                .args([
                    "-i", &file_path,
                    "-c", "copy",
                    "-tag:v", "hvc1",
                    "-movflags", "+faststart",
                    "-y",
                    cache_path_str,
                ])
                .output()
                .map_err(|e| actix_web::error::ErrorInternalServerError(
                    format!("ffmpeg 重封装失败: {}", e)
                ))?;

            if output.status.success() {
                return Ok(safe_named_file(&cache_path.to_string_lossy()).await?);
            } else {
                // 重封装失败，降级直接返回原文件
                let _ = std::fs::remove_file(&cache_path);
            }
        } else {
            // 非 hev1，写入标记文件，下次请求直接跳过探测
            let _ = std::fs::create_dir_all(&transcode_dir);
            let _ = std::fs::write(&skip_marker, b"");
        }
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
                    return Ok(safe_named_file(&cache_path.to_string_lossy()).await?);
                }
            }
        }

        // 确保 .transcoded/ 目录存在
        std::fs::create_dir_all(&transcode_dir)
            .map_err(|e| actix_web::error::ErrorInternalServerError(
                format!("无法创建转码目录: {}", e)
            ))?;

        // 使用 ffmpeg 转码为 MP4
        // 先尝试 -c copy（只换容器，不重编码，秒级完成）
        // 如果源编码不兼容 MP4 容器，再 fallback 到重编码
        let ffmpeg_path = get_ffmpeg_path();
        let cache_path_str = cache_path.to_str()
            .ok_or_else(|| actix_web::error::ErrorInternalServerError("缓存路径含非 UTF-8 字符"))?;

        eprintln!("[transcode] trying remux (copy) for: {}", source_path.display());
        let remux = std::process::Command::new(&ffmpeg_path)
            .args(&[
                "-i", &file_path,
                "-c", "copy",
                "-movflags", "+faststart",
                "-y",
                cache_path_str,
            ])
            .output();

        let remux_ok = remux.as_ref().map(|o| o.status.success()).unwrap_or(false);

        if !remux_ok {
            // Remux failed — fallback to re-encode
            let _ = std::fs::remove_file(&cache_path);
            eprintln!("[transcode] remux failed, re-encoding: {}", source_path.display());
            let output = std::process::Command::new(&ffmpeg_path)
                .args(&[
                    "-i", &file_path,
                    "-c:v", "libx264",
                    "-preset", "fast",
                    "-crf", "23",
                    "-c:a", "aac",
                    "-b:a", "128k",
                    "-movflags", "+faststart",
                    "-y",
                    cache_path_str,
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
        } else {
            eprintln!("[transcode] remux succeeded: {}", cache_path.display());
        }

        return Ok(safe_named_file(&cache_path.to_string_lossy()).await?);
    }

    Ok(safe_named_file(&file_path).await?)
}

/// Open a NamedFile with a safe content-disposition header.
/// Avoids issues with long/unicode/emoji filenames breaking browser header parsing.
async fn safe_named_file(path: &str) -> std::io::Result<NamedFile> {
    let mut f = NamedFile::open_async(path).await?;
    f = f.set_content_disposition(ContentDisposition {
        disposition: DispositionType::Inline,
        parameters: vec![],
    });
    Ok(f)
}
