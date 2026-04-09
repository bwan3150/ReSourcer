// FFmpeg等工具函数（从gallery/handlers.rs迁移）
use std::path::{Path, PathBuf};
use std::fs;
use actix_web::Result;
use std::process::Command;

/// 获取 tools/ 目录路径（基于 app_dir，与部署目录一致）
fn tools_dir() -> PathBuf {
    crate::static_files::app_dir().join("tools")
}

/// 获取 ffmpeg 二进制文件路径（从 tools/ 目录查找，不存在则从配置的 URL 下载）
pub fn get_ffmpeg_path() -> PathBuf {
    let binary_name = crate::tools::tool_binary_name("ffmpeg");
    let ffmpeg_path = tools_dir().join(&binary_name);

    if ffmpeg_path.exists() {
        return ffmpeg_path;
    }

    let download_url = crate::tools::get_tool_download_url("ffmpeg")
        .expect("未找到 ffmpeg 下载源配置");

    // 同步下载（preview 调用链是同步的）
    eprintln!("[ffmpeg] 未找到 ffmpeg，正在下载...");
    eprintln!("[ffmpeg] URL: {}", download_url);

    let dir = ffmpeg_path.parent().unwrap();
    fs::create_dir_all(dir).expect("无法创建 tools 目录");

    let output = std::process::Command::new("curl")
        .args(&["-sSL", "-o", ffmpeg_path.to_str().unwrap(), &download_url])
        .output()
        .expect("无法执行 curl 下载 ffmpeg");

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        panic!("下载 ffmpeg 失败: {}", stderr);
    }

    // Unix 设置可执行权限
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mut perms = fs::metadata(&ffmpeg_path)
            .expect("无法读取文件元数据")
            .permissions();
        perms.set_mode(0o755);
        fs::set_permissions(&ffmpeg_path, perms)
            .expect("无法设置可执行权限");
    }

    // macOS: 清除 quarantine 属性
    #[cfg(target_os = "macos")]
    {
        let _ = std::process::Command::new("xattr")
            .args(&["-cr", ffmpeg_path.to_str().unwrap()])
            .output();
    }

    eprintln!("[ffmpeg] 下载完成: {}", ffmpeg_path.display());
    ffmpeg_path
}

/// 从视频提取首帧
pub fn extract_video_first_frame(video_path: &Path) -> Result<image::DynamicImage> {
    // 获取内嵌的 ffmpeg 路径
    let ffmpeg_path = get_ffmpeg_path();

    // 创建临时文件保存首帧
    let temp_output = std::env::temp_dir().join(format!("thumb_{}.jpg", uuid::Uuid::new_v4()));

    // 使用 ffmpeg 提取第一帧
    // -i: 输入文件
    // -vf "select=eq(n\,0)": 选择第一帧
    // -vframes 1: 只输出1帧
    // -q:v 2: 高质量输出
    let output = Command::new(&ffmpeg_path)
        .args(&[
            "-i", video_path.to_str().unwrap(),
            "-vf", "select=eq(n\\,0)",
            "-vframes", "1",
            "-q:v", "2",
            "-y", // 覆盖已存在的文件
            temp_output.to_str().unwrap(),
        ])
        .output()
        .map_err(|e| {
            actix_web::error::ErrorInternalServerError(
                format!("FFmpeg 执行失败 (请确保已安装 ffmpeg): {}", e)
            )
        })?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        // 清理临时文件
        let _ = fs::remove_file(&temp_output);
        return Err(actix_web::error::ErrorInternalServerError(
            format!("FFmpeg 提取首帧失败: {}", stderr)
        ));
    }

    // 读取生成的首帧图片
    let img = image::open(&temp_output)
        .map_err(|e| {
            let _ = fs::remove_file(&temp_output);
            actix_web::error::ErrorInternalServerError(format!("无法读取视频首帧: {}", e))
        })?;

    // 清理临时文件
    let _ = fs::remove_file(&temp_output);

    Ok(img)
}

/// 使用 ffmpeg 提取音频文件的嵌入封面图（专辑封面）
/// 如果音频文件没有嵌入封面，返回 None
pub fn extract_audio_cover(audio_path: &Path) -> Option<image::DynamicImage> {
    let ffmpeg_path = get_ffmpeg_path();
    let temp_output = std::env::temp_dir().join(format!("cover_{}.jpg", uuid::Uuid::new_v4()));

    // ffmpeg -i input.mp3 -an -vcodec mjpeg -vframes 1 output.jpg
    let output = Command::new(&ffmpeg_path)
        .args(&[
            "-i", audio_path.to_str()?,
            "-an",
            "-vcodec", "mjpeg",
            "-vframes", "1",
            "-y",
            temp_output.to_str()?,
        ])
        .output()
        .ok()?;

    if !output.status.success() {
        let _ = fs::remove_file(&temp_output);
        return None;
    }

    let img = image::open(&temp_output).ok();
    let _ = fs::remove_file(&temp_output);
    img
}

/// 使用 ffmpeg 将图片（HEIC/AVIF 等 image 库不支持的格式）转为 JPEG 后读取
#[allow(dead_code)]
pub fn extract_image_frame_ffmpeg(image_path: &Path) -> Result<image::DynamicImage> {
    extract_image_thumbnail_ffmpeg(image_path, 0)
}

