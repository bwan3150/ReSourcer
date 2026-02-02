// FFmpeg等工具函数（从gallery/handlers.rs迁移）
use std::path::{Path, PathBuf};
use std::fs;
use actix_web::Result;
use std::process::Command;

// 在编译时嵌入对应平台的 ffmpeg 二进制文件
static FFMPEG_BINARY: &[u8] = include_bytes!(concat!(env!("OUT_DIR"), "/ffmpeg"));

/// 获取 ffmpeg 二进制文件路径（从嵌入的二进制中提取）
pub fn get_ffmpeg_path() -> PathBuf {
    use std::io::Write;

    // 获取临时目录
    let temp_dir = std::env::temp_dir();

    // 根据操作系统设置可执行文件名
    let binary_name = if cfg!(target_os = "windows") {
        "ffmpeg.exe"
    } else {
        "ffmpeg"
    };

    let ffmpeg_path = temp_dir.join(binary_name);

    // 如果文件不存在或者内容不同，则写入
    let needs_write = if ffmpeg_path.exists() {
        // 检查文件大小是否一致
        match fs::metadata(&ffmpeg_path) {
            Ok(metadata) => metadata.len() != FFMPEG_BINARY.len() as u64,
            Err(_) => true,
        }
    } else {
        true
    };

    if needs_write {
        // 写入嵌入的二进制文件
        let mut file = fs::File::create(&ffmpeg_path)
            .expect("无法创建 ffmpeg 临时文件");
        file.write_all(FFMPEG_BINARY)
            .expect("无法写入 ffmpeg 二进制文件");

        // 在 Unix 系统上设置可执行权限
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mut perms = fs::metadata(&ffmpeg_path)
                .expect("无法读取文件元数据")
                .permissions();
            perms.set_mode(0o755);
            fs::set_permissions(&ffmpeg_path, perms)
                .expect("无法设置可执行权限");
        }
    }

    ffmpeg_path
}

/// 从视频提取首帧
pub fn extract_video_first_frame(video_path: &Path) -> Result<image::DynamicImage> {
    // 获取内嵌的 ffmpeg 路径
    let ffmpeg_path = get_ffmpeg_path();

    // 创建临时文件保存首帧
    let temp_output = std::env::temp_dir().join(format!("thumb_{}.jpg", uuid::Uuid::new_v4()));

    // 使用 ffmpeg 提取第一帧
    // -i: 输入文件
    // -vf "select=eq(n\,0)": 选择第一帧
    // -vframes 1: 只输出1帧
    // -q:v 2: 高质量输出
    let output = Command::new(&ffmpeg_path)
        .args(&[
            "-i", video_path.to_str().unwrap(),
            "-vf", "select=eq(n\\,0)",
            "-vframes", "1",
            "-q:v", "2",
            "-y", // 覆盖已存在的文件
            temp_output.to_str().unwrap(),
        ])
        .output()
        .map_err(|e| {
            actix_web::error::ErrorInternalServerError(
                format!("FFmpeg 执行失败 (请确保已安装 ffmpeg): {}", e)
            )
        })?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        // 清理临时文件
        let _ = fs::remove_file(&temp_output);
        return Err(actix_web::error::ErrorInternalServerError(
            format!("FFmpeg 提取首帧失败: {}", stderr)
        ));
    }

    // 读取生成的首帧图片
    let img = image::open(&temp_output)
        .map_err(|e| {
            let _ = fs::remove_file(&temp_output);
            actix_web::error::ErrorInternalServerError(format!("无法读取视频首帧: {}", e))
        })?;

    // 清理临时文件
    let _ = fs::remove_file(&temp_output);

    Ok(img)
}
