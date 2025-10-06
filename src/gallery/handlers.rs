use actix_web::{web, HttpResponse, Result};
use std::path::Path;
use std::fs;
use super::models::*;

/// 支持的图片格式
const IMAGE_EXTENSIONS: &[&str] = &["jpg", "jpeg", "png", "webp", "bmp", "tiff", "svg"];

/// 支持的视频格式
const VIDEO_EXTENSIONS: &[&str] = &["mp4", "mov", "avi", "mkv", "flv", "wmv", "m4v", "webm"];

/// GIF 格式
const GIF_EXTENSION: &str = "gif";

/// 注册所有 Gallery 相关路由
pub fn routes(cfg: &mut web::ServiceConfig) {
    cfg.service(web::resource("/folders").route(web::get().to(get_folders)))
       .service(web::resource("/files").route(web::get().to(get_files)));
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
