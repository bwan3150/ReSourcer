use actix_web::{web, HttpResponse, Result};
use std::path::{Path, PathBuf};
use std::fs;
use super::models::*;
use std::io::Cursor;
use std::process::Command;
use image::ImageFormat;

// 在编译时嵌入对应平台的 ffmpeg 二进制文件
static FFMPEG_BINARY: &[u8] = include_bytes!(concat!(env!("OUT_DIR"), "/ffmpeg"));

/// 支持的图片格式
const IMAGE_EXTENSIONS: &[&str] = &["jpg", "jpeg", "png", "webp", "bmp", "tiff", "svg"];

/// 支持的视频格式
const VIDEO_EXTENSIONS: &[&str] = &["mp4", "mov", "avi", "mkv", "flv", "wmv", "m4v", "webm"];

/// GIF 格式
const GIF_EXTENSION: &str = "gif";

/// 注册所有 Gallery 相关路由
pub fn routes(cfg: &mut web::ServiceConfig) {
    cfg.service(web::resource("/folders").route(web::get().to(get_folders)))
       .service(web::resource("/files").route(web::get().to(get_files)))
       .service(web::resource("/thumbnail").route(web::get().to(get_thumbnail)));
}

/// GET /api/gallery/folders
/// 获取所有文件夹列表（源文件夹 + 分类文件夹）
async fn get_folders() -> Result<HttpResponse> {
    let config = crate::classifier::config::load_config()
        .map_err(|e| actix_web::error::ErrorInternalServerError(format!("无法加载配置: {}", e)))?;

    let mut folders = Vec::new();

    // 1. 添加源文件夹
    if let Ok(source_path) = fs::canonicalize(&config.source_folder) {
        if source_path.exists() && source_path.is_dir() {
            let file_count = count_media_files(&source_path);
            folders.push(FolderInfo {
                name: "源文件夹".to_string(),
                path: config.source_folder.clone(),
                is_source: true,
                file_count,
            });
        }
    }

    // 2. 添加分类文件夹（排除隐藏文件夹）
    if let Ok(entries) = fs::read_dir(&config.source_folder) {
        for entry in entries.flatten() {
            if let Ok(metadata) = entry.metadata() {
                if metadata.is_dir() {
                    let folder_name = entry.file_name().to_string_lossy().to_string();

                    // 跳过隐藏文件夹
                    if config.hidden_folders.contains(&folder_name) {
                        continue;
                    }

                    let folder_path = entry.path();
                    let file_count = count_media_files(&folder_path);

                    folders.push(FolderInfo {
                        name: folder_name.clone(),
                        path: folder_path.to_string_lossy().to_string(),
                        is_source: false,
                        file_count,
                    });
                }
            }
        }
    }

    Ok(HttpResponse::Ok().json(FoldersResponse { folders }))
}

/// GET /api/gallery/files?folder=<path>
/// 获取指定文件夹的所有媒体文件
async fn get_files(query: web::Query<std::collections::HashMap<String, String>>) -> Result<HttpResponse> {
    let folder_path = query.get("folder")
        .ok_or_else(|| actix_web::error::ErrorBadRequest("缺少 folder 参数"))?;

    let path = Path::new(folder_path);
    if !path.exists() || !path.is_dir() {
        return Err(actix_web::error::ErrorNotFound("文件夹不存在"));
    }

    let mut files = Vec::new();

    // 读取文件夹中的所有文件
    if let Ok(entries) = fs::read_dir(path) {
        for entry in entries.flatten() {
            if let Ok(metadata) = entry.metadata() {
                if metadata.is_file() {
                    let file_path = entry.path();
                    let file_name = entry.file_name().to_string_lossy().to_string();

                    // 获取扩展名
                    let extension = file_path
                        .extension()
                        .and_then(|e| e.to_str())
                        .unwrap_or("")
                        .to_lowercase();

                    // 判断文件类型
                    let file_type = if extension == GIF_EXTENSION {
                        FileType::Gif
                    } else if IMAGE_EXTENSIONS.contains(&extension.as_str()) {
                        FileType::Image
                    } else if VIDEO_EXTENSIONS.contains(&extension.as_str()) {
                        FileType::Video
                    } else {
                        FileType::Other
                    };

                    // 获取文件大小
                    let size = metadata.len();

                    // 获取修改时间
                    let modified = metadata.modified()
                        .ok()
                        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
                        .map(|d| {
                            let datetime = chrono::DateTime::<chrono::Utc>::from_timestamp(d.as_secs() as i64, 0);
                            datetime.map(|dt| dt.format("%Y-%m-%d %H:%M:%S").to_string()).unwrap_or_default()
                        })
                        .unwrap_or_default();

                    // 使用绝对路径（用于API访问）
                    let absolute_path = file_path.to_string_lossy().to_string();

                    files.push(FileInfo {
                        name: file_name,
                        path: absolute_path,
                        file_type,
                        extension: format!(".{}", extension),
                        size,
                        modified,
                        width: None,   // 稍后可以通过图片库获取
                        height: None,
                        duration: None,
                    });
                }
            }
        }
    }

    // 按修改时间倒序排序（最新的在前面）
    files.sort_by(|a, b| b.modified.cmp(&a.modified));

    Ok(HttpResponse::Ok().json(FilesResponse { files }))
}

/// 统计文件夹中的媒体文件数量
fn count_media_files(path: &Path) -> usize {
    let mut count = 0;

    if let Ok(entries) = fs::read_dir(path) {
        for entry in entries.flatten() {
            if let Ok(metadata) = entry.metadata() {
                if metadata.is_file() {
                    let file_path = entry.path();
                    let extension = file_path
                        .extension()
                        .and_then(|e| e.to_str())
                        .unwrap_or("")
                        .to_lowercase();

                    if extension == GIF_EXTENSION
                        || IMAGE_EXTENSIONS.contains(&extension.as_str())
                        || VIDEO_EXTENSIONS.contains(&extension.as_str()) {
                        count += 1;
                    }
                }
            }
        }
    }

    count
}

/// 获取 ffmpeg 二进制文件路径（从嵌入的二进制中提取）
fn get_ffmpeg_path() -> PathBuf {
    use std::io::Write;

    // 获取临时目录
    let temp_dir = std::env::temp_dir();

    // 根据操作系统设置可执行文件名
    let binary_name = if cfg!(target_os = "windows") {
        "ffmpeg.exe"
    } else {
        "ffmpeg"
    };

    let ffmpeg_path = temp_dir.join(binary_name);

    // 如果文件不存在或者内容不同，则写入
    let needs_write = if ffmpeg_path.exists() {
        // 检查文件大小是否一致
        match fs::metadata(&ffmpeg_path) {
            Ok(metadata) => metadata.len() != FFMPEG_BINARY.len() as u64,
            Err(_) => true,
        }
    } else {
        true
    };

    if needs_write {
        // 写入嵌入的二进制文件
        let mut file = fs::File::create(&ffmpeg_path)
            .expect("无法创建 ffmpeg 临时文件");
        file.write_all(FFMPEG_BINARY)
            .expect("无法写入 ffmpeg 二进制文件");

        // 在 Unix 系统上设置可执行权限
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
    }

    ffmpeg_path
}

/// 从视频提取首帧
fn extract_video_first_frame(video_path: &Path) -> Result<image::DynamicImage> {
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

/// GET /api/gallery/thumbnail?path=<file_path>&size=<size>
/// 生成并返回图片/视频缩略图
async fn get_thumbnail(query: web::Query<std::collections::HashMap<String, String>>) -> Result<HttpResponse> {
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
