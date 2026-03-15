// yt-dlp 下载器实现：支持 YouTube、Bilibili、X、TikTok 等平台
// yt-dlp 二进制存放在 ~/.resourcer/bin/yt-dlp，运行时管理，不再编译时内嵌
use std::path::PathBuf;
use std::process::Stdio;
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::Command;
use super::super::models::Platform;

// 各平台 yt-dlp GitHub releases 下载地址
#[cfg(target_os = "linux")]
const YTDLP_DOWNLOAD_URL: &str =
    "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux";

#[cfg(target_os = "macos")]
const YTDLP_DOWNLOAD_URL: &str =
    "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos";

#[cfg(target_os = "windows")]
const YTDLP_DOWNLOAD_URL: &str =
    "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe";

/// 获取 yt-dlp 安装路径：~/.resourcer/bin/yt-dlp
pub fn get_ytdlp_path() -> PathBuf {
    let home = dirs::home_dir().expect("无法获取 home 目录");
    let binary_name = if cfg!(target_os = "windows") { "yt-dlp.exe" } else { "yt-dlp" };
    home.join(".resourcer").join("bin").join(binary_name)
}

/// 确保 yt-dlp 存在，首次运行时从 GitHub 自动下载
pub async fn ensure_ytdlp() -> Result<PathBuf, String> {
    let path = get_ytdlp_path();
    if path.exists() {
        return Ok(path);
    }

    // 创建目录
    let bin_dir = path.parent().unwrap();
    std::fs::create_dir_all(bin_dir)
        .map_err(|e| format!("无法创建目录 {}: {}", bin_dir.display(), e))?;

    eprintln!("[yt-dlp] 首次运行，正在从 GitHub 下载 yt-dlp...");
    eprintln!("[yt-dlp] URL: {}", YTDLP_DOWNLOAD_URL);

    let response = reqwest::get(YTDLP_DOWNLOAD_URL).await
        .map_err(|e| format!("下载 yt-dlp 失败: {}", e))?;

    if !response.status().is_success() {
        return Err(format!("下载 yt-dlp 失败，HTTP {}", response.status()));
    }

    let bytes = response.bytes().await
        .map_err(|e| format!("读取下载内容失败: {}", e))?;

    std::fs::write(&path, &bytes)
        .map_err(|e| format!("保存 yt-dlp 失败: {}", e))?;

    // Unix 设置可执行权限
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mut perms = std::fs::metadata(&path)
            .map_err(|e| format!("读取文件权限失败: {}", e))?
            .permissions();
        perms.set_mode(0o755);
        std::fs::set_permissions(&path, perms)
            .map_err(|e| format!("设置可执行权限失败: {}", e))?;
    }

    eprintln!("[yt-dlp] 下载完成: {}", path.display());
    Ok(path)
}

/// 获取当前 yt-dlp 版本号
pub async fn get_ytdlp_version() -> Result<String, String> {
    let path = get_ytdlp_path();
    if !path.exists() {
        return Err("yt-dlp 未安装".to_string());
    }

    let output = Command::new(&path)
        .arg("--version")
        .output()
        .await
        .map_err(|e| format!("获取版本失败: {}", e))?;

    Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
}

/// 更新 yt-dlp（调用 yt-dlp -U 原地更新）
/// 返回更新过程的输出信息
pub async fn update_ytdlp() -> Result<String, String> {
    let path = get_ytdlp_path();

    // 不存在则直接下载最新版
    if !path.exists() {
        ensure_ytdlp().await?;
        let version = get_ytdlp_version().await.unwrap_or_default();
        return Ok(format!("yt-dlp 已安装，版本: {}", version));
    }

    let output = Command::new(&path)
        .arg("-U")
        .output()
        .await
        .map_err(|e| format!("运行 yt-dlp -U 失败: {}", e))?;

    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();
    let combined = format!("{}{}", stdout, stderr).trim().to_string();

    Ok(combined)
}

