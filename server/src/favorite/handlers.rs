// 收藏模块 - API 处理函数
use actix_web::{web, HttpResponse, Result};
use super::models::*;
use super::storage;

const DEFAULT_LIMIT: i64 = 50;
const MAX_LIMIT: i64 = 200;

/// 切换收藏状态
pub async fn toggle(body: web::Json<ToggleRequest>) -> Result<HttpResponse> {
    if !is_valid_level(&body.level) {
        return Ok(HttpResponse::BadRequest().json(serde_json::json!({
            "error": "level 必须是 favorite 或 featured"
        })));
    }
    let uuid = body.uuid.clone();
    let level = body.level.clone();

    let result = tokio::task::spawn_blocking(move || storage::toggle_favorite(&uuid, &level))
        .await
        .map_err(|e| actix_web::error::ErrorInternalServerError(format!("任务执行失败: {}", e)))?;

    match result {
        Ok(favorited) => Ok(HttpResponse::Ok().json(ToggleResponse {
            uuid: body.uuid.clone(),
            level: body.level.clone(),
            favorited,
        })),
        Err(e) => Ok(HttpResponse::InternalServerError().json(serde_json::json!({
            "error": format!("切换收藏失败: {}", e)
        }))),
    }
}

/// 获取收藏列表（分页，可按 level 筛选）
pub async fn list(query: web::Query<FavoriteListQuery>) -> Result<HttpResponse> {
    if let Some(ref l) = query.level {
        if !is_valid_level(l) {
            return Ok(HttpResponse::BadRequest().json(serde_json::json!({
                "error": "level 必须是 favorite 或 featured"
            })));
        }
    }
    let level = query.level.clone();
    let offset = query.offset.unwrap_or(0).max(0);
    let limit = query.limit.unwrap_or(DEFAULT_LIMIT).clamp(1, MAX_LIMIT);

    let result = tokio::task::spawn_blocking(move || {
        storage::list_favorites(level.as_deref(), offset, limit)
    })
    .await
    .map_err(|e| actix_web::error::ErrorInternalServerError(format!("任务执行失败: {}", e)))?;

    match result {
        Ok((files, total)) => {
            let has_more = offset + (files.len() as i64) < total;
            Ok(HttpResponse::Ok().json(FavoriteListResponse {
                files,
                total,
                offset,
                limit,
                has_more,
            }))
        }
        Err(e) => Ok(HttpResponse::InternalServerError().json(serde_json::json!({
            "error": format!("获取收藏列表失败: {}", e)
        }))),
    }
}

/// 批量查询多个文件的收藏状态
pub async fn status(query: web::Query<FavoriteStatusQuery>) -> Result<HttpResponse> {
    let uuids: Vec<String> = query
        .uuids
        .split(',')
        .map(|u| u.trim().to_string())
        .filter(|u| !u.is_empty())
        .collect();

    let result = tokio::task::spawn_blocking(move || storage::get_favorite_status(&uuids))
        .await
        .map_err(|e| actix_web::error::ErrorInternalServerError(format!("任务执行失败: {}", e)))?;

    match result {
        Ok(map) => Ok(HttpResponse::Ok().json(map)),
        Err(e) => Ok(HttpResponse::InternalServerError().json(serde_json::json!({
            "error": format!("查询收藏状态失败: {}", e)
        }))),
    }
}
