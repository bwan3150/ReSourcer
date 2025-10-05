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
        source_folder: String::new(),
        hidden_folders: Vec::new(),
    }
}

// 加载预设列表 - 从项目目录的 config/presets.json 读取
pub fn load_presets() -> io::Result<Vec<Preset>> {
    // 获取可执行文件所在目录
    let exe_path = std::env::current_exe()
        .map_err(|e| io::Error::new(io::ErrorKind::NotFound, e))?;
    let exe_dir = exe_path.parent()
        .ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "无法获取可执行文件目录"))?;

    // 尝试从多个可能的位置读取预设文件
    let possible_paths = vec![
        exe_dir.join("config").join("presets.json"),           // 打包后的位置
        exe_dir.join("../config/presets.json"),                // 开发环境
        PathBuf::from("config/presets.json"),                   // 当前目录
        PathBuf::from("./config/presets.json"),                 // 显式当前目录
    ];

    for presets_path in possible_paths {
        if presets_path.exists() {
            let content = fs::read_to_string(&presets_path)?;
            let presets: Vec<Preset> = serde_json::from_str(&content)
                .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
            return Ok(presets);
        }
    }

    // 如果找不到文件，返回空列表
    Ok(Vec::new())
}

pub const SUPPORTED_EXTENSIONS: &[&str] = &[
    "png", "jpg", "jpeg", "webp", "gif", "bmp",
    "PNG", "JPG", "JPEG", "WEBP", "GIF", "BMP",
    "mp4", "mov", "avi", "mkv", "webm",
    "MP4", "MOV", "AVI", "MKV", "WEBM",
    "heic", "HEIC", "heif", "HEIF"
];