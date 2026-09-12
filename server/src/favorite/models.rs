// 收藏模块 - 数据模型
use serde::{Deserialize, Serialize};
use crate::indexer::models::IndexedFile;

/// 切换收藏请求
#[derive(Debug, Deserialize)]
pub struct ToggleRequest {
    pub uuid: String,
    pub level: String,
}

/// 切换收藏响应
#[derive(Debug, Serialize)]
pub struct ToggleResponse {
    pub uuid: String,
    pub level: String,
    pub favorited: bool,
}

/// 收藏列表查询参数
#[derive(Debug, Deserialize)]
pub struct FavoriteListQuery {
    pub level: Option<String>,
    pub offset: Option<i64>,
    pub limit: Option<i64>,
}

/// 收藏列表响应（分页）
#[derive(Debug, Serialize)]
pub struct FavoriteListResponse {
    pub files: Vec<IndexedFile>,
    pub total: i64,
    pub offset: i64,
    pub limit: i64,
    pub has_more: bool,
}

/// 批量查询收藏状态参数
#[derive(Debug, Deserialize)]
pub struct FavoriteStatusQuery {
    pub uuids: String, // 逗号分隔的 UUID 列表
}

/// 合法的收藏级别
pub fn is_valid_level(level: &str) -> bool {
    level == "favorite" || level == "featured"
}
