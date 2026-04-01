use std::path::PathBuf;

/// 获取 config 目录路径（可执行文件同级目录下的 config/）
fn config_dir() -> PathBuf {
    // 优先使用可执行文件所在目录
    if let Ok(exe_path) = std::env::current_exe() {
        if let Some(exe_dir) = exe_path.parent() {
            let config_path = exe_dir.join("config");
            if config_path.exists() {
                return config_path;
            }
        }
    }

    // 回退到当前工作目录
    PathBuf::from("config")
}

/// 从 config 目录读取文件内容
pub fn read_config_file(filename: &str) -> Option<Vec<u8>> {
    let path = config_dir().join(filename);
    std::fs::read(&path).ok()
}
