// 自更新模块：检查 GitHub releases 并自我更新
use actix_web::{HttpResponse, Result};
use serde::Deserialize;
use std::sync::atomic::{AtomicBool, Ordering};

/// Global flag: true after update triggered, server is about to restart
static UPDATING: AtomicBool = AtomicBool::new(false);

pub fn is_updating() -> bool {
    UPDATING.load(Ordering::Relaxed)
}

/// 从 app.json 读取当前版本和 GitHub URL
fn load_app_info() -> Option<(String, String)> {
    #[derive(Deserialize)]
    struct AppConfig { version: String, github_url: String }
    let data = crate::static_files::read_config_file("app.json")?;
    let config: AppConfig = serde_json::from_slice(&data).ok()?;
    let repo = config.github_url.trim_end_matches('/')
        .strip_prefix("https://github.com/")?
        .to_string();
    Some((config.version, repo))
}

/// 当前平台的 release artifact 名称
fn artifact_name() -> &'static str {
    if cfg!(target_os = "linux") && cfg!(target_arch = "x86_64") {
        "re-sourcer-linux-x86_64"
    } else if cfg!(target_os = "linux") && cfg!(target_arch = "aarch64") {
        "re-sourcer-linux-aarch64"
    } else if cfg!(target_os = "macos") {
        "re-sourcer-macos"
    } else if cfg!(target_os = "windows") {
        "re-sourcer-windows.exe"
    } else {
        "re-sourcer"
    }
}

/// 从 tag 名提取纯版本号: "server-v0.3.6-beta" → "0.3.6-beta", "v1.0" → "1.0"
fn extract_version(tag: &str) -> String {
    tag.trim_start_matches("server-v")
       .trim_start_matches("v")
       .to_string()
}

/// 取某个 tag 前缀下最新的 release
///
/// 不能用 /releases/latest：这个仓库里服务端（server-v*）和网页端（web-v*）
/// 各自发版，latest 只会给出全仓库最新的那条，两边会互相抢。
async fn fetch_latest_release_with_prefix(
    repo: &str,
    prefix: &str,
) -> std::result::Result<serde_json::Value, String> {
    let api_url = format!("https://api.github.com/repos/{}/releases?per_page=30", repo);
    let client = reqwest::Client::new();
    let resp = client.get(&api_url)
        .header("User-Agent", "ReSourcer-Updater")
        .header("Accept", "application/vnd.github.v3+json")
        .send().await
        .map_err(|e| format!("GitHub API error: {}", e))?;

    if !resp.status().is_success() {
        return Err(format!("GitHub API returned {}", resp.status()));
    }

    let releases: Vec<serde_json::Value> = resp.json().await
        .map_err(|e| format!("parse error: {}", e))?;

    // GitHub 按发布时间倒序返回，第一条匹配的就是最新的
    releases.into_iter()
        .find(|r| {
            r["tag_name"].as_str().map_or(false, |t| t.starts_with(prefix))
                && !r["draft"].as_bool().unwrap_or(false)
        })
        .ok_or_else(|| format!("没有找到 {}* 的 release", prefix))
}

/// 服务端自己的最新 release
async fn fetch_latest_release(repo: &str) -> std::result::Result<serde_json::Value, String> {
    fetch_latest_release_with_prefix(repo, "server-v").await
}

/// 从 release assets 中找到当前平台的下载 URL
fn find_asset_url(release: &serde_json::Value) -> Option<String> {
    let name = artifact_name();
    release["assets"].as_array()?
        .iter()
        .find(|a| a["name"].as_str() == Some(name))?
        ["browser_download_url"].as_str()
        .map(|s| s.to_string())
}

/// GET /api/app/check-update
pub async fn check_update() -> Result<HttpResponse> {
    let (current, repo) = load_app_info()
        .ok_or_else(|| actix_web::error::ErrorInternalServerError("cannot read app.json"))?;

    let release = match fetch_latest_release(&repo).await {
        Ok(r) => r,
        Err(e) => {
            return Ok(HttpResponse::Ok().json(serde_json::json!({
                "current_version": current,
                "latest_version": null,
                "has_update": false,
                "error": e
            })));
        }
    };

    let latest_tag = release["tag_name"].as_str().unwrap_or("");
    let latest_version = extract_version(latest_tag);
    let has_update = !latest_version.is_empty() && latest_version != current;
    let download_url = find_asset_url(&release);

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "current_version": current,
        "latest_version": latest_version,
        "has_update": has_update,
        "download_url": download_url,
    })))
}

