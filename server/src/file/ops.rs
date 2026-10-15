// 文件移动 / 软删除的核心逻辑（单文件与批量共用）
use std::fs;
use std::path::Path;

use super::models::RECYCLE_BIN_NAME;
use super::utils::get_unique_path;

/// 文件操作失败原因（批量接口按项返回；单文件接口映射为 HTTP 错误）
#[derive(Debug)]
pub enum FileOpError {
    NotFound(String),
    BadRequest(String),
    Internal(String),
}

impl FileOpError {
    pub fn message(&self) -> &str {
        match self {
            FileOpError::NotFound(m) | FileOpError::BadRequest(m) | FileOpError::Internal(m) => m,
        }
    }

    pub fn into_actix(self) -> actix_web::Error {
        match self {
            FileOpError::NotFound(m) => actix_web::error::ErrorNotFound(m),
            FileOpError::BadRequest(m) => actix_web::error::ErrorBadRequest(m),
            FileOpError::Internal(m) => actix_web::error::ErrorInternalServerError(m),
        }
    }
}

/// 移动单个文件到目标文件夹，返回新路径
pub fn move_one(
    uuid: &str,
    target_folder: &str,
    new_name: Option<&str>,
) -> Result<String, FileOpError> {
    let indexed = crate::indexer::storage::get_file_by_uuid(uuid)
        .map_err(|e| FileOpError::Internal(format!("查询索引失败: {}", e)))?
        .ok_or_else(|| FileOpError::NotFound("UUID 对应的文件不存在".into()))?;

    let current_path = indexed
        .current_path
        .ok_or_else(|| FileOpError::NotFound("文件路径为空".into()))?;
    let file_path = Path::new(&current_path);
    let target_folder_path = Path::new(target_folder);

    if !file_path.exists() || !file_path.is_file() {
        return Err(FileOpError::NotFound("文件不存在".into()));
    }
    if !target_folder_path.exists() || !target_folder_path.is_dir() {
        return Err(FileOpError::NotFound("目标文件夹不存在".into()));
    }

    let file_name = if let Some(name) = new_name {
        name.to_string()
    } else {
        file_path
            .file_name()
            .ok_or_else(|| FileOpError::BadRequest("无法获取文件名".into()))?
            .to_string_lossy()
            .to_string()
    };

    let target_path = get_unique_path(target_folder_path, &file_name);

    fs::rename(file_path, &target_path)
        .map_err(|e| FileOpError::Internal(format!("移动失败: {}", e)))?;

    let new_path_str = target_path.to_string_lossy().to_string();
    let new_folder_str = target_folder_path.to_string_lossy().to_string();
    let new_file_name = target_path
        .file_name()
        .unwrap_or_default()
        .to_string_lossy()
        .to_string();
    let _ = crate::indexer::storage::update_file_path(
        uuid,
        &new_path_str,
        &new_folder_str,
        &new_file_name,
    );

    Ok(new_path_str)
}

/// 软删除单个文件到源文件夹回收站，返回回收站中的新路径
pub fn delete_one(uuid: &str) -> Result<String, FileOpError> {
    let indexed = crate::indexer::storage::get_file_by_uuid(uuid)
        .map_err(|e| FileOpError::Internal(format!("查询索引失败: {}", e)))?
        .ok_or_else(|| FileOpError::NotFound("UUID 对应的文件不存在".into()))?;

    let current_path = indexed
        .current_path
        .ok_or_else(|| FileOpError::NotFound("文件路径为空".into()))?;
    let file_path = Path::new(&current_path);

    if !file_path.exists() || !file_path.is_file() {
        return Err(FileOpError::NotFound("文件不存在".into()));
    }

    let config = crate::config_api::storage::load_config()
        .map_err(|e| FileOpError::Internal(format!("无法加载配置: {}", e)))?;

    let recycle_dir = Path::new(&config.source_folder).join(RECYCLE_BIN_NAME);
    if !recycle_dir.exists() {
        fs::create_dir_all(&recycle_dir)
            .map_err(|e| FileOpError::Internal(format!("无法创建回收站: {}", e)))?;
    }

    if let Ok(canon_recycle) = fs::canonicalize(&recycle_dir) {
        if let Some(parent) = file_path.parent() {
            if let Ok(canon_parent) = fs::canonicalize(parent) {
                if canon_parent == canon_recycle {
                    return Err(FileOpError::BadRequest("文件已在回收站中".into()));
                }
            }
        }
    }

    let file_name = file_path
        .file_name()
        .ok_or_else(|| FileOpError::BadRequest("无法获取文件名".into()))?
        .to_string_lossy()
        .to_string();
    let target_path = get_unique_path(&recycle_dir, &file_name);

    fs::rename(file_path, &target_path)
        .map_err(|e| FileOpError::Internal(format!("删除失败: {}", e)))?;

    let new_path_str = target_path.to_string_lossy().to_string();
    let new_folder_str = recycle_dir.to_string_lossy().to_string();
    let new_file_name = target_path
        .file_name()
        .unwrap_or_default()
        .to_string_lossy()
        .to_string();
    let _ = crate::indexer::storage::update_file_path(
        uuid,
        &new_path_str,
        &new_folder_str,
        &new_file_name,
    );

    Ok(new_path_str)
}
