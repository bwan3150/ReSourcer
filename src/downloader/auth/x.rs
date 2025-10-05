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

// 保存 cookies
pub fn save_cookies(content: &str) -> Result<(), String> {
    eprintln!("[X Auth] 开始保存 cookies, 内容长度: {} bytes", content.len());
    ensure_dir()?;
    let path = get_cookies_path()?;
    eprintln!("[X Auth] 保存路径: {}", path.display());
    fs::write(&path, content)
        .map_err(|e| format!("无法保存 cookies: {}", e))?;
    eprintln!("[X Auth] cookies 已写入文件");
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