/// POST /api/app/update
pub async fn do_update() -> Result<HttpResponse> {
    let (current, repo) = load_app_info()
        .ok_or_else(|| actix_web::error::ErrorInternalServerError("cannot read app.json"))?;

    let release = fetch_latest_release(&repo).await
        .map_err(|e| actix_web::error::ErrorInternalServerError(e))?;

    let latest_tag = release["tag_name"].as_str().unwrap_or("").to_string();
    let latest_version = extract_version(&latest_tag);

    let download_url = find_asset_url(&release)
        .ok_or_else(|| actix_web::error::ErrorBadRequest(
            format!("No release artifact for this platform ({})", artifact_name())
        ))?;

    // Download new binary
    eprintln!("[update] Downloading {} ...", download_url);
    let client = reqwest::Client::new();
    let binary_data = client.get(&download_url)
        .header("User-Agent", "ReSourcer-Updater")
        .send().await
        .map_err(|e| actix_web::error::ErrorInternalServerError(format!("download error: {}", e)))?
        .bytes().await
        .map_err(|e| actix_web::error::ErrorInternalServerError(format!("download read error: {}", e)))?;

    // Replace binary
    let exe_path = std::env::current_exe()
        .map_err(|e| actix_web::error::ErrorInternalServerError(format!("cannot find exe path: {}", e)))?;

    let tmp_path = exe_path.with_extension("new");
    let backup_path = exe_path.with_extension("bak");

    std::fs::write(&tmp_path, &binary_data)
        .map_err(|e| actix_web::error::ErrorInternalServerError(format!("write failed: {}", e)))?;

    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mut perms = std::fs::metadata(&tmp_path)
            .map_err(|e| actix_web::error::ErrorInternalServerError(format!("metadata: {}", e)))?
            .permissions();
        perms.set_mode(0o755);
        std::fs::set_permissions(&tmp_path, perms)
            .map_err(|e| actix_web::error::ErrorInternalServerError(format!("chmod: {}", e)))?;
    }

    let _ = std::fs::remove_file(&backup_path);
    std::fs::rename(&exe_path, &backup_path)
        .map_err(|e| actix_web::error::ErrorInternalServerError(format!("backup failed: {}", e)))?;
    std::fs::rename(&tmp_path, &exe_path)
        .map_err(|e| {
            let _ = std::fs::rename(&backup_path, &exe_path);
            actix_web::error::ErrorInternalServerError(format!("replace failed: {}", e))
        })?;

    // Update version in app.json
    if let Some(data) = crate::static_files::read_config_file("app.json") {
        if let Ok(mut config) = serde_json::from_slice::<serde_json::Value>(&data) {
            config["version"] = serde_json::Value::String(latest_version.clone());
            let app_json_path = crate::static_files::data_dir().join("config").join("app.json");
            let _ = std::fs::write(&app_json_path, serde_json::to_string_pretty(&config).unwrap());
        }
    }

    eprintln!("[update] Updated from {} to {}. Restarting...", current, latest_version);

    // Mark as updating — all subsequent requests will get 503
    UPDATING.store(true, Ordering::Relaxed);

    // Exit — systemd (Restart=always) will restart with the new binary
    tokio::spawn(async move {
        tokio::time::sleep(tokio::time::Duration::from_millis(500)).await;
        std::process::exit(0);
    });

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "status": "updating",
        "message": format!("Updated to {}. Server is restarting.", latest_version)
    })))
}

// ─────────────────────────────────────────────────────────────
// 网页端自更新
//
// 网页端是一堆静态文件，不需要替换运行中的进程、也不需要重启：
// 把新的构建产物解压到 web_dir() 即可，下一次请求就读到新文件。
// ─────────────────────────────────────────────────────────────

const WEB_ASSET: &str = "web-dist.zip";

/// GET /api/app/web/check-update
pub async fn check_web_update() -> Result<HttpResponse> {
    let (_, repo) = load_app_info()
        .ok_or_else(|| actix_web::error::ErrorInternalServerError("cannot read app.json"))?;

    let web_root = crate::static_files::web_dir();
    let current = crate::web_static::installed_version(&web_root);

    let release = match fetch_latest_release_with_prefix(&repo, "web-v").await {
        Ok(r) => r,
        Err(e) => {
            return Ok(HttpResponse::Ok().json(serde_json::json!({
                "current_version": current,
                "latest_version": null,
                "has_update": false,
                "error": e
            })));
        }
    };

    let latest_version = extract_web_version(release["tag_name"].as_str().unwrap_or(""));
    let download_url = find_named_asset(&release, WEB_ASSET);

    // 装不出版本号时（本地手工构建的 dist 没有 version.json）不主动提示更新，
    // 免得每次打开都闪一个红点
    let has_update = match (&current, latest_version.is_empty()) {
        (Some(cur), false) => cur != &latest_version,
        (None, false) => !web_root.join("index.html").exists(),
        _ => false,
    };

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "current_version": current,
        "latest_version": latest_version,
        "has_update": has_update,
        "download_url": download_url,
    })))
}

