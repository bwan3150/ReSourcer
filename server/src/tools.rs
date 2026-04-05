// 工具管理模块：管理 ffmpeg/ffprobe/yt-dlp 等外部工具的下载源配置
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;

/// 单个工具的配置
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ToolConfig {
    pub name: String,
    pub description: String,
    /// 各平台的下载 URL
    pub urls: ToolUrls,
    /// 工具是否已安装（运行时计算）
    #[serde(skip_deserializing, default)]
    pub installed: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ToolUrls {
    pub linux_x86_64: String,
    pub linux_aarch64: String,
    pub macos: String,
    pub windows: String,
}

/// 所有工具配置
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ToolsConfig {
    pub tools: Vec<ToolConfig>,
}

/// 默认工具配置
fn default_tools() -> Vec<ToolConfig> {
    vec![
        ToolConfig {
            name: "ffmpeg".to_string(),
            description: "Video/image processing tool".to_string(),
            urls: ToolUrls {
                linux_x86_64: "https://resourcer-assets.s3.ap-southeast-2.amazonaws.com/binaries/ffmpeg/ffmpeg-linux-x86_64".to_string(),
                linux_aarch64: String::new(),
                macos: "https://resourcer-assets.s3.ap-southeast-2.amazonaws.com/binaries/ffmpeg/ffmpeg-macos".to_string(),
                windows: "https://resourcer-assets.s3.ap-southeast-2.amazonaws.com/binaries/ffmpeg/ffmpeg-windows.exe".to_string(),
            },
            installed: false,
        },
        ToolConfig {
            name: "ffprobe".to_string(),
            description: "Media file analyzer".to_string(),
            urls: ToolUrls {
                linux_x86_64: "https://resourcer-assets.s3.ap-southeast-2.amazonaws.com/binaries/ffprobe/ffprobe-linux-x86_64".to_string(),
                linux_aarch64: String::new(),
                macos: "https://resourcer-assets.s3.ap-southeast-2.amazonaws.com/binaries/ffprobe/ffprobe-macos".to_string(),
                windows: "https://resourcer-assets.s3.ap-southeast-2.amazonaws.com/binaries/ffprobe/ffprobe-windows.exe".to_string(),
            },
            installed: false,
        },
        ToolConfig {
            name: "yt-dlp".to_string(),
            description: "Video downloader".to_string(),
            urls: ToolUrls {
                linux_x86_64: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux".to_string(),
                linux_aarch64: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux_aarch64".to_string(),
                macos: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos".to_string(),
                windows: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe".to_string(),
            },
            installed: false,
        },
    ]
}

fn tools_json_path() -> PathBuf {
    crate::static_files::app_dir().join("config").join("tools.json")
}

fn tools_dir() -> PathBuf {
    crate::static_files::app_dir().join("tools")
}

/// 加载工具配置（tools.json 不存在则用默认值创建）
pub fn load_tools_config() -> Vec<ToolConfig> {
    let path = tools_json_path();
    let mut tools = if let Ok(data) = fs::read_to_string(&path) {
        if let Ok(config) = serde_json::from_str::<ToolsConfig>(&data) {
            config.tools
        } else {
            default_tools()
        }
    } else {
        let tools = default_tools();
        // 写入默认配置
        let config = ToolsConfig { tools: tools.clone() };
        if let Ok(json) = serde_json::to_string_pretty(&config) {
            let _ = fs::create_dir_all(path.parent().unwrap());
            let _ = fs::write(&path, json);
        }
        tools
    };

    // 计算 installed 状态
    for tool in &mut tools {
        let binary_name = tool_binary_name(&tool.name);
        tool.installed = tools_dir().join(&binary_name).exists();
    }
    tools
}

/// 保存工具配置
pub fn save_tools_config(tools: &[ToolConfig]) -> Result<(), String> {
    let path = tools_json_path();
    let config = ToolsConfig { tools: tools.to_vec() };
    let json = serde_json::to_string_pretty(&config)
        .map_err(|e| format!("序列化失败: {}", e))?;
    fs::create_dir_all(path.parent().unwrap())
        .map_err(|e| format!("创建目录失败: {}", e))?;
    fs::write(&path, json)
        .map_err(|e| format!("写入失败: {}", e))?;
    Ok(())
}

/// 获取指定工具当前平台的下载 URL
pub fn get_tool_download_url(tool_name: &str) -> Option<String> {
    let tools = load_tools_config();
    let tool = tools.iter().find(|t| t.name == tool_name)?;
    Some(platform_url(&tool.urls))
}

/// 获取工具二进制文件名
pub fn tool_binary_name(name: &str) -> String {
    if cfg!(target_os = "windows") {
        format!("{}.exe", name)
    } else {
        name.to_string()
    }
}

/// 根据当前平台和架构选择 URL
fn platform_url(urls: &ToolUrls) -> String {
    if cfg!(target_os = "linux") {
        if cfg!(target_arch = "aarch64") {
            urls.linux_aarch64.clone()
        } else {
            urls.linux_x86_64.clone()
        }
    } else if cfg!(target_os = "windows") {
        urls.windows.clone()
    } else {
        urls.macos.clone()
    }
}

// === Preflight check: verify tools on startup, auto-download if missing ===

#[derive(Debug)]
pub enum ToolStatus {
    Ready(String),     // version string
    Downloading,
    Downloaded,
    Failed(String),    // error message
}

/// 检查单个工具是否可用（运行 --version / -version）
fn verify_tool(name: &str) -> Option<String> {
    let binary = tools_dir().join(tool_binary_name(name));
    if !binary.exists() {
        return None;
    }
    // ffmpeg/ffprobe 用 -version, yt-dlp 用 --version
    let flag = if name == "yt-dlp" { "--version" } else { "-version" };
    let output = std::process::Command::new(&binary)
        .arg(flag)
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    let stdout = String::from_utf8_lossy(&output.stdout);
    // 取第一行作为版本信息
    let version = stdout.lines().next().unwrap_or("").trim().to_string();
    if version.is_empty() { None } else { Some(version) }
}

/// 同步下载工具 binary
fn download_tool(name: &str) -> Result<(), String> {
    let url = get_tool_download_url(name)
        .ok_or_else(|| format!("no download URL configured for {}", name))?;
    if url.is_empty() {
        return Err("no download URL for this platform/arch".to_string());
    }
    let binary_path = tools_dir().join(tool_binary_name(name));

    fs::create_dir_all(tools_dir())
        .map_err(|e| format!("cannot create tools dir: {}", e))?;

    let output = std::process::Command::new("curl")
        .args(&["-sSL", "--fail", "-o", binary_path.to_str().unwrap(), &url])
        .output()
        .map_err(|e| format!("curl failed: {}", e))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        // 清理损坏的文件
        let _ = fs::remove_file(&binary_path);
        return Err(format!("download failed: {}", stderr.trim()));
    }

    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        if let Ok(meta) = fs::metadata(&binary_path) {
            let mut perms = meta.permissions();
            perms.set_mode(0o755);
            let _ = fs::set_permissions(&binary_path, perms);
        }
    }

    // macOS: 清除 quarantine 属性，否则 Gatekeeper 会阻止执行
    #[cfg(target_os = "macos")]
    {
        let _ = std::process::Command::new("xattr")
            .args(&["-cr", binary_path.to_str().unwrap()])
            .output();
    }

    Ok(())
}

