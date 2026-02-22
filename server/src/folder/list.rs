// 文件夹列表功能
use actix_web::{web, HttpResponse, Result};
use std::fs;
use std::path::Path;
use super::models::*;
use super::utils::*;

/// GET /api/folder/list
/// 获取文件夹列表 - 整合了 gallery/folders, classifier/folders, downloader/folders, settings/folders
pub async fn list_folders(query: web::Query<std::collections::HashMap<String, String>>) -> Result<HttpResponse> {
    // 判断是要获取 gallery 的文件夹列表还是 classifier 的文件夹列表
    // 如果有 source_folder 参数，则返回该源文件夹下的子文件夹列表
    // 如果没有参数，则返回 gallery 样式的文件夹列表（源文件夹 + 分类文件夹）

    if let Some(source_folder) = query.get("source_folder") {
        // 返回指定源文件夹下的子文件夹列表（classifier/settings/downloader 模式）
        return get_subfolders(source_folder);
    } else {
        // 返回 gallery 模式的文件夹列表
        return get_gallery_folders();
    }
}

/// 获取 gallery 样式的文件夹列表（源文件夹 + 分类文件夹）
fn get_gallery_folders() -> Result<HttpResponse> {
    let config = crate::config_api::storage::load_config()
        .map_err(|e| actix_web::error::ErrorInternalServerError(format!("无法加载配置: {}", e)))?;

    let mut folders = Vec::new();

    // 1. 添加源文件夹
    if let Ok(source_path) = fs::canonicalize(&config.source_folder) {
        if source_path.exists() && source_path.is_dir() {
            let file_count = count_media_files(&source_path);
            folders.push(GalleryFolderInfo {
                name: "源文件夹".to_string(),
                path: config.source_folder.clone(),
                is_source: true,
                file_count,
            });
        }
    }

    // 2. 添加分类文件夹（排除隐藏文件夹和忽略文件夹）
    if let Ok(entries) = fs::read_dir(&config.source_folder) {
        for entry in entries.flatten() {
            if let Ok(metadata) = entry.metadata() {
                if metadata.is_dir() {
                    let folder_name = entry.file_name().to_string_lossy().to_string();

                    // 跳过隐藏文件夹
                    if config.hidden_folders.contains(&folder_name) {
                        continue;
                    }

                    // 跳过忽略文件夹（NAS 系统文件夹等）
                    if config.ignored_folders.contains(&folder_name) {
                        continue;
                    }

                    let folder_path = entry.path();
                    let file_count = count_media_files(&folder_path);

                    folders.push(GalleryFolderInfo {
                        name: folder_name.clone(),
                        path: folder_path.to_string_lossy().to_string(),
                        is_source: false,
                        file_count,
                    });
                }
            }
        }
    }

    Ok(HttpResponse::Ok().json(GalleryFoldersResponse { folders }))
}

/// 获取指定源文件夹下的子文件夹列表
fn get_subfolders(source_folder: &str) -> Result<HttpResponse> {
    let source_path = Path::new(source_folder);

    if !source_path.exists() || !source_path.is_dir() {
        return Ok(HttpResponse::Ok().json(Vec::<FolderInfo>::new()));
    }

    // 加载配置以获取隐藏文件夹列表
    let state = crate::config_api::storage::load_config()
        .unwrap_or_else(|_| crate::config_api::storage::get_default_state());

    let mut folders = Vec::new();

    if let Ok(entries) = fs::read_dir(source_path) {
        for entry in entries.flatten() {
            if let Ok(metadata) = entry.metadata() {
                if metadata.is_dir() {
                    let folder_name = entry.file_name().to_string_lossy().to_string();
                    // 跳过隐藏文件夹（以.开头的）和忽略文件夹
                    if !folder_name.starts_with('.')
                        && !state.ignored_folders.contains(&folder_name)
                    {
                        let hidden = state.hidden_folders.contains(&folder_name);

                        // 统计文件夹中的文件数量
                        let folder_path = entry.path();
                        let file_count = count_files_in_folder(&folder_path);

                        folders.push(FolderInfo {
                            name: folder_name,
                            hidden,
                            file_count,
                        });
                    }
                }
            }
        }
    }

    // 按照保存的顺序排序（支持任意层级文件夹路径），没有则按名称排序
    let subfolder_order = crate::config_api::storage::get_subfolder_order(source_folder);
    if !subfolder_order.is_empty() {
        folders.sort_by(|a, b| {
            let pos_a = subfolder_order.iter().position(|x| x == &a.name);
            let pos_b = subfolder_order.iter().position(|x| x == &b.name);

            match (pos_a, pos_b) {
                (Some(pa), Some(pb)) => pa.cmp(&pb),
                (Some(_), None) => std::cmp::Ordering::Less,
                (None, Some(_)) => std::cmp::Ordering::Greater,
                (None, None) => a.name.cmp(&b.name),
            }
        });
    } else {
        folders.sort_by(|a, b| a.name.cmp(&b.name));
    }

    Ok(HttpResponse::Ok().json(folders))
}
