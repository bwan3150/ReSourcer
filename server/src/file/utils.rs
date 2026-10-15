// 文件操作的工具函数
use std::path::{Path, PathBuf};

/// 获取唯一文件路径（处理重名情况）
/// 若目标文件已存在，自动追加序号：IMG1234(1).PNG、IMG1234(2).PNG…
/// 使用指数搜索 + 二分搜索，O(log n) 次文件系统检查
pub fn get_unique_path(dir: &Path, filename: &str) -> PathBuf {
    let base_path = dir.join(filename);

    if !base_path.exists() {
        return base_path;
    }

    let path = Path::new(filename);
    let stem = path.file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or(filename);
    let ext = path.extension()
        .and_then(|e| e.to_str())
        .map(|e| format!(".{}", e))
        .unwrap_or_default();

    let candidate = |n: u32| -> PathBuf {
        dir.join(format!("{}({}){}", stem, n, ext))
    };

    // 指数搜索找上界
    let mut hi: u32 = 1;
    while candidate(hi).exists() {
        hi = hi.saturating_mul(2);
        if hi >= 1_000_000 { break; }
    }

    // 二分搜索找最小可用序号
    let mut lo: u32 = hi / 2 + 1;
    while lo < hi {
        let mid = lo + (hi - lo) / 2;
        if candidate(mid).exists() { lo = mid + 1; } else { hi = mid; }
    }

    candidate(lo)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn temp_dir(label: &str) -> PathBuf {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let dir = std::env::temp_dir().join(format!("resourcer-unique-{}-{}", label, nanos));
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn unique_path_returns_original_when_free() {
        let dir = temp_dir("free");
        let path = get_unique_path(&dir, "photo.jpg");
        assert_eq!(path, dir.join("photo.jpg"));
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn unique_path_appends_counter_on_collision() {
        let dir = temp_dir("collide");
        fs::write(dir.join("photo.jpg"), b"a").unwrap();
        let path = get_unique_path(&dir, "photo.jpg");
        assert_eq!(path, dir.join("photo(1).jpg"));
        fs::write(&path, b"b").unwrap();
        let path2 = get_unique_path(&dir, "photo.jpg");
        assert_eq!(path2, dir.join("photo(2).jpg"));
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn unique_path_handles_files_without_extension() {
        let dir = temp_dir("noext");
        fs::write(dir.join("README"), b"a").unwrap();
        let path = get_unique_path(&dir, "README");
        assert_eq!(path, dir.join("README(1)"));
        let _ = fs::remove_dir_all(&dir);
    }
}
