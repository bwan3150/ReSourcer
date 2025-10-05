use std::env;
use std::fs;
use std::path::Path;

fn main() {
    let target_os = env::var("CARGO_CFG_TARGET_OS").unwrap();

    let yt_dlp_source = match target_os.as_str() {
        "linux" => "bin/yt-dlp-linux",
        "macos" => "bin/yt-dlp-macos",
        "windows" => "bin/yt-dlp-windows.exe",
        _ => panic!("Unsupported target OS: {}", target_os),
    };

    // 确保源文件存在
    if !Path::new(yt_dlp_source).exists() {
        panic!("yt-dlp binary not found: {}", yt_dlp_source);
    }

    // 复制到 OUT_DIR，这样可以用 include_bytes! 嵌入
    let out_dir = env::var("OUT_DIR").unwrap();
    let dest_path = Path::new(&out_dir).join("yt-dlp");

    fs::copy(yt_dlp_source, &dest_path)
        .expect(&format!("Failed to copy {} to {}", yt_dlp_source, dest_path.display()));

    println!("cargo:rerun-if-changed={}", yt_dlp_source);
    println!("cargo:rerun-if-changed=build.rs");
}
