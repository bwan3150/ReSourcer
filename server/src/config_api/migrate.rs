// 源文件夹迁移：批量替换数据库中的路径前缀
use actix_web::{web, HttpResponse, Result};
use serde::Deserialize;
use crate::database;

#[derive(Debug, Deserialize)]
pub struct MigrateRequest {
    pub old_path: String,
    pub new_path: String,
}

/// POST /api/config/sources/migrate
/// 将数据库中所有旧路径前缀替换为新路径前缀
/// 例: old_path="/data/art" new_path="/volume1/media/art"
pub async fn migrate_source(req: web::Json<MigrateRequest>) -> Result<HttpResponse> {
    let old = req.old_path.trim_end_matches('/');
    let new = req.new_path.trim_end_matches('/');

    if old.is_empty() || new.is_empty() {
        return Ok(HttpResponse::BadRequest().json(serde_json::json!({
            "error": "old_path and new_path are required"
        })));
    }

    if old == new {
        return Ok(HttpResponse::BadRequest().json(serde_json::json!({
            "error": "old_path and new_path are the same"
        })));
    }

    let old = old.to_string();
    let new = new.to_string();

    let result = tokio::task::spawn_blocking(move || {
        do_migrate(&old, &new)
    }).await
        .map_err(|e| actix_web::error::ErrorInternalServerError(format!("task error: {}", e)))?
        .map_err(|e| actix_web::error::ErrorInternalServerError(format!("migrate error: {}", e)))?;

    Ok(HttpResponse::Ok().json(result))
}

fn do_migrate(old_prefix: &str, new_prefix: &str) -> std::result::Result<serde_json::Value, String> {
    let conn = database::get_connection()
        .map_err(|e| format!("db connection error: {}", e))?;

    // Use a transaction for atomicity
    conn.execute_batch("BEGIN").map_err(|e| format!("begin: {}", e))?;

    let mut total = 0u64;

    // Helper: replace prefix in a text column
    // UPDATE table SET col = new_prefix || substr(col, len(old_prefix)+1) WHERE col = old_prefix OR col LIKE old_prefix || '/%'
    let old_len = old_prefix.len() as i64 + 1; // +1 for 1-based substr

    macro_rules! migrate_col {
        ($table:expr, $col:expr) => {
            let sql = format!(
                "UPDATE {} SET {} = ?1 || substr({}, ?3) WHERE {} = ?2 OR {} LIKE ?2 || '/%'",
                $table, $col, $col, $col, $col
            );
            let count = conn.execute(&sql, rusqlite::params![new_prefix, old_prefix, old_len])
                .map_err(|e| format!("migrate {}.{}: {}", $table, $col, e))?;
            eprintln!("[migrate] {}.{}: {} rows", $table, $col, count);
            total += count as u64;
        };
    }

    // 1. source_folders.folder_path
    migrate_col!("source_folders", "folder_path");

    // 2. subfolder_order.folder_path
    migrate_col!("subfolder_order", "folder_path");

    // 3. file_index.current_path (can be NULL, but the WHERE handles it)
    migrate_col!("file_index", "current_path");

    // 4. file_index.folder_path
    migrate_col!("file_index", "folder_path");

    // 5. folder_index.path
    migrate_col!("folder_index", "path");

    // 6. folder_index.parent_path (can be NULL)
    migrate_col!("folder_index", "parent_path");

    // 7. folder_index.source_folder
    migrate_col!("folder_index", "source_folder");

    // 8. tags.source_folder
    migrate_col!("tags", "source_folder");

    // 9. download_history.file_path
    migrate_col!("download_history", "file_path");

    // 10. upload_history.target_folder
    migrate_col!("upload_history", "target_folder");

    // 11. config.hidden_folders (JSON array) — replace in JSON text
    let hidden_update = format!(
        "UPDATE config SET hidden_folders = replace(hidden_folders, ?1, ?2) WHERE hidden_folders LIKE '%' || ?1 || '%'"
    );
    let hc = conn.execute(&hidden_update, rusqlite::params![old_prefix, new_prefix])
        .map_err(|e| format!("migrate config.hidden_folders: {}", e))?;
    if hc > 0 {
        eprintln!("[migrate] config.hidden_folders: {} rows", hc);
        total += hc as u64;
    }

    conn.execute_batch("COMMIT").map_err(|e| format!("commit: {}", e))?;

    eprintln!("[migrate] Done: {} → {}, {} total updates", old_prefix, new_prefix, total);

    Ok(serde_json::json!({
        "status": "success",
        "old_path": old_prefix,
        "new_path": new_prefix,
        "updated_rows": total
    }))
}
