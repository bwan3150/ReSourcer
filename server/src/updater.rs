// 自更新模块：检查 GitHub releases 并自我更新
use actix_web::{HttpResponse, Result};
use serde::Deserialize;

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

/// 获取 GitHub latest release 信息
async fn fetch_latest_release(repo: &str) -> std::result::Result<serde_json::Value, String> {
    let api_url = format!("https://api.github.com/repos/{}/releases/latest", repo);
    let client = reqwest::Client::new();
    let resp = client.get(&api_url)
        .header("User-Agent", "ReSourcer-Updater")
        .header("Accept", "application/vnd.github.v3+json")
        .send().await
        .map_err(|e| format!("GitHub API error: {}", e))?;

    if !resp.status().is_success() {
        return Err(format!("GitHub API returned {}", resp.status()));
    }

    resp.json().await.map_err(|e| format!("parse error: {}", e))
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
            let app_json_path = crate::static_files::app_dir().join("config").join("app.json");
            let _ = std::fs::write(&app_json_path, serde_json::to_string_pretty(&config).unwrap());
        }
    }

    eprintln!("[update] Updated from {} to {}. Restarting...", current, latest_version);

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
