use std::env;
use std::fs;
use std::path::Path;

fn main() {
    let target_os = env::var("CARGO_CFG_TARGET_OS").unwrap();

    // ffmpeg 二进制文件
    let ffmpeg_source = match target_os.as_str() {
        "linux" => "../bin/ffmpeg-linux",
        "macos" => "../bin/ffmpeg-macos",
        "windows" => "../bin/ffmpeg-windows.exe",
        _ => panic!("Unsupported target OS: {}", target_os),
    };

    // ffprobe 二进制文件（可选）
    let ffprobe_source = match target_os.as_str() {
        "linux" => "../bin/ffprobe-linux",
        "macos" => "../bin/ffprobe-macos",
        "windows" => "../bin/ffprobe-windows.exe",
        _ => panic!("Unsupported target OS: {}", target_os),
    };

    let out_dir = env::var("OUT_DIR").unwrap();

    // 复制 ffmpeg
    if !Path::new(ffmpeg_source).exists() {
        panic!("ffmpeg binary not found: {}", ffmpeg_source);
    }
    let ffmpeg_dest = Path::new(&out_dir).join("ffmpeg");
    let _ = fs::remove_file(&ffmpeg_dest);
    fs::copy(ffmpeg_source, &ffmpeg_dest)
        .expect(&format!("Failed to copy {} to {}", ffmpeg_source, ffmpeg_dest.display()));

    // 复制 ffprobe（可选）
    if Path::new(ffprobe_source).exists() {
        let ffprobe_dest = Path::new(&out_dir).join("ffprobe");
        let _ = fs::remove_file(&ffprobe_dest);
        fs::copy(ffprobe_source, &ffprobe_dest)
            .expect(&format!("Failed to copy {} to {}", ffprobe_source, ffprobe_dest.display()));
        println!("cargo:rerun-if-changed={}", ffprobe_source);
    }

    println!("cargo:rerun-if-changed={}", ffmpeg_source);
    println!("cargo:rerun-if-changed=build.rs");
}
