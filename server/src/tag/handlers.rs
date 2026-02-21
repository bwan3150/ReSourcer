// 标签模块 - API 处理函数
use actix_web::{web, HttpResponse, Result};
use super::models::*;
use super::storage;

/// 获取标签列表
pub async fn list_tags(query: web::Query<TagListQuery>) -> Result<HttpResponse> {
    let source_folder = query.source_folder.clone();

    let result = tokio::task::spawn_blocking(move || {
        storage::get_tags(&source_folder)
    }).await.map_err(|e| actix_web::error::ErrorInternalServerError(format!("任务执行失败: {}", e)))?;

    match result {
        Ok(tags) => Ok(HttpResponse::Ok().json(tags)),
        Err(e) => Ok(HttpResponse::InternalServerError().json(serde_json::json!({
            "error": format!("获取标签失败: {}", e)
        }))),
    }
}

/// 创建标签
pub async fn create_tag(body: web::Json<CreateTagRequest>) -> Result<HttpResponse> {
    let source_folder = body.source_folder.clone();
    let name = body.name.clone();
    let color = body.color.clone().unwrap_or_else(|| "#007AFF".to_string());

    let result = tokio::task::spawn_blocking(move || {
        storage::create_tag(&source_folder, &name, &color)
    }).await.map_err(|e| actix_web::error::ErrorInternalServerError(format!("任务执行失败: {}", e)))?;

    match result {
        Ok(tag) => Ok(HttpResponse::Ok().json(tag)),
        Err(e) => Ok(HttpResponse::InternalServerError().json(serde_json::json!({
            "error": format!("创建标签失败: {}", e)
        }))),
    }
}

/// 更新标签
pub async fn update_tag(
    path: web::Path<i64>,
    body: web::Json<UpdateTagRequest>,
) -> Result<HttpResponse> {
    let id = path.into_inner();
    let name = body.name.clone();
    let color = body.color.clone();

    let result = tokio::task::spawn_blocking(move || {
        storage::update_tag(id, name.as_deref(), color.as_deref())
    }).await.map_err(|e| actix_web::error::ErrorInternalServerError(format!("任务执行失败: {}", e)))?;

    match result {
        Ok(()) => Ok(HttpResponse::Ok().json(serde_json::json!({ "success": true }))),
        Err(e) => Ok(HttpResponse::InternalServerError().json(serde_json::json!({
            "error": format!("更新标签失败: {}", e)
        }))),
    }
}

/// 删除标签
pub async fn delete_tag(path: web::Path<i64>) -> Result<HttpResponse> {
    let id = path.into_inner();

    let result = tokio::task::spawn_blocking(move || {
        storage::delete_tag(id)
    }).await.map_err(|e| actix_web::error::ErrorInternalServerError(format!("任务执行失败: {}", e)))?;

    match result {
        Ok(()) => Ok(HttpResponse::Ok().json(serde_json::json!({ "success": true }))),
        Err(e) => Ok(HttpResponse::InternalServerError().json(serde_json::json!({
            "error": format!("删除标签失败: {}", e)
        }))),
    }
}

/// 获取文件标签
pub async fn get_file_tags(query: web::Query<FileTagQuery>) -> Result<HttpResponse> {
    let file_uuid = query.file_uuid.clone();

    let result = tokio::task::spawn_blocking(move || {
        storage::get_file_tags(&file_uuid)
    }).await.map_err(|e| actix_web::error::ErrorInternalServerError(format!("任务执行失败: {}", e)))?;

    match result {
        Ok(tags) => Ok(HttpResponse::Ok().json(FileTagsResponse {
            file_uuid: query.file_uuid.clone(),
            tags,
        })),
        Err(e) => Ok(HttpResponse::InternalServerError().json(serde_json::json!({
            "error": format!("获取文件标签失败: {}", e)
        }))),
    }
}

/// 设置文件标签
pub async fn set_file_tags(body: web::Json<FileTagRequest>) -> Result<HttpResponse> {
    let file_uuid = body.file_uuid.clone();
    let tag_ids = body.tag_ids.clone();

    let result = tokio::task::spawn_blocking(move || {
        storage::set_file_tags(&file_uuid, &tag_ids)
    }).await.map_err(|e| actix_web::error::ErrorInternalServerError(format!("任务执行失败: {}", e)))?;

    match result {
        Ok(()) => Ok(HttpResponse::Ok().json(serde_json::json!({ "success": true }))),
        Err(e) => Ok(HttpResponse::InternalServerError().json(serde_json::json!({
            "error": format!("设置文件标签失败: {}", e)
        }))),
    }
}

/// 批量获取多个文件的标签
pub async fn get_files_tags(body: web::Json<FilesTagsRequest>) -> Result<HttpResponse> {
    let file_uuids = body.file_uuids.clone();

    let result = tokio::task::spawn_blocking(move || {
        storage::get_files_tags(&file_uuids)
    }).await.map_err(|e| actix_web::error::ErrorInternalServerError(format!("任务执行失败: {}", e)))?;

    match result {
        Ok(tags_map) => {
            // 转换为 Vec<FileTagsResponse> 格式
            let responses: Vec<FileTagsResponse> = tags_map.into_iter()
                .map(|(file_uuid, tags)| FileTagsResponse { file_uuid, tags })
                .collect();
            Ok(HttpResponse::Ok().json(responses))
        }
        Err(e) => Ok(HttpResponse::InternalServerError().json(serde_json::json!({
            "error": format!("批量获取文件标签失败: {}", e)
        }))),
    }
}
