// 文件夹排序功能
use actix_web::{web, HttpResponse, Result};
use super::models::ReorderCategoriesRequest;

/// POST /api/folder/reorder
/// 保存分类顺序
pub async fn reorder_categories(req: web::Json<ReorderCategoriesRequest>) -> Result<HttpResponse> {
    // 保存指定源文件夹的分类顺序
    crate::config_api::storage::set_category_order(&req.source_folder, req.category_order.clone())
        .map_err(|e| {
            actix_web::error::ErrorInternalServerError(format!("无法保存分类顺序: {}", e))
        })?;

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "status": "success"
    })))
}
