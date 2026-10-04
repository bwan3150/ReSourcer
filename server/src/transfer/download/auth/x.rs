// X (Twitter) 认证管理
use std::fs;
use std::path::PathBuf;

// 获取 X 认证目录
fn get_x_dir() -> Result<PathBuf, String> {
    let creds_dir = crate::transfer::download::storage::get_credentials_dir()?;
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

// 判断是否已经是 Netscape cookie 文件（yt-dlp --cookies 要求的格式）
// 该格式每条记录是一行、7 个字段、用制表符分隔
fn is_netscape_format(content: &str) -> bool {
    content.lines()
        .filter(|l| !l.trim().is_empty() && !l.trim_start().starts_with('#'))
        .any(|l| l.split('\t').count() >= 7)
}

// 从用户粘贴的文本里取出某个 cookie 的值
// 容忍三种写法：`auth_token=abc`、`auth_token: abc`、以及独占一行的裸值
fn extract_cookie_value(content: &str, name: &str) -> Option<String> {
    for raw in content.split(|c| c == ';' || c == '\n' || c == '\r') {
        let part = raw.trim();
        if let Some(rest) = part.strip_prefix(name) {
            let rest = rest.trim_start();
            if let Some(v) = rest.strip_prefix('=').or_else(|| rest.strip_prefix(':')) {
                let v = v.trim().trim_matches('"');
                if !v.is_empty() {
                    return Some(v.to_string());
                }
            }
        }
    }
    None
}

// 用 auth_token / ct0 拼出最小可用的 Netscape cookie 文件
// 过期时间给一个远期值；真实失效由 X 服务端判定，写在这里只是占位
fn build_netscape(auth_token: &str, ct0: &str) -> String {
    let expires = "2147483647";
    let mut out = String::from("# Netscape HTTP Cookie File\n");
    for (name, value) in [("auth_token", auth_token), ("ct0", ct0)] {
        out.push_str(&format!(
            "#HttpOnly_.x.com\tTRUE\t/\tTRUE\t{}\t{}\t{}\n",
            expires, name, value
        ));
    }
    out
}

// 保存 cookies
// 既接受完整的 Netscape cookies.txt（浏览器扩展导出的），
// 也接受只填了 auth_token / ct0 两个值的情况——后者在网页输入框里打不出制表符，
// 所以由服务端补齐格式
pub fn save_cookies(content: &str) -> Result<(), String> {
    eprintln!("[X Auth] 开始保存 cookies, 内容长度: {} bytes", content.len());
    ensure_dir()?;
    let path = get_cookies_path()?;

    let to_write = if is_netscape_format(content) {
        eprintln!("[X Auth] 识别为 Netscape cookie 文件，原样保存");
        content.to_string()
    } else {
        let auth_token = extract_cookie_value(content, "auth_token")
            .ok_or("未找到 auth_token，请粘贴浏览器导出的 cookies.txt，或分别填入 auth_token 和 ct0")?;
        let ct0 = extract_cookie_value(content, "ct0")
            .ok_or("未找到 ct0，X 的接口要求 auth_token 和 ct0 同时存在")?;
        eprintln!("[X Auth] 由 auth_token / ct0 拼出 Netscape cookie 文件");
        build_netscape(&auth_token, &ct0)
    };

    eprintln!("[X Auth] 保存路径: {}", path.display());
    fs::write(&path, &to_write)
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
