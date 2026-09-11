use std::path::{Path, PathBuf};

/// 获取应用根目录（程序安装目录，可被重装/覆盖，不保证保留）
///
/// 解析逻辑（按优先级）：
/// 1. 环境变量 RESOURCER_DIR（开发时手动指定）
/// 2. 可执行文件同级有 config/ → 使用该目录（部署模式）
/// 3. 回退到当前工作目录
pub fn app_dir() -> PathBuf {
    // 环境变量优先（开发模式）
    if let Ok(dir) = std::env::var("RESOURCER_DIR") {
        return PathBuf::from(dir);
    }
    // 部署模式：exe 同级有 config/
    if let Ok(exe_path) = std::env::current_exe() {
        if let Some(exe_dir) = exe_path.parent() {
            if exe_dir.join("config").exists() {
                return exe_dir.to_path_buf();
            }
        }
    }
    // 回退到当前工作目录
    std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."))
}

/// 获取数据目录（sqlite/、config/、backups/ 等必须跨重装保留的数据存放于此）
///
/// 与 app_dir() 分离：app_dir() 是程序安装目录，NAS 系统更新时可能被整体清空重装；
/// data_dir() 必须指向一个独立、持久化的位置。
///
/// 解析逻辑（按优先级）：
/// 1. 环境变量 RESOURCER_DATA_DIR（NAS 部署时指定持久化卷，如群晖 /volume1/...）
/// 2. 回退到 app_dir()（向后兼容：不设置该变量时行为与改动前完全一致）
pub fn data_dir() -> PathBuf {
    if let Ok(dir) = std::env::var("RESOURCER_DATA_DIR") {
        return PathBuf::from(dir);
    }
    app_dir()
}

/// 一次性迁移：早期版本把 sqlite/ 和 config/ 直接放在 app_dir() 下。
/// 首次配置了 RESOURCER_DATA_DIR 后，如果新数据目录下还没有数据库、而旧位置有，
/// 就把 sqlite/ 和 config/ 整体搬过去，绝不在旧数据存在时悄悄新建空库。
pub fn migrate_legacy_data_if_needed() {
    let data = data_dir();
    let app = app_dir();
    if data == app {
        return; // 未设置 RESOURCER_DATA_DIR，沿用原有行为
    }

    let old_db = app.join("sqlite").join("data.db");
    let new_db = data.join("sqlite").join("data.db");
    if new_db.exists() || !old_db.exists() {
        return; // 目标已有数据，或旧位置本就没有数据，无需迁移
    }

    eprintln!(
        "[migrate] 发现旧数据目录 {} 下有数据，而持久化目录 {} 下为空，开始迁移",
        app.display(),
        data.display()
    );
    for name in ["sqlite", "config"] {
        let src = app.join(name);
        let dst = data.join(name);
        if !src.exists() || dst.exists() {
            continue;
        }
        match move_dir(&src, &dst) {
            Ok(()) => eprintln!("[migrate] 已迁移 {} -> {}", src.display(), dst.display()),
            Err(e) => eprintln!("[migrate] 迁移 {} 失败: {}", src.display(), e),
        }
    }
}

/// 整体搬一个目录：优先用 rename（同文件系统下是原子操作），
/// 跨文件系统时 rename 会失败，退化为递归复制 + 删除源目录
fn move_dir(src: &Path, dst: &Path) -> std::io::Result<()> {
    if let Some(parent) = dst.parent() {
        std::fs::create_dir_all(parent)?;
    }
    if std::fs::rename(src, dst).is_ok() {
        return Ok(());
    }
    copy_dir_recursive(src, dst)?;
    std::fs::remove_dir_all(src)
}

fn copy_dir_recursive(src: &Path, dst: &Path) -> std::io::Result<()> {
    std::fs::create_dir_all(dst)?;
    for entry in std::fs::read_dir(src)? {
        let entry = entry?;
        let file_type = entry.file_type()?;
        let dst_path = dst.join(entry.file_name());
        if file_type.is_dir() {
            copy_dir_recursive(&entry.path(), &dst_path)?;
        } else {
            std::fs::copy(entry.path(), &dst_path)?;
        }
    }
    Ok(())
}

/// 从 config 目录读取文件内容
pub fn read_config_file(filename: &str) -> Option<Vec<u8>> {
    let path = data_dir().join("config").join(filename);
    std::fs::read(&path).ok()
}
