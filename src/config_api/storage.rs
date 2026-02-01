// 配置存储功能 - 从classifier/config.rs迁移的存储相关功能
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
