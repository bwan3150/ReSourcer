// yt-dlp 下载器实现：支持 YouTube、Bilibili、X、TikTok 等平台
// yt-dlp 二进制存放在 app_dir()/tools/yt-dlp，运行时管理，不再编译时内嵌
use std::path::PathBuf;
use std::process::Stdio;
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::Command;
use super::super::models::Platform;

/// 获取 yt-dlp 安装路径：app_dir()/tools/yt-dlp
pub fn get_ytdlp_path() -> PathBuf {
    let binary_name = crate::tools::tool_binary_name("yt-dlp");
    crate::static_files::app_dir().join("tools").join(binary_name)
}

/// 确保 yt-dlp 存在，首次运行时从配置的 URL 自动下载
pub async fn ensure_ytdlp() -> Result<PathBuf, String> {
    let path = get_ytdlp_path();
    if path.exists() {
        return Ok(path);
    }

    let download_url = crate::tools::get_tool_download_url("yt-dlp")
        .ok_or("未找到 yt-dlp 下载源配置")?;

    // 创建目录
    let bin_dir = path.parent().unwrap();
    std::fs::create_dir_all(bin_dir)
        .map_err(|e| format!("无法创建目录 {}: {}", bin_dir.display(), e))?;

    eprintln!("[yt-dlp] 首次运行，正在下载 yt-dlp...");
    eprintln!("[yt-dlp] URL: {}", download_url);

    let response = reqwest::get(&download_url).await
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

/// 将 ID 文件名重命名为截断的标题
/// index: 当前文件序号, total: 总文件数（多文件时加序号后缀）
fn rename_to_title(path: &str, title: Option<&str>, index: usize, total: usize) -> String {
    let Some(title) = title else { return path.to_string() };
    let src = std::path::Path::new(path);
    if !src.exists() { return path.to_string() }

    let ext = src.extension().and_then(|e| e.to_str()).unwrap_or("mp4");
    let safe_title: String = title.chars()
        .filter(|c| !['/', '\\', ':', '*', '?', '"', '<', '>', '|', '\0'].contains(c))
        .take(60)
        .collect();
    let safe_title = safe_title.trim().trim_end_matches('.');
    if safe_title.is_empty() { return path.to_string() }

    // 多文件时加序号: title(1).mp4, title(2).mp4
    let new_name = if total > 1 {
        format!("{}({}).{}", safe_title, index + 1, ext)
    } else {
        format!("{}.{}", safe_title, ext)
    };

    let new_path = src.parent().unwrap_or(src).join(&new_name);
    if !new_path.exists() {
        if let Ok(()) = std::fs::rename(src, &new_path) {
            eprintln!("[yt-dlp] renamed: {} → {}", path, new_path.display());
            return new_path.to_string_lossy().to_string();
        }
    }
    path.to_string()
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
    file_uuid: Option<String>,
    mut progress_callback: F,
) -> Result<String, String>
where
    F: FnMut(f32, Option<String>, Option<String>) + Send + 'static,
{
    // 确保 yt-dlp 存在（首次运行自动下载）
    let ytdlp_path = ensure_ytdlp().await?;

    // 构建命令
    let mut cmd = Command::new(&ytdlp_path);

    // 获取 ffmpeg 路径，告知 yt-dlp 合并音视频流（Bilibili 等 DASH 格式必须）
    let ffmpeg_path = crate::preview::utils::get_ffmpeg_path();

    // 文件名策略：UUID_平台_平台ID.ext（下载安全 + 可追溯）
    let platform_prefix = match platform {
        Platform::YouTube => "youtube",
        Platform::Bilibili => "bilibili",
        Platform::X => "x",
        Platform::TikTok => "tiktok",
        Platform::Pixiv => "pixiv",
        Platform::Xiaohongshu => "xiaohongshu",
        Platform::Unknown => "unknown",
    };
    let output_template = if let Some(ref uuid) = file_uuid {
        format!("{}/{}_{}_{}.%(ext)s", output_dir, uuid, platform_prefix, "%(id)s")
    } else {
        format!("{}/{}_%(id)s.%(ext)s", output_dir, platform_prefix)
    };
    cmd.arg(&url)
       .arg("-o")
       .arg(&output_template)
       .arg("--newline")       // 每行输出进度信息
       .arg("--progress")      // 强制显示进度条
       .arg("--no-playlist")   // 不下载播放列表
       .arg("--no-update")     // 禁止自动检查更新（由接口管理）
       .arg("--ffmpeg-location").arg(&ffmpeg_path) // 指定 ffmpeg 路径，用于合并音视频
       .arg("--print").arg("after_move:filepath")  // 打印下载完成后的文件路径
       .arg("--print").arg("after_move:title");   // 打印视频标题（用于重命名）

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

    // 存储 yt-dlp 的 --print 输出（filepath 和 title 交替输出）
    let print_outputs = std::sync::Arc::new(tokio::sync::Mutex::new(Vec::<String>::new()));
    let print_outputs_clone = print_outputs.clone();

    // 异步读取 stdout（进度信息和 --print 输出）
    let stdout_handle = tokio::spawn(async move {
        let mut lines = stdout_reader.lines();
        while let Ok(Some(line)) = lines.next_line().await {
            let line = line.trim();

            if !line.is_empty() {
                eprintln!("[yt-dlp] {}", line);
            }

            if let Some((progress, speed, eta)) = parse_progress(line) {
                progress_callback(progress, speed, eta);
            } else if !line.is_empty() && !line.contains('[') {
                // --print outputs: lines without [] brackets
                print_outputs_clone.lock().await.push(line.to_string());
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
        let outputs = print_outputs.lock().await;
        // --print outputs: filepath and title alternate for each file
        // [filepath1, title1, filepath2, title2, ...]
        let pairs: Vec<(String, Option<String>)> = outputs.chunks(2)
            .map(|chunk| (chunk[0].clone(), chunk.get(1).cloned()))
            .collect();

        if pairs.is_empty() {
            return Err("下载成功但无法获取文件路径".to_string());
        }

        // Rename all files from ID-based to truncated title
        let mut first_result: Option<String> = None;
        for (i, (path, title)) in pairs.iter().enumerate() {
            let renamed = rename_to_title(path, title.as_deref(), i, pairs.len());
            if first_result.is_none() {
                first_result = Some(renamed);
            }
        }

        Ok(first_result.unwrap())
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
