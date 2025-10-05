// X (Twitter) 认证管理
use std::fs;
use std::path::PathBuf;

// 获取 X 认证目录
fn get_x_dir() -> Result<PathBuf, String> {
    let creds_dir = super::super::config::get_credentials_dir()?;
    Ok(creds_dir.join("x"))
}

// 获取 cookies 文件路径
pub fn get_cookies_path() -> Result<PathBuf, String> {
    Ok(get_x_dir()?.join("cookies.txt"))
}

// 确保目录存在
fn ensure_dir() -> Result<(), String> {
    let dir = get_x_dir()?;
    if !dir.exists() {
        fs::create_dir_all(&dir)
            .map_err(|e| format!("无法创建 X 目录: {}", e))?;
    }
    Ok(())
}

// 检查是否有 cookies
pub fn has_cookies() -> bool {
    get_cookies_path()
        .map(|path| path.exists())
        .unwrap_or(false)
}

// 读取 cookies 内容
pub fn load_cookies() -> Result<String, String> {
    let path = get_cookies_path()?;
    fs::read_to_string(&path)
        .map_err(|e| format!("无法读取 cookies: {}", e))
}

// 保存 cookies
pub fn save_cookies(content: &str) -> Result<(), String> {
    ensure_dir()?;
    let path = get_cookies_path()?;
    fs::write(&path, content)
        .map_err(|e| format!("无法保存 cookies: {}", e))?;
    Ok(())
}

// 删除 cookies
pub fn delete_cookies() -> Result<(), String> {
    let path = get_cookies_path()?;
    if path.exists() {
        fs::remove_file(&path)
            .map_err(|e| format!("无法删除 cookies: {}", e))?;
    }
    Ok(())
}
