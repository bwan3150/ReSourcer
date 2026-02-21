// 文件夹排序功能
use actix_web::{web, HttpResponse, Result};
use super::models::ReorderCategoriesRequest;

/// POST /api/folder/reorder
/// 保存子文件夹排序（支持任意层级）
pub async fn reorder_categories(req: web::Json<ReorderCategoriesRequest>) -> Result<HttpResponse> {
    // 优先使用新字段 folder_path，回退到旧字段 source_folder
    let folder_path = req.folder_path.as_deref()
        .or(req.source_folder.as_deref())
        .unwrap_or("");

    // 优先使用新字段 order，回退到旧字段 category_order
    let order = req.order.clone()
        .or_else(|| req.category_order.clone())
        .unwrap_or_default();

    if folder_path.is_empty() {
        return Err(actix_web::error::ErrorBadRequest("缺少 folder_path 参数"));
    }

    crate::config_api::storage::set_subfolder_order(folder_path, order)
        .map_err(|e| {
            actix_web::error::ErrorInternalServerError(format!("无法保存子文件夹排序: {}", e))
        })?;

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "status": "success"
    })))
}
