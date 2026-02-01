// 文件列表功能（从gallery/handlers.rs迁移）
use actix_web::{web, HttpResponse, Result};
use std::path::Path;
use std::fs;
use super::models::*;

/// GET /api/preview/files?folder=<path>
/// 获取指定文件夹的所有媒体文件
pub async fn get_files(query: web::Query<std::collections::HashMap<String, String>>) -> Result<HttpResponse> {
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
