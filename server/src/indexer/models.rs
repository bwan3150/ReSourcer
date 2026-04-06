// 索引模块数据结构
use serde::{Deserialize, Serialize};

/// 索引文件记录
/// file_path 使用相对路径：@/subfolder/file.mp4（@ = 源文件夹根目录）
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IndexedFile {
    pub uuid: String,
    pub fingerprint: String,
    pub file_path: Option<String>,      // 相对路径 @/folder/file.mp4, None=pending/deleted
    pub source_folder: String,           // 对应的源文件夹绝对路径
    pub file_type: String,
    pub extension: String,
    pub file_size: i64,
    pub created_at: String,
    pub modified_at: String,
    pub indexed_at: String,
    pub source_url: Option<String>,
}

impl IndexedFile {
    /// 从相对路径提取文件名
    pub fn file_name(&self) -> String {
        self.file_path.as_deref().unwrap_or("")
            .rsplit('/').next().unwrap_or("").to_string()
    }

    /// 从相对路径提取文件夹部分（不含文件名）
    pub fn folder_path(&self) -> String {
        let path = self.file_path.as_deref().unwrap_or("@");
        match path.rfind('/') {
            Some(pos) => path[..pos].to_string(),
            None => "@".to_string(),
        }
    }

    /// 解析为磁盘绝对路径
    pub fn absolute_path(&self) -> Option<String> {
        let rel = self.file_path.as_deref()?;
        let without_at = rel.strip_prefix("@/").unwrap_or(rel.strip_prefix("@").unwrap_or(rel));
        if without_at.is_empty() {
            Some(self.source_folder.clone())
        } else {
            Some(format!("{}/{}", self.source_folder, without_at))
        }
    }

    /// 从绝对路径 + 源文件夹生成相对路径
    pub fn to_relative(abs_path: &str, source_folder: &str) -> String {
        if let Some(rel) = abs_path.strip_prefix(source_folder) {
            let rel = rel.trim_start_matches('/');
            if rel.is_empty() {
                "@".to_string()
            } else {
                format!("@/{}", rel)
            }
        } else {
            // fallback: 用完整路径
            abs_path.to_string()
        }
    }

    /// 从相对路径提取文件夹的相对路径（用于查询）
    pub fn relative_folder(abs_folder: &str, source_folder: &str) -> String {
        if let Some(rel) = abs_folder.strip_prefix(source_folder) {
            let rel = rel.trim_start_matches('/');
            if rel.is_empty() {
                "@".to_string()
            } else {
                format!("@/{}", rel)
            }
        } else {
            abs_folder.to_string()
        }
    }
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
    #[serde(default)]
    pub subfolder_count: i64,
    pub indexed_at: String,
}

/// 扫描请求
#[derive(Debug, Deserialize)]
pub struct ScanRequest {
    pub source_folder: String,
    /// 强制重建索引（清除旧的 file_index 后全量重新扫描）
    #[serde(default)]
    pub force: bool,
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
