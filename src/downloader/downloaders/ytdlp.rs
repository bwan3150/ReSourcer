// yt-dlp 下载器实现：支持 YouTube、Bilibili、X、TikTok 等平台
use std::path::PathBuf;
use std::process::Stdio;
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::Command;
use super::super::models::Platform;

/// 根据当前操作系统获取 yt-dlp 二进制文件路径
pub fn get_ytdlp_path() -> PathBuf {
    let binary_name = if cfg!(target_os = "macos") {
        "yt-dlp-macos"
    } else if cfg!(target_os = "windows") {
        "yt-dlp-windows.exe"
    } else if cfg!(target_os = "linux") {
        "yt-dlp-linux"
    } else {
        panic!("不支持的操作系统");
    };

    PathBuf::from("bin").join(binary_name)
}

/// 检查 yt-dlp 是否可用
pub fn check_available() -> bool {
    let path = get_ytdlp_path();
    path.exists()
}

/// 获取 yt-dlp 版本信息
pub fn get_version() -> Result<String, String> {
    let ytdlp_path = get_ytdlp_path();

    if !ytdlp_path.exists() {
        return Err(format!("yt-dlp 不存在: {}", ytdlp_path.display()));
    }

    let output = std::process::Command::new(&ytdlp_path)
        .arg("--version")
        .output()
        .map_err(|e| format!("执行失败: {}", e))?;

    if output.status.success() {
        Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
    } else {
        Err(String::from_utf8_lossy(&output.stderr).to_string())
    }
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
    let ytdlp_path = get_ytdlp_path();

    if !ytdlp_path.exists() {
        return Err(format!("yt-dlp 不存在: {}", ytdlp_path.display()));
    }

    // 构建命令
    let mut cmd = Command::new(&ytdlp_path);

    // 基础参数
    cmd.arg(&url)
       .arg("-o")
       .arg(format!("{}/%(title)s.%(ext)s", output_dir))
       .arg("--newline") // 每行输出进度信息
       .arg("--no-playlist") // 不下载播放列表
       .arg("--print")
       .arg("after_move:filepath"); // 打印下载完成后的文件路径

    // 格式参数
    if let Some(fmt) = format {
        cmd.arg("-f").arg(fmt);
    } else {
        cmd.arg("-f").arg("best"); // 默认最佳质量
    }

    // 根据平台添加 cookies（仅 X 需要）
    if platform == Platform::X {
        if let Ok(cookies_path) = super::super::auth::x::get_cookies_path() {
            if cookies_path.exists() {
                cmd.arg("--cookies").arg(cookies_path);
            } else {
                return Err("X 平台需要 cookies，但 cookies 文件不存在".to_string());
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
            // 如果是文件路径（不包含 [download] 标记），则保存
            if !line.contains("[download]") && !line.trim().is_empty() {
                *final_filepath_clone.lock().await = Some(line.trim().to_string());
            }
            // 解析进度信息
            else if let Some((progress, speed, eta)) = parse_progress(&line) {
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
        // 成功：返回实际的文件路径
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
///
/// # 返回
/// - Some((progress, speed, eta))
/// - None 如果无法解析
fn parse_progress(line: &str) -> Option<(f32, Option<String>, Option<String>)> {
    if !line.contains("[download]") {
        return None;
    }

    // 提取百分比
    let progress = if let Some(percent_str) = line.split('%').next() {
        if let Some(num_str) = percent_str.split_whitespace().last() {
            num_str.parse::<f32>().ok()?
        } else {
            return None;
        }
    } else {
        return None;
    };

    // 提取速度
    let speed = if line.contains(" at ") {
        line.split(" at ")
            .nth(1)
            .and_then(|s| s.split_whitespace().next())
            .map(|s| s.to_string())
    } else {
        None
    };

    // 提取 ETA
    let eta = if line.contains(" ETA ") {
        line.split(" ETA ")
            .nth(1)
            .and_then(|s| s.split_whitespace().next())
            .map(|s| s.to_string())
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
