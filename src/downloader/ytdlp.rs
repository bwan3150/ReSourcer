use std::path::PathBuf;
use std::process::Command;

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
pub fn check_ytdlp_available() -> bool {
    let path = get_ytdlp_path();
    path.exists()
}

/// 获取 yt-dlp 版本信息
pub fn get_version() -> Result<String, String> {
    let ytdlp_path = get_ytdlp_path();

    if !ytdlp_path.exists() {
        return Err(format!("yt-dlp 不存在: {}", ytdlp_path.display()));
    }

    let output = Command::new(&ytdlp_path)
        .arg("--version")
        .output()
        .map_err(|e| format!("执行失败: {}", e))?;

    if output.status.success() {
        Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
    } else {
        Err(String::from_utf8_lossy(&output.stderr).to_string())
    }
}

/// 下载视频/音频
///
/// # 参数
/// - url: 视频链接
/// - output_path: 保存路径
/// - format: 格式选项 (如 "best", "bestaudio", 等)
pub async fn download(
    url: &str,
    output_path: &str,
    format: Option<&str>
) -> Result<(), String> {
    let ytdlp_path = get_ytdlp_path();

    if !ytdlp_path.exists() {
        return Err(format!("yt-dlp 不存在: {}", ytdlp_path.display()));
    }

    let mut cmd = Command::new(&ytdlp_path);
    cmd.arg(url)
       .arg("-o")
       .arg(output_path);

    // 添加格式参数
    if let Some(fmt) = format {
        cmd.arg("-f").arg(fmt);
    }

    // TODO: 实现异步执行和进度监控
    // 当前是同步执行，后续可以改为异步 + 进度回调

    let output = cmd.output()
        .map_err(|e| format!("执行失败: {}", e))?;

    if output.status.success() {
        Ok(())
    } else {
        Err(String::from_utf8_lossy(&output.stderr).to_string())
    }
}
