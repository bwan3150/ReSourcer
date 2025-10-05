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

    // 提取纯 token 值（兼容旧格式带 PHPSESSID= 前缀）
    let token = if content.contains("PHPSESSID=") {
        content.lines()
            .find(|line| line.contains("PHPSESSID="))
            .and_then(|line| line.split("PHPSESSID=").nth(1))
            .map(|s| s.trim().to_string())
            .ok_or_else(|| "无法解析 PHPSESSID".to_string())?
    } else {
        content.trim().to_string()
    };

    Ok(token)
}

// 保存 token
pub fn save_token(token: &str) -> Result<(), String> {
    eprintln!("[Pixiv Auth] 开始保存 token, 内容长度: {} bytes", token.len());
    ensure_dir()?;
    let path = get_token_path()?;
    eprintln!("[Pixiv Auth] 保存路径: {}", path.display());

    // 提取纯 token 值（去掉可能存在的 PHPSESSID= 前缀）
    let clean_token = if token.contains("PHPSESSID=") {
        token.split("PHPSESSID=")
            .nth(1)
            .unwrap_or(token)
            .trim()
    } else {
        token.trim()
    };

    // 只保存纯 token 值，不加前缀
    fs::write(&path, format!("{}\n", clean_token))
        .map_err(|e| format!("无法保存 token: {}", e))?;
    eprintln!("[Pixiv Auth] token 已写入文件");
    Ok(())
}

// 读取刷新令牌
pub fn load_refresh_token() -> Result<String, String> {
    let path = get_refresh_token_path()?;
    fs::read_to_string(&path)
        .map(|s| s.trim().to_string())
        .map_err(|e| format!("无法读取刷新令牌: {}", e))
}

// 保存刷新令牌
pub fn save_refresh_token(token: &str) -> Result<(), String> {
    ensure_dir()?;
    let path = get_refresh_token_path()?;
    fs::write(&path, token.trim())
        .map_err(|e| format!("无法保存刷新令牌: {}", e))?;
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
