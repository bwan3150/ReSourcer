// 文件操作的工具函数
use std::path::{Path, PathBuf};

/// 获取唯一文件路径(处理重名情况)
pub fn get_unique_path(dir: &Path, filename: &str) -> PathBuf {
    let mut target_path = dir.join(filename);

    // 如果文件不存在,直接返回
    if !target_path.exists() {
        return target_path;
    }

    // 分离文件名和扩展名
    let path = Path::new(filename);
    let stem = path.file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or(filename);
    let extension = path.extension()
        .and_then(|e| e.to_str())
        .unwrap_or("");

    // 尝试添加数字后缀
    let mut counter = 1;
    loop {
        let new_filename = if extension.is_empty() {
            format!("{}_({})", stem, counter)
        } else {
            format!("{}_({}).{}", stem, counter, extension)
        };

        target_path = dir.join(&new_filename);

        if !target_path.exists() {
            return target_path;
        }

        counter += 1;

        // 防止无限循环
        if counter > 9999 {
            break;
        }
    }

    target_path
}
