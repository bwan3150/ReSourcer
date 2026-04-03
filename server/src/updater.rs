// 自更新模块：检查 GitHub releases 并自我更新
use actix_web::{HttpResponse, Result};
use serde::Deserialize;

/// 从 app.json 读取当前版本和 GitHub URL
fn load_app_info() -> Option<(String, String)> {
    #[derive(Deserialize)]
    struct AppConfig { version: String, github_url: String }
    let data = crate::static_files::read_config_file("app.json")?;
    let config: AppConfig = serde_json::from_slice(&data).ok()?;
    // 从 github_url 提取 owner/repo: "https://github.com/bwan3150/ReSourcer" → "bwan3150/ReSourcer"
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

/// GET /api/app/check-update
pub async fn check_update() -> Result<HttpResponse> {
    let (current, repo) = load_app_info()
        .ok_or_else(|| actix_web::error::ErrorInternalServerError("cannot read app.json"))?;

    let api_url = format!("https://api.github.com/repos/{}/releases/latest", repo);

    let client = reqwest::Client::new();
    let resp = client.get(&api_url)
        .header("User-Agent", "ReSourcer-Updater")
        .header("Accept", "application/vnd.github.v3+json")
        .send().await
        .map_err(|e| actix_web::error::ErrorInternalServerError(format!("GitHub API error: {}", e)))?;

    if !resp.status().is_success() {
        return Ok(HttpResponse::Ok().json(serde_json::json!({
            "current_version": current,
            "latest_version": null,
            "has_update": false,
            "error": format!("GitHub API returned {}", resp.status())
        })));
    }

    let release: serde_json::Value = resp.json().await
        .map_err(|e| actix_web::error::ErrorInternalServerError(format!("parse error: {}", e)))?;

    let latest = release["tag_name"].as_str().unwrap_or("").trim_start_matches('v').to_string();
    let current_clean = current.trim_start_matches('v').to_string();
    let has_update = !latest.is_empty() && latest != current_clean;

    // Find download URL for this platform's artifact
    let download_url = release["assets"].as_array()
        .and_then(|assets| {
            let name = artifact_name();
            assets.iter().find(|a| a["name"].as_str() == Some(name))
        })
        .and_then(|a| a["browser_download_url"].as_str())
        .map(|s| s.to_string());

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "current_version": current,
        "latest_version": latest,
        "has_update": has_update,
        "download_url": download_url,
    })))
}

/// POST /api/app/update
/// 下载最新 release binary，替换当前可执行文件，然后重启
pub async fn do_update() -> Result<HttpResponse> {
    let (current, repo) = load_app_info()
        .ok_or_else(|| actix_web::error::ErrorInternalServerError("cannot read app.json"))?;

    // 1. Get latest release info
    let api_url = format!("https://api.github.com/repos/{}/releases/latest", repo);
    let client = reqwest::Client::new();
    let resp = client.get(&api_url)
        .header("User-Agent", "ReSourcer-Updater")
        .header("Accept", "application/vnd.github.v3+json")
        .send().await
        .map_err(|e| actix_web::error::ErrorInternalServerError(format!("GitHub API error: {}", e)))?;

    let release: serde_json::Value = resp.json().await
        .map_err(|e| actix_web::error::ErrorInternalServerError(format!("parse error: {}", e)))?;

    let latest_tag = release["tag_name"].as_str().unwrap_or("").to_string();

    // 2. Find download URL
    let download_url = release["assets"].as_array()
        .and_then(|assets| {
            let name = artifact_name();
            assets.iter().find(|a| a["name"].as_str() == Some(name))
        })
        .and_then(|a| a["browser_download_url"].as_str())
        .ok_or_else(|| actix_web::error::ErrorBadRequest(
            format!("No release artifact found for this platform ({})", artifact_name())
        ))?
        .to_string();

    // 3. Download new binary
    eprintln!("[update] Downloading {} ...", download_url);
    let binary_data = client.get(&download_url)
        .header("User-Agent", "ReSourcer-Updater")
        .send().await
        .map_err(|e| actix_web::error::ErrorInternalServerError(format!("download error: {}", e)))?
        .bytes().await
        .map_err(|e| actix_web::error::ErrorInternalServerError(format!("download read error: {}", e)))?;

    // 4. Get current executable path
    let exe_path = std::env::current_exe()
        .map_err(|e| actix_web::error::ErrorInternalServerError(format!("cannot find exe path: {}", e)))?;

    // 5. Write to temp file next to current exe, then swap
    let tmp_path = exe_path.with_extension("new");
    let backup_path = exe_path.with_extension("bak");

    std::fs::write(&tmp_path, &binary_data)
        .map_err(|e| actix_web::error::ErrorInternalServerError(format!("write failed: {}", e)))?;

    // Set executable permission
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

    // 6. Backup current → .bak, move new → current
    let _ = std::fs::remove_file(&backup_path); // remove old backup if exists
    std::fs::rename(&exe_path, &backup_path)
        .map_err(|e| actix_web::error::ErrorInternalServerError(format!("backup failed: {}", e)))?;
    std::fs::rename(&tmp_path, &exe_path)
        .map_err(|e| {
            // Try to restore backup
            let _ = std::fs::rename(&backup_path, &exe_path);
            actix_web::error::ErrorInternalServerError(format!("replace failed: {}", e))
        })?;

    // 7. Update version in app.json
    if let Some(data) = crate::static_files::read_config_file("app.json") {
        if let Ok(mut config) = serde_json::from_slice::<serde_json::Value>(&data) {
            config["version"] = serde_json::Value::String(latest_tag.trim_start_matches('v').to_string());
            let app_json_path = crate::static_files::app_dir().join("config").join("app.json");
            let _ = std::fs::write(&app_json_path, serde_json::to_string_pretty(&config).unwrap());
        }
    }

    eprintln!("[update] Updated from {} to {}. Restarting...", current, latest_tag);

    // 8. Exit process — systemd (Restart=on-failure) or the user will restart it
    //    Send response first, then exit after a short delay
    tokio::spawn(async move {
        tokio::time::sleep(tokio::time::Duration::from_millis(500)).await;
        std::process::exit(0);
    });

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "status": "updating",
        "message": format!("Updated to {}. Server is restarting.", latest_tag)
    })))
}
