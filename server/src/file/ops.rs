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

    // 最佳努力：同步搬迁 `.thumb` 镜像（外部挪文件则靠 GC）
    crate::preview::persist::relocate_thumb_mirrors(file_path, &target_path);

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

    // 软删进回收站：相对路径变了，同步镜像；失败则留给扫描 GC
    crate::preview::persist::relocate_thumb_mirrors(file_path, &target_path);

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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::indexer::models::IndexedFile;
    use std::fs;
    use std::path::PathBuf;
    use std::sync::Mutex;
    use std::time::{SystemTime, UNIX_EPOCH};

    /// 全局锁：ops 测试依赖进程级 RESOURCER_DIR / DB，必须串行
    static TEST_LOCK: Mutex<()> = Mutex::new(());

    struct TestEnv {
        _guard: std::sync::MutexGuard<'static, ()>,
        data_dir: PathBuf,
        source: PathBuf,
        dest: PathBuf,
    }

    impl TestEnv {
        fn setup() -> Self {
            let guard = TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
            let nanos = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos();
            let root = std::env::temp_dir().join(format!("resourcer-ops-{}", nanos));
            let data_dir = root.join("data");
            let source = root.join("source");
            let dest = source.join("Album");
            fs::create_dir_all(&data_dir).unwrap();
            fs::create_dir_all(&dest).unwrap();
            std::env::set_var("RESOURCER_DIR", &data_dir);
            std::env::remove_var("RESOURCER_DATA_DIR");
            crate::database::init_db().expect("init_db");
            crate::config_api::storage::add_source_folder(source.to_str().unwrap())
                .expect("add_source");
            Self {
                _guard: guard,
                data_dir,
                source,
                dest,
            }
        }

        fn register_file(&self, name: &str, bytes: &[u8]) -> String {
            let path = self.source.join(name);
            fs::write(&path, bytes).unwrap();
            let uuid = uuid::Uuid::new_v4().to_string();
            let now = chrono::Utc::now().to_rfc3339();
            let file = IndexedFile {
                uuid: uuid.clone(),
                fingerprint: format!("fp-{}", name),
                current_path: Some(path.to_string_lossy().to_string()),
                folder_path: self.source.to_string_lossy().to_string(),
                file_name: name.to_string(),
                file_type: "image".to_string(),
                extension: "png".to_string(),
                file_size: bytes.len() as i64,
                created_at: now.clone(),
                modified_at: now.clone(),
                indexed_at: now,
                source_url: None,
            live_video_uuid: None,
            live_video_path: None,
            };
            crate::indexer::storage::upsert_file(&file).expect("upsert");
            uuid
        }
    }

    impl Drop for TestEnv {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(self.data_dir.parent().unwrap_or(&self.data_dir));
            std::env::remove_var("RESOURCER_DIR");
        }
    }

    #[test]
    fn move_one_relocates_file_and_updates_index() {
        let env = TestEnv::setup();
        let uuid = env.register_file("a.png", b"aaa");
        let new_path = move_one(&uuid, env.dest.to_str().unwrap(), None).unwrap();
        assert!(Path::new(&new_path).exists());
        assert!(!env.source.join("a.png").exists());
        let indexed = crate::indexer::storage::get_file_by_uuid(&uuid)
            .unwrap()
            .unwrap();
        assert_eq!(indexed.current_path.as_deref(), Some(new_path.as_str()));
        assert_eq!(
            indexed.folder_path,
            env.dest.to_string_lossy().to_string()
        );
    }

    #[test]
    fn delete_one_moves_to_recycle_bin() {
        let env = TestEnv::setup();
        let uuid = env.register_file("b.png", b"bbb");
        let new_path = delete_one(&uuid).unwrap();
        let recycle = env.source.join(RECYCLE_BIN_NAME);
        assert!(recycle.exists());
        assert!(Path::new(&new_path).exists());
        assert!(new_path.contains(RECYCLE_BIN_NAME));
        // 回收站内再次删除应失败
        let err = delete_one(&uuid).unwrap_err();
        assert!(matches!(err, FileOpError::BadRequest(_)));
    }

    #[test]
    fn move_one_unknown_uuid_is_not_found() {
        let _env = TestEnv::setup();
        let err = move_one("missing-uuid", "/tmp", None).unwrap_err();
        assert!(matches!(err, FileOpError::NotFound(_)));
    }
}
