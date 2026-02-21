// 标签模块 - 数据模型
use serde::{Deserialize, Serialize};

/// 标签
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Tag {
    pub id: i64,
    pub source_folder: String,
    pub name: String,
    pub color: String,
    pub created_at: String,
}

/// 创建标签请求
#[derive(Debug, Deserialize)]
pub struct CreateTagRequest {
    pub source_folder: String,
    pub name: String,
    pub color: Option<String>,
}

/// 更新标签请求
#[derive(Debug, Deserialize)]
pub struct UpdateTagRequest {
    pub name: Option<String>,
    pub color: Option<String>,
}

/// 设置文件标签请求
#[derive(Debug, Deserialize)]
pub struct FileTagRequest {
    pub file_uuid: String,
    pub tag_ids: Vec<i64>,
}

/// 文件标签响应
#[derive(Debug, Serialize)]
pub struct FileTagsResponse {
    pub file_uuid: String,
    pub tags: Vec<Tag>,
}

/// 批量获取文件标签请求
#[derive(Debug, Deserialize)]
pub struct FilesTagsRequest {
    pub file_uuids: Vec<String>,
}

/// 获取标签列表查询参数
#[derive(Debug, Deserialize)]
pub struct TagListQuery {
    pub source_folder: String,
}

/// 获取文件标签查询参数
#[derive(Debug, Deserialize)]
pub struct FileTagQuery {
    pub file_uuid: String,
}
