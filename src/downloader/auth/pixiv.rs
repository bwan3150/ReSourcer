// Pixiv 认证管理
use std::fs;
use std::path::PathBuf;

// 获取 Pixiv 认证目录
fn get_pixiv_dir() -> Result<PathBuf, String> {
    let creds_dir = super::super::config::get_credentials_dir()?;
    Ok(creds_dir.join("pixiv"))
}

// 获取 token 文件路径
pub fn get_token_path() -> Result<PathBuf, String> {
    Ok(get_pixiv_dir()?.join("token.txt"))
}

// 获取刷新令牌文件路径
pub fn get_refresh_token_path() -> Result<PathBuf, String> {
    Ok(get_pixiv_dir()?.join("refresh_token.txt"))
}

// 确保目录存在
fn ensure_dir() -> Result<(), String> {
    let dir = get_pixiv_dir()?;
    if !dir.exists() {
        fs::create_dir_all(&dir)
            .map_err(|e| format!("无法创建 Pixiv 目录: {}", e))?;
    }
    Ok(())
}

// 检查是否有 token
pub fn has_token() -> bool {
    get_token_path()
        .map(|path| path.exists())
        .unwrap_or(false)
}

// 读取 PHPSESSID token
pub fn load_token() -> Result<String, String> {
    let path = get_token_path()?;
    let content = fs::read_to_string(&path)
        .map_err(|e| format!("无法读取 token: {}", e))?;

    // 直接返回用户保存的原始内容
    Ok(content.trim().to_string())
}

// 保存 token
pub fn save_token(token: &str) -> Result<(), String> {
    eprintln!("[Pixiv Auth] 开始保存 token, 内容长度: {} bytes", token.len());
    ensure_dir()?;
    let path = get_token_path()?;
    eprintln!("[Pixiv Auth] 保存路径: {}", path.display());

    // 直接保存用户输入的原始内容，不做任何处理
    fs::write(&path, token.trim())
        .map_err(|e| format!("无法保存 token: {}", e))?;
    eprintln!("[Pixiv Auth] token 已写入文件");
    Ok(())
}

// 删除所有认证信息
pub fn delete_all() -> Result<(), String> {
    let token_path = get_token_path()?;
    let refresh_path = get_refresh_token_path()?;

    if token_path.exists() {
        fs::remove_file(&token_path)
            .map_err(|e| format!("无法删除 token: {}", e))?;
    }

    if refresh_path.exists() {
        fs::remove_file(&refresh_path)
            .map_err(|e| format!("无法删除刷新令牌: {}", e))?;
    }

    Ok(())
}
