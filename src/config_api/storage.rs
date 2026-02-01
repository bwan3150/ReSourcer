// 配置存储功能 - 从classifier/config.rs迁移的存储相关功能
use super::models::{AppState, Preset, CategoryOrderConfig};
use std::path::PathBuf;
use std::fs;
use std::io;

/// 获取配置文件目录 ~/.config/re-sourcer/
pub fn get_config_dir() -> PathBuf {
    let home = std::env::var("HOME")
        .or_else(|_| std::env::var("USERPROFILE"))
        .unwrap_or_else(|_| ".".to_string());

    PathBuf::from(home).join(".config").join("re-sourcer")
}

/// 获取配置文件路径
pub fn get_config_path() -> PathBuf {
    get_config_dir().join("config.json")
}

/// 确保配置目录存在
pub fn ensure_config_dir() -> io::Result<()> {
    let config_dir = get_config_dir();
    if !config_dir.exists() {
        fs::create_dir_all(&config_dir)?;
    }
    Ok(())
}

/// 读取配置
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

/// 保存配置
pub fn save_config(state: &AppState) -> io::Result<()> {
    ensure_config_dir()?;
    let config_path = get_config_path();
    let content = serde_json::to_string_pretty(state)
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
    fs::write(config_path, content)?;
    Ok(())
}

/// 默认应用状态 - 不设置默认文件夹，由用户在设置页面指定
pub fn get_default_state() -> AppState {
    AppState {
        source_folder: String::new(),
        hidden_folders: Vec::new(),
        backup_source_folders: Vec::new(),
    }
}

/// 加载分类排序配置
pub fn load_category_order_config() -> io::Result<CategoryOrderConfig> {
    let config_path = get_config_dir().join("category_order.json");

    if !config_path.exists() {
        return Ok(CategoryOrderConfig::default());
    }

    let content = fs::read_to_string(&config_path)?;
    let config = serde_json::from_str(&content)?;
    Ok(config)
}

/// 保存分类排序配置
pub fn save_category_order_config(config: &CategoryOrderConfig) -> io::Result<()> {
    let config_dir = get_config_dir();
    fs::create_dir_all(&config_dir)?;

    let config_path = config_dir.join("category_order.json");
    let content = serde_json::to_string_pretty(config)?;
    fs::write(config_path, content)?;
    Ok(())
}

/// 获取指定源文件夹的分类排序
pub fn get_category_order(source_folder: &str) -> Vec<String> {
    load_category_order_config()
        .ok()
        .and_then(|config| config.orders.get(source_folder).cloned())
        .unwrap_or_default()
}

/// 保存指定源文件夹的分类排序
pub fn set_category_order(source_folder: &str, order: Vec<String>) -> io::Result<()> {
    let mut config = load_category_order_config().unwrap_or_default();
    config.orders.insert(source_folder.to_string(), order);
    save_category_order_config(&config)
}

/// 加载预设列表 - 从嵌入的 config/presets.json 读取
pub fn load_presets() -> io::Result<Vec<Preset>> {
    use crate::static_files::ConfigAsset;

    // 从嵌入的资源读取预设文件
    if let Some(config_file) = ConfigAsset::get("presets.json") {
        let presets: Vec<Preset> = serde_json::from_slice(&config_file.data)
            .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
        return Ok(presets);
    }

    // 如果找不到嵌入的文件，返回空列表
    Ok(Vec::new())
}
