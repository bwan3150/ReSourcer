use std::path::PathBuf;

/// 获取应用根目录
///
/// 解析逻辑（按优先级）：
/// 1. 环境变量 RESOURCER_DIR（开发时手动指定）
/// 2. 可执行文件同级有 config/ → 使用该目录（部署模式）
/// 3. 回退到当前工作目录
pub fn app_dir() -> PathBuf {
    // 环境变量优先（开发模式）
    if let Ok(dir) = std::env::var("RESOURCER_DIR") {
        return PathBuf::from(dir);
    }
    // 部署模式：exe 同级有 config/
    if let Ok(exe_path) = std::env::current_exe() {
        if let Some(exe_dir) = exe_path.parent() {
            if exe_dir.join("config").exists() {
                return exe_dir.to_path_buf();
            }
        }
    }
    // 回退到当前工作目录
    std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."))
}

/// 从 config 目录读取文件内容
pub fn read_config_file(filename: &str) -> Option<Vec<u8>> {
    let path = app_dir().join("config").join(filename);
    std::fs::read(&path).ok()
}
