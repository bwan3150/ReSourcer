// 基础配置管理：只负责主配置文件，不处理平台认证
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;

// 配置数据结构
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConfigData {
    pub source_folder: String,
    pub hidden_folders: Vec<String>,
    #[serde(default = "default_use_cookies")]
    pub use_cookies: bool,
}

fn default_use_cookies() -> bool {
    true
}

// 获取配置目录路径 ~/.config/re-sourcer
pub fn get_config_dir() -> Result<PathBuf, String> {
    let home = std::env::var("HOME")
        .map_err(|_| "无法获取 HOME 环境变量".to_string())?;

    Ok(PathBuf::from(home).join(".config").join("re-sourcer"))
}

// 获取配置文件路径
pub fn get_config_path() -> Result<PathBuf, String> {
    Ok(get_config_dir()?.join("config.json"))
}

// 获取认证文件根目录
pub fn get_credentials_dir() -> Result<PathBuf, String> {
    Ok(get_config_dir()?.join("credentials"))
}

// 确保配置目录存在
pub fn ensure_config_dir() -> Result<(), String> {
    let config_dir = get_config_dir()?;
    if !config_dir.exists() {
        fs::create_dir_all(&config_dir)
            .map_err(|e| format!("无法创建配置目录: {}", e))?;
    }

    let creds_dir = get_credentials_dir()?;
    if !creds_dir.exists() {
        fs::create_dir_all(&creds_dir)
            .map_err(|e| format!("无法创建认证目录: {}", e))?;
    }

    Ok(())
}

// 默认配置
fn get_default_config() -> ConfigData {
    ConfigData {
        source_folder: String::new(),
        hidden_folders: vec![],
        use_cookies: true,
    }
}

// 加载主配置文件
pub fn load_config() -> Result<ConfigData, String> {
    let config_path = get_config_path()?;

    if !config_path.exists() {
        return Ok(get_default_config());
    }

    let content = fs::read_to_string(&config_path)
        .map_err(|e| format!("无法读取配置文件: {}", e))?;

    serde_json::from_str(&content)
        .map_err(|e| format!("配置文件格式错误: {}", e))
}

// 保存主配置文件
pub fn save_config(config: &ConfigData) -> Result<(), String> {
    ensure_config_dir()?;

    let config_path = get_config_path()?;
    let content = serde_json::to_string_pretty(config)
        .map_err(|e| format!("序列化配置失败: {}", e))?;

    fs::write(&config_path, content)
        .map_err(|e| format!("无法写入配置文件: {}", e))?;

    Ok(())
}