/// 启动时预检所有必要工具，输出状态表，自动下载缺失的
pub fn preflight_check() {
    let db_path = crate::database::get_db_path();
    let tools_to_check = ["ffmpeg", "ffprobe"]; // 启动时检查的基础工具

    // 1. Database
    let db_ok = db_path.exists();
    let db_status = if db_ok {
        let size = fs::metadata(&db_path).map(|m| m.len()).unwrap_or(0);
        format!("\x1b[32m✓\x1b[0m db: {}", format_bytes(size))
    } else {
        "\x1b[33m-\x1b[0m db: pending".to_string()
    };

    // 2. Required tools (ffmpeg, ffprobe)
    let mut tool_statuses = Vec::new();
    for name in &tools_to_check {
        tool_statuses.push(check_and_ensure_tool_quiet(name, true));
    }

    // 输出状态行
    print!("  {}", db_status);
    for s in &tool_statuses {
        print!("  {}", s);
    }
    println!();
}


/// 静默版本：返回状态字符串而非直接打印
fn check_and_ensure_tool_quiet(name: &str, required: bool) -> String {
    if let Some(_) = verify_tool(name) {
        return format!("\x1b[32m✓\x1b[0m {}", name);
    }

    let binary_path = tools_dir().join(tool_binary_name(name));
    if binary_path.exists() {
        let _ = fs::remove_file(&binary_path);
    }

    match download_tool(name) {
        Ok(()) => {
            if verify_tool(name).is_some() {
                format!("\x1b[32m✓\x1b[0m {}", name)
            } else {
                format!("\x1b[31m✗\x1b[0m {}", name)
            }
        }
        Err(_) => {
            if required {
                format!("\x1b[31m✗\x1b[0m {}", name)
            } else {
                format!("\x1b[33m-\x1b[0m {}", name)
            }
        }
    }
}

fn format_bytes(bytes: u64) -> String {
    if bytes < 1024 { return format!("{} B", bytes); }
    if bytes < 1024 * 1024 { return format!("{:.1} KB", bytes as f64 / 1024.0); }
    return format!("{:.1} MB", bytes as f64 / (1024.0 * 1024.0));
}

// === API handlers ===
use actix_web::{web, HttpResponse};

pub fn routes(cfg: &mut web::ServiceConfig) {
    cfg.service(web::resource("/tools").route(web::get().to(get_tools)))
       .service(web::resource("/tools/update").route(web::post().to(update_tool_urls)));
}

/// GET /api/config/tools — 获取工具列表及状态
async fn get_tools() -> actix_web::Result<HttpResponse> {
    let tools = load_tools_config();
    Ok(HttpResponse::Ok().json(serde_json::json!({ "tools": tools })))
}

/// POST /api/config/tools/update — 更新工具下载源
async fn update_tool_urls(body: web::Json<UpdateToolRequest>) -> actix_web::Result<HttpResponse> {
    let mut tools = load_tools_config();
    if let Some(tool) = tools.iter_mut().find(|t| t.name == body.name) {
        tool.urls = body.urls.clone();
        save_tools_config(&tools)
            .map_err(|e| actix_web::error::ErrorInternalServerError(e))?;
        Ok(HttpResponse::Ok().json(serde_json::json!({ "status": "success" })))
    } else {
        Ok(HttpResponse::NotFound().json(serde_json::json!({ "error": "工具未找到" })))
    }
}

#[derive(Deserialize)]
struct UpdateToolRequest {
    name: String,
    urls: ToolUrls,
}
