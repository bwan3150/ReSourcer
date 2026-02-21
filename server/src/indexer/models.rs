// 索引模块数据结构
use serde::{Deserialize, Serialize};

/// 索引文件记录
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IndexedFile {
    pub uuid: String,
    pub fingerprint: String,
    pub current_path: Option<String>,
    pub folder_path: String,
    pub file_name: String,
    pub file_type: String,
    pub extension: String,
    pub file_size: i64,
    pub created_at: String,
    pub modified_at: String,
    pub indexed_at: String,
}

/// 索引文件夹记录
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IndexedFolder {
    pub path: String,
    pub parent_path: Option<String>,
    pub source_folder: String,
    pub name: String,
    pub depth: i32,
    pub file_count: i64,
    pub indexed_at: String,
}

/// 扫描请求
#[derive(Debug, Deserialize)]
pub struct ScanRequest {
    pub source_folder: String,
}

/// 分页查询文件
#[derive(Debug, Deserialize)]
pub struct FilesQuery {
    pub folder_path: String,
    pub offset: Option<i64>,
    pub limit: Option<i64>,
    pub file_type: Option<String>,
    pub sort: Option<String>,
}

/// UUID 查询文件
#[derive(Debug, Deserialize)]
pub struct FileByUuidQuery {
    pub uuid: String,
}

/// 子文件夹查询
#[derive(Debug, Deserialize)]
pub struct FoldersQuery {
    pub parent_path: Option<String>,
    pub source_folder: Option<String>,
}

/// 面包屑查询
#[derive(Debug, Deserialize)]
pub struct BreadcrumbQuery {
    pub folder_path: String,
}

/// 分页文件响应
#[derive(Debug, Serialize)]
pub struct PaginatedFilesResponse {
    pub files: Vec<IndexedFile>,
    pub total: i64,
    pub offset: i64,
    pub limit: i64,
    pub has_more: bool,
}

/// 扫描状态
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScanStatus {
    pub is_scanning: bool,
    pub scanned_files: u64,
    pub scanned_folders: u64,
}

impl Default for ScanStatus {
    fn default() -> Self {
        Self {
            is_scanning: false,
            scanned_files: 0,
            scanned_folders: 0,
        }
    }
}

/// 面包屑条目
#[derive(Debug, Serialize)]
pub struct BreadcrumbItem {
    pub name: String,
    pub path: String,
}
