// 文件夹操作的工具函数
use std::fs;
use std::path::Path;
use super::models::*;

/// 统计文件夹中的媒体文件数量（Gallery模式）
pub fn count_media_files(path: &Path) -> usize {
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

/// 统计文件夹中的支持文件数量（使用 classifier 的 SUPPORTED_EXTENSIONS）
pub fn count_files_in_folder(folder_path: &Path) -> usize {
    use crate::config_api::storage::SUPPORTED_EXTENSIONS;

    let mut count = 0;

    if let Ok(entries) = fs::read_dir(folder_path) {
        for entry in entries.flatten() {
            if let Ok(metadata) = entry.metadata() {
                if metadata.is_file() {
                    let path = entry.path();
                    if let Some(extension) = path.extension() {
                        if SUPPORTED_EXTENSIONS.contains(&extension.to_str().unwrap_or("")) {
                            count += 1;
                        }
                    }
                }
            }
        }
    }

    count
}
