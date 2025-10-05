use super::models::{AppState, Preset};
use std::path::PathBuf;
use std::fs;
use std::io;

// 获取配置文件目录 ~/.config/re-sourcer/
pub fn get_config_dir() -> PathBuf {
    let home = std::env::var("HOME")
        .or_else(|_| std::env::var("USERPROFILE"))
        .unwrap_or_else(|_| ".".to_string());

    PathBuf::from(home).join(".config").join("re-sourcer")
}

// 获取配置文件路径
pub fn get_config_path() -> PathBuf {
    get_config_dir().join("config.json")
}

// 确保配置目录存在
pub fn ensure_config_dir() -> io::Result<()> {
    let config_dir = get_config_dir();
    if !config_dir.exists() {
        fs::create_dir_all(&config_dir)?;
    }
    Ok(())
}

// 读取配置
pub fn load_config() -> io::Result<AppState> {
    let config_path = get_config_path();

    if !config_path.exists() {
        return Ok(get_default_state());
    }

    let content = fs::read_to_string(config_path)?;
    let state: AppState = serde_json::from_str(&content)
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;

    Ok(state)
}

// 保存配置
pub fn save_config(state: &AppState) -> io::Result<()> {
    ensure_config_dir()?;
    let config_path = get_config_path();
    let content = serde_json::to_string_pretty(state)
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
    fs::write(config_path, content)?;
    Ok(())
}

// 默认应用状态 - 不设置默认文件夹，由用户在设置页面指定
pub fn get_default_state() -> AppState {
    AppState {
        source_folder: String::new(), // 不再自动填充
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