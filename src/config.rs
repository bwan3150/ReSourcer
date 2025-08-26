use std::env;
use crate::models::{AppState, Preset};

// 默认应用状态 - 使用当前目录作为默认源文件夹
pub fn get_default_state() -> AppState {
    // 获取当前工作目录
    let current_dir = env::current_dir()
        .map(|p| p.to_string_lossy().to_string())
        .unwrap_or_else(|_| String::new());
    
    AppState {
        source_folder: current_dir,
        current_preset: "Art Resources".to_string(),
        presets: vec![
            Preset {
                name: "Art Resources".to_string(),
                categories: vec![
                    "Character Design".to_string(),
                    "Backgrounds".to_string(),
                    "Color Reference".to_string(),
                    "Composition".to_string(),
                    "Anatomy".to_string(),
                    "Lighting".to_string(),
                ],
            },
            Preset {
                name: "Photography".to_string(),
                categories: vec![
                    "Portraits".to_string(),
                    "Landscapes".to_string(),
                    "Street".to_string(),
                    "Architecture".to_string(),
                    "Nature".to_string(),
                    "Black & White".to_string(),
                ],
            },
            Preset {
                name: "Design Assets".to_string(),
                categories: vec![
                    "UI/UX".to_string(),
                    "Icons".to_string(),
                    "Patterns".to_string(),
                    "Textures".to_string(),
                    "Mockups".to_string(),
                    "Fonts".to_string(),
                ],
            },
        ],
    }
}

pub const SUPPORTED_EXTENSIONS: &[&str] = &[
    "png", "jpg", "jpeg", "webp", "gif", "bmp",
    "PNG", "JPG", "JPEG", "WEBP", "GIF", "BMP",
    "mp4", "mov", "avi", "mkv", "webm",
    "MP4", "MOV", "AVI", "MKV", "WEBM",
    "heic", "HEIC", "heif", "HEIF"
];