// yt-dlp 下载器实现：支持 YouTube、Bilibili、X、TikTok 等平台
use std::path::PathBuf;
use std::process::Stdio;
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::Command;
use super::super::models::Platform;

// 在编译时嵌入对应平台的 yt-dlp 二进制文件
static YTDLP_BINARY: &[u8] = include_bytes!(concat!(env!("OUT_DIR"), "/yt-dlp"));

/// 获取 yt-dlp 二进制文件路径（从嵌入的二进制中提取）
pub fn get_ytdlp_path() -> PathBuf {
    use std::fs;
    use std::io::Write;

    // 获取临时目录
    let temp_dir = std::env::temp_dir();

    // 根据操作系统设置可执行文件名
    let binary_name = if cfg!(target_os = "windows") {
        "yt-dlp.exe"
    } else {
        "yt-dlp"
    };

    let ytdlp_path = temp_dir.join(binary_name);

    // 如果文件不存在或者内容不同，则写入
    let needs_write = if ytdlp_path.exists() {
        // 检查文件大小是否一致
        match fs::metadata(&ytdlp_path) {
            Ok(metadata) => metadata.len() != YTDLP_BINARY.len() as u64,
            Err(_) => true,
        }
    } else {
        true
    };

    if needs_write {
        // 写入嵌入的二进制文件
        let mut file = fs::File::create(&ytdlp_path)
            .expect("无法创建 yt-dlp 临时文件");
        file.write_all(YTDLP_BINARY)
            .expect("无法写入 yt-dlp 二进制文件");

        // 在 Unix 系统上设置可执行权限
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mut perms = fs::metadata(&ytdlp_path)
                .expect("无法读取文件元数据")
                .permissions();
            perms.set_mode(0o755);
            fs::set_permissions(&ytdlp_path, perms)
                .expect("无法设置可执行权限");
        }
    }

    ytdlp_path
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
       .arg("--progress") // 强制显示进度条
       .arg("--no-playlist") // 不下载播放列表
       .arg("--print")
       .arg("after_move:filepath"); // 打印下载完成后的文件路径

    // 格式参数：只在用户明确指定时添加，否则让 yt-dlp 自动选择最佳格式
    // 这样可以避免 bilibili 等平台不支持 "best" 预合并格式的问题
    if let Some(fmt) = format {
        cmd.arg("-f").arg(fmt);
    }
    // 不再设置默认的 "-f best"，让 yt-dlp 自动下载并合并最佳可用格式

    // 根据平台添加 cookies（可选，有就用，没有就不加）
    if platform == Platform::X {
        if let Ok(cookies_path) = super::super::auth::x::get_cookies_path() {
            if cookies_path.exists() {
                cmd.arg("--cookies").arg(cookies_path);
            }
            // 如果没有 cookies，不报错，让 yt-dlp 自己尝试下载
        }
    }

    // Pixiv 平台的 token（如果需要的话）
    if platform == Platform::Pixiv {
        if let Ok(token_path) = super::super::auth::pixiv::get_token_path() {
            if token_path.exists() {
                // Pixiv 可能需要特殊参数，这里暂时跳过
                // 如果 yt-dlp 需要 token，可以在这里添加
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

            // 调试输出
            if !line.is_empty() {
                eprintln!("[yt-dlp] {}", line);
            }

            // 如果是文件路径（不包含 [download] 标记且不是空行），则保存
            if !line.contains("[download]") && !line.is_empty() {
                *final_filepath_clone.lock().await = Some(line.to_string());
            }
            // 解析进度信息
            else if let Some((progress, speed, eta)) = parse_progress(line) {
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
/// [download] 100% of 10.50MiB in 00:05
///
/// # 返回
/// - Some((progress, speed, eta))
/// - None 如果无法解析
fn parse_progress(line: &str) -> Option<(f32, Option<String>, Option<String>)> {
    // 只处理包含 [download] 的行
    if !line.contains("[download]") {
        return None;
    }

    // 跳过非进度行（如 "Destination: xxx"）
    if !line.contains('%') {
        return None;
    }

    // 清理行内容（移除可能的回车符和多余空格）
    let line = line.trim().replace('\r', "");

    // 提取百分比 - 改进的解析逻辑
    let progress = if let Some(percent_pos) = line.find('%') {
        // 向前查找数字
        let before_percent = &line[..percent_pos];
        let num_str = before_percent
            .split_whitespace()
            .last()
            .unwrap_or("0");

        num_str.parse::<f32>().unwrap_or(0.0)
    } else {
        return None;
    };

    // 提取速度（at 后面的值）
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
    } else if line.contains(" in ") && progress >= 100.0 {
        // 如果是 "100% of X in 00:05" 格式
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