/// POST /api/app/web/update
pub async fn do_web_update() -> Result<HttpResponse> {
    let (_, repo) = load_app_info()
        .ok_or_else(|| actix_web::error::ErrorInternalServerError("cannot read app.json"))?;

    let release = fetch_latest_release_with_prefix(&repo, "web-v").await
        .map_err(actix_web::error::ErrorInternalServerError)?;

    let latest_version = extract_web_version(release["tag_name"].as_str().unwrap_or(""));
    let download_url = find_named_asset(&release, WEB_ASSET)
        .ok_or_else(|| actix_web::error::ErrorBadRequest(
            format!("该 release 下没有 {}", WEB_ASSET)
        ))?;

    eprintln!("[web-update] 下载 {} ...", download_url);
    let client = reqwest::Client::new();
    let data = client.get(&download_url)
        .header("User-Agent", "ReSourcer-Updater")
        .send().await
        .map_err(|e| actix_web::error::ErrorInternalServerError(format!("下载失败: {}", e)))?
        .bytes().await
        .map_err(|e| actix_web::error::ErrorInternalServerError(format!("读取失败: {}", e)))?;

    let web_root = crate::static_files::web_dir();
    let parent = web_root.parent()
        .ok_or_else(|| actix_web::error::ErrorInternalServerError("bad web dir"))?
        .to_path_buf();
    let staging = parent.join("web.new");
    let old = parent.join("web.old");

    // 先解压到临时目录，确认完整再替换 —— 中途失败不会留下半套文件
    let _ = std::fs::remove_dir_all(&staging);
    std::fs::create_dir_all(&staging)
        .map_err(|e| actix_web::error::ErrorInternalServerError(format!("建临时目录失败: {}", e)))?;

    extract_zip(&data, &staging)
        .map_err(|e| {
            let _ = std::fs::remove_dir_all(&staging);
            actix_web::error::ErrorInternalServerError(format!("解压失败: {}", e))
        })?;

    if !staging.join("index.html").exists() {
        let _ = std::fs::remove_dir_all(&staging);
        return Err(actix_web::error::ErrorInternalServerError(
            "产物里没有 index.html，已放弃替换",
        ));
    }

    // 换入：旧目录先挪开，失败能换回来
    let _ = std::fs::remove_dir_all(&old);
    if web_root.exists() {
        std::fs::rename(&web_root, &old)
            .map_err(|e| actix_web::error::ErrorInternalServerError(format!("备份旧版失败: {}", e)))?;
    }
    if let Err(e) = std::fs::rename(&staging, &web_root) {
        let _ = std::fs::rename(&old, &web_root);
        return Err(actix_web::error::ErrorInternalServerError(format!("替换失败: {}", e)));
    }
    let _ = std::fs::remove_dir_all(&old);

    eprintln!("[web-update] 已更新到 {}", latest_version);
    Ok(HttpResponse::Ok().json(serde_json::json!({
        "status": "success",
        "version": latest_version,
        "message": format!("网页端已更新到 {}，刷新页面即可生效", latest_version)
    })))
}

fn extract_web_version(tag: &str) -> String {
    tag.trim_start_matches("web-v").trim_start_matches('v').to_string()
}

fn find_named_asset(release: &serde_json::Value, name: &str) -> Option<String> {
    release["assets"].as_array()?
        .iter()
        .find(|a| a["name"].as_str() == Some(name))?
        ["browser_download_url"].as_str()
        .map(|s| s.to_string())
}

/// 解压 zip 到目标目录
/// 逐条校验路径，拒绝 `..` 和绝对路径（zip slip）
fn extract_zip(data: &[u8], dest: &std::path::Path) -> std::result::Result<(), String> {
    let reader = std::io::Cursor::new(data);
    let mut archive = zip::ZipArchive::new(reader).map_err(|e| e.to_string())?;

    for i in 0..archive.len() {
        let mut entry = archive.by_index(i).map_err(|e| e.to_string())?;
        let Some(rel) = entry.enclosed_name() else {
            return Err(format!("压缩包内有不安全的路径: {}", entry.name()));
        };
        let out = dest.join(rel);
        if entry.is_dir() {
            std::fs::create_dir_all(&out).map_err(|e| e.to_string())?;
            continue;
        }
        if let Some(p) = out.parent() {
            std::fs::create_dir_all(p).map_err(|e| e.to_string())?;
        }
        let mut f = std::fs::File::create(&out).map_err(|e| e.to_string())?;
        std::io::copy(&mut entry, &mut f).map_err(|e| e.to_string())?;
    }
    Ok(())
}