/// 用 ffmpeg 将图片直接缩放到目标尺寸后读取
/// max_size=0 表示不缩放（保留原始分辨率）
/// 用于 image::open 内存超限时的 fallback，避免把超大图完整载入内存
pub fn extract_image_thumbnail_ffmpeg(image_path: &Path, max_size: u32) -> Result<image::DynamicImage> {
    let ffmpeg_path = get_ffmpeg_path();

    let temp_output = std::env::temp_dir().join(format!("img_{}.jpg", uuid::Uuid::new_v4()));

    // 如果指定了目标尺寸，用 scale filter 缩放（保持宽高比）
    let scale_filter = if max_size > 0 {
        format!("scale={}:{}:force_original_aspect_ratio=decrease", max_size, max_size)
    } else {
        String::new()
    };

    let mut args: Vec<&str> = vec!["-i", image_path.to_str().unwrap()];
    let filter_str; // 延长生命周期
    if !scale_filter.is_empty() {
        filter_str = scale_filter;
        args.extend_from_slice(&["-vf", &filter_str]);
    }
    args.extend_from_slice(&["-frames:v", "1", "-update", "1", "-q:v", "2", "-y",
        temp_output.to_str().unwrap()]);

    let output = Command::new(&ffmpeg_path)
        .args(&args)
        .output()
        .map_err(|e| {
            actix_web::error::ErrorInternalServerError(format!("FFmpeg 执行失败: {}", e))
        })?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        let _ = fs::remove_file(&temp_output);
        return Err(actix_web::error::ErrorInternalServerError(
            format!("FFmpeg 图片转换失败: {}", stderr)
        ));
    }

    let img = image::open(&temp_output)
        .map_err(|e| {
            let _ = fs::remove_file(&temp_output);
            actix_web::error::ErrorInternalServerError(format!("无法读取转换后的图片: {}", e))
        })?;

    let _ = fs::remove_file(&temp_output);
    Ok(img)
}

/// 从 CLIP (Clip Studio Paint) 文件的内嵌 SQLite 数据库中提取缩略图
///
/// .clip 文件结构：文件头部分 + 嵌入的 SQLite 数据库
/// SQLite 数据库中 CanvasPreview 表存储了 PNG 格式的缩略图
pub fn extract_clip_thumbnail(clip_path: &Path) -> Result<image::DynamicImage> {
    // 读取整个文件
    let data = fs::read(clip_path)
        .map_err(|e| actix_web::error::ErrorInternalServerError(format!("无法读取 CLIP 文件: {}", e)))?;

    // 搜索 SQLite 魔数 "SQLite format 3\000"
    let sqlite_magic = b"SQLite format 3\x00";
    let offset = data.windows(sqlite_magic.len())
        .position(|window| window == sqlite_magic)
        .ok_or_else(|| actix_web::error::ErrorBadRequest("CLIP 文件中未找到 SQLite 数据库"))?;

    // 将 SQLite 部分写入临时文件（rusqlite 需要文件路径）
    let temp_db = std::env::temp_dir().join(format!("clip_{}.db", uuid::Uuid::new_v4()));
    fs::write(&temp_db, &data[offset..])
        .map_err(|e| actix_web::error::ErrorInternalServerError(format!("无法写入临时数据库: {}", e)))?;

    // 打开 SQLite 数据库并查询缩略图
    let conn = rusqlite::Connection::open(&temp_db)
        .map_err(|e| {
            let _ = fs::remove_file(&temp_db);
            actix_web::error::ErrorInternalServerError(format!("无法打开 CLIP 数据库: {}", e))
        })?;

    let image_data: Vec<u8> = conn.query_row(
        "SELECT ImageData FROM CanvasPreview LIMIT 1",
        [],
        |row| row.get(0),
    ).map_err(|e| {
        let _ = fs::remove_file(&temp_db);
        actix_web::error::ErrorInternalServerError(format!("无法从 CLIP 提取预览图: {}", e))
    })?;

    let _ = fs::remove_file(&temp_db);

    // 解码 PNG 数据为 DynamicImage
    let img = image::load_from_memory_with_format(&image_data, image::ImageFormat::Png)
        .or_else(|_| image::load_from_memory(&image_data))
        .map_err(|e| actix_web::error::ErrorInternalServerError(format!("无法解码 CLIP 预览图: {}", e)))?;

    Ok(img)
}

/// 使用 MuPDF 渲染 PDF 第一页为缩略图
pub fn extract_pdf_thumbnail(pdf_path: &Path) -> Result<image::DynamicImage> {
    let path_str = pdf_path.to_str()
        .ok_or_else(|| actix_web::error::ErrorBadRequest("无效的文件路径"))?;

    let doc = mupdf::Document::open(path_str)
        .map_err(|e| actix_web::error::ErrorInternalServerError(format!("无法打开 PDF: {}", e)))?;

    let page = doc.load_page(0)
        .map_err(|e| actix_web::error::ErrorInternalServerError(format!("无法加载 PDF 页面: {}", e)))?;

    let bounds = page.bounds()
        .map_err(|e| actix_web::error::ErrorInternalServerError(format!("无法获取页面尺寸: {}", e)))?;

    // 缩放到约 600px 宽
    let scale = if bounds.x1 - bounds.x0 > 0.0 {
        600.0 / (bounds.x1 - bounds.x0)
    } else {
        2.0
    };
    let matrix = mupdf::Matrix::new_scale(scale, scale);

    let pixmap = page.to_pixmap(&matrix, &mupdf::Colorspace::device_rgb(), false, true)
        .map_err(|e| actix_web::error::ErrorInternalServerError(format!("无法渲染 PDF 页面: {}", e)))?;

    let width = pixmap.width() as u32;
    let height = pixmap.height() as u32;
    let samples = pixmap.samples();

    // MuPDF 输出 RGB 数据，转为 image::DynamicImage
    let img = image::RgbImage::from_raw(width, height, samples.to_vec())
        .ok_or_else(|| actix_web::error::ErrorInternalServerError("无法从像素数据创建图片"))?;

    Ok(image::DynamicImage::ImageRgb8(img))
}