/// 下载视频/音频（核心函数）
///
/// # 参数
/// - url: 视频链接
/// - platform: 平台类型（用于选择认证方式）
/// - output_dir: 输出目录
/// - format: 格式选项 (如 "best", "bestaudio" 等)
/// - progress_callback: 进度回调函数 (progress, speed, eta)
///
/// # 返回
/// - Ok(file_path): 下载成功，返回文件路径
/// - Err(error): 下载失败，返回错误信息
pub async fn download<F>(
    url: String,
    platform: Platform,
    output_dir: String,
    format: Option<String>,
    mut progress_callback: F,
) -> Result<String, String>
where
    F: FnMut(f32, Option<String>, Option<String>) + Send + 'static,
{
    // 确保 yt-dlp 存在（首次运行自动下载）
    let ytdlp_path = ensure_ytdlp().await?;

    // 构建命令
    let mut cmd = Command::new(&ytdlp_path);

    cmd.arg(&url)
       .arg("-o")
       .arg(format!("{}/%(title)s.%(ext)s", output_dir))
       .arg("--newline")       // 每行输出进度信息
       .arg("--progress")      // 强制显示进度条
       .arg("--no-playlist")   // 不下载播放列表
       .arg("--no-update")     // 禁止自动检查更新（由接口管理）
       .arg("--print")
       .arg("after_move:filepath"); // 打印下载完成后的文件路径

    // 格式参数：只在用户明确指定时添加，否则让 yt-dlp 自动选择最佳格式
    if let Some(fmt) = format {
        cmd.arg("-f").arg(fmt);
    }

    // 根据平台添加 cookies（可选，有就用，没有就不加）
    if platform == Platform::X {
        if let Ok(cookies_path) = super::super::auth::x::get_cookies_path() {
            if cookies_path.exists() {
                cmd.arg("--cookies").arg(cookies_path);
            }
        }
    }

    // 设置输出为管道，以便读取进度
    cmd.stdout(Stdio::piped())
       .stderr(Stdio::piped());

    // 启动进程
    let mut child = cmd.spawn()
        .map_err(|e| format!("启动 yt-dlp 失败: {}", e))?;

    // 读取 stdout 和 stderr
    let stdout = child.stdout.take()
        .ok_or("无法获取 stdout")?;
    let stderr = child.stderr.take()
        .ok_or("无法获取 stderr")?;

    let stdout_reader = BufReader::new(stdout);
    let stderr_reader = BufReader::new(stderr);

    // 用于存储最终的文件路径
    let final_filepath = std::sync::Arc::new(tokio::sync::Mutex::new(None::<String>));
    let final_filepath_clone = final_filepath.clone();

    // 异步读取 stdout（进度信息和文件路径）
    let stdout_handle = tokio::spawn(async move {
        let mut lines = stdout_reader.lines();
        while let Ok(Some(line)) = lines.next_line().await {
            let line = line.trim();

            if !line.is_empty() {
                eprintln!("[yt-dlp] {}", line);
            }

            // 如果是文件路径（不包含 [download] 标记且不是空行），则保存
            if !line.contains("[download]") && !line.is_empty() {
                *final_filepath_clone.lock().await = Some(line.to_string());
            } else if let Some((progress, speed, eta)) = parse_progress(line) {
                progress_callback(progress, speed, eta);
            }
        }
    });

    // 异步读取 stderr（错误信息）
    let mut stderr_lines = stderr_reader.lines();
    let mut error_msg = String::new();
    while let Ok(Some(line)) = stderr_lines.next_line().await {
        error_msg.push_str(&line);
        error_msg.push('\n');
    }

    // 等待进程结束
    let status = child.wait().await
        .map_err(|e| format!("等待进程失败: {}", e))?;

    // 等待 stdout 读取完成
    stdout_handle.await
        .map_err(|e| format!("读取 stdout 失败: {}", e))?;

    if status.success() {
        let filepath = final_filepath.lock().await;
        if let Some(path) = filepath.as_ref() {
            Ok(path.clone())
        } else {
            Err("下载成功但无法获取文件路径".to_string())
        }
    } else {
        Err(format!("下载失败: {}", error_msg))
    }
}

/// 解析 yt-dlp 的进度输出
///
/// yt-dlp 输出格式示例：
/// [download]  45.2% of 10.50MiB at 2.30MiB/s ETA 00:02
/// [download] 100% of 10.50MiB in 00:05
fn parse_progress(line: &str) -> Option<(f32, Option<String>, Option<String>)> {
    if !line.contains("[download]") || !line.contains('%') {
        return None;
    }

    let line = line.trim().replace('\r', "");

    let progress = if let Some(percent_pos) = line.find('%') {
        let before_percent = &line[..percent_pos];
        let num_str = before_percent
            .split_whitespace()
            .last()
            .unwrap_or("0");
        num_str.parse::<f32>().unwrap_or(0.0)
    } else {
        return None;
    };

    let speed = if line.contains(" at ") {
        line.split(" at ")
            .nth(1)
            .and_then(|s| s.split_whitespace().next())
            .map(|s| s.to_string())
    } else {
        None
    };

    let eta = if line.contains(" ETA ") {
        line.split(" ETA ")
            .nth(1)
            .and_then(|s| s.split_whitespace().next())
            .map(|s| s.to_string())
    } else if line.contains(" in ") && progress >= 100.0 {
        line.split(" in ")
            .nth(1)
            .and_then(|s| s.split_whitespace().next())
            .map(|s| format!("in {}", s))
    } else {
        None
    };

    Some((progress, speed, eta))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_progress() {
        let line = "[download]  45.2% of 10.50MiB at 2.30MiB/s ETA 00:02";
        let result = parse_progress(line);
        assert!(result.is_some());

        let (progress, speed, eta) = result.unwrap();
        assert_eq!(progress, 45.2);
        assert_eq!(speed, Some("2.30MiB/s".to_string()));
        assert_eq!(eta, Some("00:02".to_string()));
    }

    #[test]
    fn test_parse_progress_no_match() {
        let line = "Some other log message";
        let result = parse_progress(line);
        assert!(result.is_none());
    }
}
