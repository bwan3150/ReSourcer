//! 服务端缩略图磁盘持久化：源根下 `.thumb/` 路径镜像。
//!
//! 命名（已锁定）：
//! ```text
//! {source_root}/abc/123/test.mp4
//! → {source_root}/.thumb/abc/123/test.mp4.thumb          # size=300（默认）
//! → {source_root}/.thumb/abc/123/test.mp4.s640.thumb     # 其它尺寸
//! ```
//!
//! 文件格式：文本头 + 空行 + JPEG 正文。头内记录 `tv` / 源 mtime / 源 size / 请求 px，
//! 不一致则视为未命中并重建。无后台 batch backfill——仅首次请求时写入。

use std::fs::{self, File};
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use walkdir::WalkDir;

use super::models::THUMBNAIL_VERSION;

/// 默认缩略图边长（像素）；对应无 `.s{N}` 的 `.thumb` 文件名。
pub const DEFAULT_THUMB_SIZE: u32 = 300;

/// 源根下镜像目录名。
pub const THUMB_DIR_NAME: &str = ".thumb";

/// 缩略图文件后缀（不要用会进媒体索引的扩展名）。
pub const THUMB_FILE_SUFFIX: &str = ".thumb";

/// 磁盘容器格式魔数（与算法版本 `tv` 独立）。
const CONTAINER_MAGIC: &str = "RS-THUMB/1";

/// 扫描时应跳过的缩略图产物：目录名 `.thumb`，或文件名以 `.thumb` 结尾。
pub fn is_thumb_scan_skip(name: &str, is_dir: bool) -> bool {
    if is_dir {
        name == THUMB_DIR_NAME
    } else {
        name.ends_with(THUMB_FILE_SUFFIX)
    }
}

/// 路径是否落在 `.thumb` 镜像树内，或本身是 `*.thumb` 文件。
pub fn is_thumb_artifact_path(path: &Path) -> bool {
    if path
        .file_name()
        .and_then(|n| n.to_str())
        .map(|n| n.ends_with(THUMB_FILE_SUFFIX))
        .unwrap_or(false)
    {
        return true;
    }
    path.components().any(|c| {
        c.as_os_str()
            .to_str()
            .map(|s| s == THUMB_DIR_NAME)
            .unwrap_or(false)
    })
}

/// 给定源根与媒体路径，计算镜像缩略图路径。
/// 媒体文件可不存在（供 move/rename 后搬镜像用）。
///
/// - `size == DEFAULT_THUMB_SIZE` → `{rel}.thumb`
/// - 其它 → `{rel}.s{size}.thumb`
pub fn mirror_thumb_path(
    source_root: &Path,
    media_path: &Path,
    size: u32,
) -> Result<PathBuf, String> {
    let source_canon = source_root
        .canonicalize()
        .unwrap_or_else(|_| source_root.to_path_buf());

    // 优先 canonicalize（文件仍在时）；否则用绝对路径字符串前缀剥离，
    // 以便 rename 之后仍能算出旧/新镜像路径。
    let rel = if let Ok(media_canon) = media_path.canonicalize() {
        media_canon
            .strip_prefix(&source_canon)
            .map(|p| p.to_path_buf())
            .map_err(|_| format!("媒体不在源根下: {:?}", media_path))?
    } else {
        let media_abs = if media_path.is_absolute() {
            media_path.to_path_buf()
        } else {
            source_canon.join(media_path)
        };
        strip_prefix_lossy(&media_abs, &source_canon)
            .or_else(|| strip_prefix_lossy(&media_abs, source_root))
            .ok_or_else(|| format!("媒体不在源根下: {:?}", media_path))?
    };

    let file_name = rel
        .file_name()
        .ok_or_else(|| "无效的媒体文件名".to_string())?
        .to_string_lossy();

    let thumb_name = if size == DEFAULT_THUMB_SIZE {
        format!("{}{}", file_name, THUMB_FILE_SUFFIX)
    } else {
        format!("{}.s{}{}", file_name, size, THUMB_FILE_SUFFIX)
    };

    let mut out = source_canon.join(THUMB_DIR_NAME);
    if let Some(parent) = rel.parent() {
        if !parent.as_os_str().is_empty() {
            out = out.join(parent);
        }
    }
    out.push(thumb_name);
    Ok(out)
}

fn strip_prefix_lossy(path: &Path, prefix: &Path) -> Option<PathBuf> {
    let path_s = path.to_string_lossy();
    let prefix_s = prefix.to_string_lossy();
    let trimmed = if path_s == prefix_s {
        return Some(PathBuf::new());
    } else if let Some(rest) = path_s.strip_prefix(prefix_s.as_ref()) {
        rest.trim_start_matches(['/', '\\'])
    } else {
        return None;
    };
    if trimmed.is_empty() {
        Some(PathBuf::new())
    } else {
        Some(PathBuf::from(trimmed))
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SourceStamp {
    pub mtime_secs: i64,
    pub size: u64,
}

impl SourceStamp {
    pub fn from_path(path: &Path) -> Result<Self, String> {
        let meta = fs::metadata(path).map_err(|e| format!("读取源元数据失败: {}", e))?;
        let mtime_secs = meta
            .modified()
            .unwrap_or(SystemTime::UNIX_EPOCH)
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs() as i64;
        Ok(Self {
            mtime_secs,
            size: meta.len(),
        })
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ThumbHeader {
    pub tv: String,
    pub mtime_secs: i64,
    pub source_size: u64,
    pub px: u32,
}

impl ThumbHeader {
    pub fn matches(&self, stamp: &SourceStamp, size: u32) -> bool {
        self.tv == THUMBNAIL_VERSION
            && self.mtime_secs == stamp.mtime_secs
            && self.source_size == stamp.size
            && self.px == size
    }

    pub fn encode(&self) -> String {
        format!(
            "{}\ntv={}\nmtime={}\nsize={}\npx={}\n\n",
            CONTAINER_MAGIC, self.tv, self.mtime_secs, self.source_size, self.px
        )
    }

    pub fn parse(bytes: &[u8]) -> Option<(Self, usize)> {
        // 只解析文本头；正文是 JPEG（非 UTF-8），不能对整缓冲 from_utf8。
        let sep = b"\n\n";
        let split = bytes.windows(sep.len()).position(|w| w == sep)?;
        let header = std::str::from_utf8(&bytes[..split]).ok()?;
        let mut lines = header.lines();
        if lines.next()? != CONTAINER_MAGIC {
            return None;
        }
        let mut tv: Option<String> = None;
        let mut mtime_secs: Option<i64> = None;
        let mut source_size: Option<u64> = None;
        let mut px: Option<u32> = None;
        for line in lines {
            if let Some(rest) = line.strip_prefix("tv=") {
                tv = Some(rest.to_string());
            } else if let Some(rest) = line.strip_prefix("mtime=") {
                mtime_secs = rest.parse().ok();
            } else if let Some(rest) = line.strip_prefix("size=") {
                source_size = rest.parse().ok();
            } else if let Some(rest) = line.strip_prefix("px=") {
                px = rest.parse().ok();
            }
        }
        Some((
            Self {
                tv: tv?,
                mtime_secs: mtime_secs?,
                source_size: source_size?,
                px: px?,
            },
            split + sep.len(),
        ))
    }
}

/// 尝试从磁盘读取仍有效的 JPEG 正文；过期 / 版本不符 / 损坏 → None。
pub fn try_read_valid_thumb(
    thumb_path: &Path,
    stamp: &SourceStamp,
    size: u32,
) -> Option<Vec<u8>> {
    let mut file = File::open(thumb_path).ok()?;
    let mut buf = Vec::new();
    file.read_to_end(&mut buf).ok()?;
    let (header, offset) = ThumbHeader::parse(&buf)?;
    if !header.matches(stamp, size) {
        return None;
    }
    let jpeg = &buf[offset..];
    if jpeg.len() < 3 || jpeg[0] != 0xFF || jpeg[1] != 0xD8 {
        return None;
    }
    Some(jpeg.to_vec())
}

/// 原子写入：先写同目录临时文件再 rename。
pub fn atomic_write_thumb(
    thumb_path: &Path,
    stamp: &SourceStamp,
    size: u32,
    jpeg: &[u8],
) -> Result<(), String> {
    if let Some(parent) = thumb_path.parent() {
        fs::create_dir_all(parent).map_err(|e| format!("创建 .thumb 目录失败: {}", e))?;
    }
    let header = ThumbHeader {
        tv: THUMBNAIL_VERSION.to_string(),
        mtime_secs: stamp.mtime_secs,
        source_size: stamp.size,
        px: size,
    };
    let tmp_name = format!(
        ".{}.tmp-{}",
        thumb_path
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("thumb"),
        std::process::id()
    );
    let tmp_path = thumb_path
        .parent()
        .unwrap_or_else(|| Path::new("."))
        .join(tmp_name);

    {
        let mut f =
            File::create(&tmp_path).map_err(|e| format!("创建临时缩略图失败: {}", e))?;
        f.write_all(header.encode().as_bytes())
            .map_err(|e| format!("写入缩略图头失败: {}", e))?;
        f.write_all(jpeg)
            .map_err(|e| format!("写入缩略图正文失败: {}", e))?;
        f.sync_all().ok();
    }

    fs::rename(&tmp_path, thumb_path).map_err(|e| {
        let _ = fs::remove_file(&tmp_path);
        format!("原子替换缩略图失败: {}", e)
    })?;
    Ok(())
}

/// 解析媒体所属源根；未知源则不落盘。
pub fn resolve_source_root(media_path: &Path) -> Option<PathBuf> {
    let path_str = media_path.to_string_lossy();
    crate::indexer::storage::find_source_folder(&path_str).map(PathBuf::from)
}

/// 读取缓存；未命中返回 None（调用方生成后再 write）。
pub fn load_persisted_thumbnail(media_path: &Path, size: u32) -> Option<Vec<u8>> {
    let source_root = resolve_source_root(media_path)?;
    let thumb_path = mirror_thumb_path(&source_root, media_path, size).ok()?;
    let stamp = SourceStamp::from_path(media_path).ok()?;
    try_read_valid_thumb(&thumb_path, &stamp, size)
}

/// 生成成功后写入镜像路径（失败仅记日志，不影响响应）。
pub fn store_persisted_thumbnail(media_path: &Path, size: u32, jpeg: &[u8]) {
    let Some(source_root) = resolve_source_root(media_path) else {
        return;
    };
    let Ok(thumb_path) = mirror_thumb_path(&source_root, media_path, size) else {
        return;
    };
    let Ok(stamp) = SourceStamp::from_path(media_path) else {
        return;
    };
    if let Err(e) = atomic_write_thumb(&thumb_path, &stamp, size, jpeg) {
        eprintln!("[thumbnail] 持久化失败 ({:?}): {}", thumb_path, e);
    }
}

/// 将某媒体路径下已有的各尺寸 `.thumb` 镜像跟随 rename/move。
/// 最佳努力：失败不阻断文件操作。
pub fn relocate_thumb_mirrors(old_media: &Path, new_media: &Path) {
    let Some(source_root) = resolve_source_root(old_media)
        .or_else(|| resolve_source_root(new_media))
    else {
        return;
    };
    let Ok(old_default) = mirror_thumb_path(&source_root, old_media, DEFAULT_THUMB_SIZE) else {
        return;
    };
    let parent = match old_default.parent() {
        Some(p) => p.to_path_buf(),
        None => return,
    };
    let old_stem = match old_media.file_name().and_then(|n| n.to_str()) {
        Some(s) => s.to_string(),
        None => return,
    };

    let Ok(entries) = fs::read_dir(&parent) else {
        return;
    };
    for entry in entries.flatten() {
        let name = entry.file_name();
        let name = match name.to_str() {
            Some(n) => n,
            None => continue,
        };
        // 匹配 `stem.thumb` 或 `stem.sNNN.thumb`
        let size = if name == format!("{}{}", old_stem, THUMB_FILE_SUFFIX) {
            DEFAULT_THUMB_SIZE
        } else if let Some(rest) = name
            .strip_prefix(&format!("{}.s", old_stem))
            .and_then(|r| r.strip_suffix(THUMB_FILE_SUFFIX))
        {
            match rest.parse::<u32>() {
                Ok(n) => n,
                Err(_) => continue,
            }
        } else {
            continue;
        };
        let Ok(dest) = mirror_thumb_path(&source_root, new_media, size) else {
            continue;
        };
        if let Some(dest_parent) = dest.parent() {
            let _ = fs::create_dir_all(dest_parent);
        }
        let src = entry.path();
        if src == dest {
            continue;
        }
        if fs::rename(&src, &dest).is_err() {
            // 跨设备等：复制后删源
            if fs::copy(&src, &dest).is_ok() {
                let _ = fs::remove_file(&src);
            }
        }
    }
}

/// 遍历源根 `.thumb/`，删除对应源文件已不存在的孤儿缩略图。
/// 返回删除的文件数。不预生成；可挂在全量/lazy 扫描收尾。
pub fn gc_orphan_thumbs(source_root: &Path) -> u64 {
    let thumb_root = source_root.join(THUMB_DIR_NAME);
    if !thumb_root.is_dir() {
        return 0;
    }
    let source_canon = source_root
        .canonicalize()
        .unwrap_or_else(|_| source_root.to_path_buf());
    let mut deleted: u64 = 0;

    for entry in WalkDir::new(&thumb_root).into_iter().filter_map(|e| e.ok()) {
        let path = entry.path();
        if !path.is_file() {
            continue;
        }
        let name = match path.file_name().and_then(|n| n.to_str()) {
            Some(n) if n.ends_with(THUMB_FILE_SUFFIX) => n,
            _ => continue,
        };
        // 跳过写入中的临时文件
        if name.starts_with('.') || name.contains(".tmp-") {
            continue;
        }

        let Ok(rel_under_thumb) = path.strip_prefix(&thumb_root) else {
            continue;
        };
        let Some(media_rel) = thumb_name_to_media_rel(rel_under_thumb) else {
            continue;
        };
        let media_path = source_canon.join(&media_rel);
        if media_path.is_file() {
            continue;
        }
        if fs::remove_file(path).is_ok() {
            deleted += 1;
        }
    }

    // 清理空目录（自底向上）
    let mut dirs: Vec<PathBuf> = WalkDir::new(&thumb_root)
        .into_iter()
        .filter_map(|e| e.ok())
        .filter(|e| e.path().is_dir())
        .map(|e| e.path().to_path_buf())
        .collect();
    dirs.sort_by_key(|p| std::cmp::Reverse(p.components().count()));
    for dir in dirs {
        if dir == thumb_root {
            continue;
        }
        let _ = fs::remove_dir(&dir); // 非空则失败，忽略
    }

    deleted
}

/// `.thumb/abc/123/test.mp4.s640.thumb` → `abc/123/test.mp4`
fn thumb_name_to_media_rel(rel_under_thumb: &Path) -> Option<PathBuf> {
    let file_name = rel_under_thumb.file_name()?.to_str()?;
    let media_file = if let Some(stem) = file_name.strip_suffix(THUMB_FILE_SUFFIX) {
        // stem 可能是 `test.mp4` 或 `test.mp4.s640`
        if let Some((base, size_part)) = stem.rsplit_once(".s") {
            if size_part.chars().all(|c| c.is_ascii_digit()) && !size_part.is_empty() {
                base.to_string()
            } else {
                stem.to_string()
            }
        } else {
            stem.to_string()
        }
    } else {
        return None;
    };
    let mut out = PathBuf::new();
    if let Some(parent) = rel_under_thumb.parent() {
        out.push(parent);
    }
    out.push(media_file);
    Some(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;
    use std::time::{SystemTime, UNIX_EPOCH};

    static TEST_LOCK: Mutex<()> = Mutex::new(());

    fn unique_root(tag: &str) -> PathBuf {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        std::env::temp_dir().join(format!("resourcer-thumb-{}-{}", tag, nanos))
    }

    #[test]
    fn mirror_path_default_and_sized() {
        let root = unique_root("mirror");
        let media = root.join("abc/123/test.mp4");
        fs::create_dir_all(media.parent().unwrap()).unwrap();
        fs::write(&media, b"fake").unwrap();

        let def = mirror_thumb_path(&root, &media, 300).unwrap();
        assert_eq!(
            def,
            root.canonicalize()
                .unwrap()
                .join(".thumb/abc/123/test.mp4.thumb")
        );

        let s640 = mirror_thumb_path(&root, &media, 640).unwrap();
        assert_eq!(
            s640,
            root.canonicalize()
                .unwrap()
                .join(".thumb/abc/123/test.mp4.s640.thumb")
        );
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn header_roundtrip_and_mismatch() {
        let stamp = SourceStamp {
            mtime_secs: 1_700_000_000,
            size: 42,
        };
        let header = ThumbHeader {
            tv: THUMBNAIL_VERSION.to_string(),
            mtime_secs: stamp.mtime_secs,
            source_size: stamp.size,
            px: 300,
        };
        let mut bytes = header.encode().into_bytes();
        bytes.extend_from_slice(&[0xFF, 0xD8, 0xFF, 0xD9]); // minimal JPEG SOI..EOI-ish

        let (parsed, offset) = ThumbHeader::parse(&bytes).unwrap();
        assert!(parsed.matches(&stamp, 300));
        assert_eq!(&bytes[offset..], &[0xFF, 0xD8, 0xFF, 0xD9]);

        let stale = SourceStamp {
            mtime_secs: stamp.mtime_secs + 1,
            size: stamp.size,
        };
        assert!(!parsed.matches(&stale, 300));
    }

    #[test]
    fn atomic_write_and_read_valid() {
        let root = unique_root("rw");
        let media = root.join("photo.jpg");
        fs::create_dir_all(&root).unwrap();
        fs::write(&media, b"abcdef").unwrap();
        let stamp = SourceStamp::from_path(&media).unwrap();
        let thumb = mirror_thumb_path(&root, &media, 300).unwrap();
        let jpeg = vec![0xFF, 0xD8, 0xFF, 0xD9];
        atomic_write_thumb(&thumb, &stamp, 300, &jpeg).unwrap();
        let got = try_read_valid_thumb(&thumb, &stamp, 300).unwrap();
        assert_eq!(got, jpeg);

        // stale size → miss
        let stale = SourceStamp {
            mtime_secs: stamp.mtime_secs,
            size: stamp.size + 1,
        };
        assert!(try_read_valid_thumb(&thumb, &stale, 300).is_none());
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn gc_removes_orphans_keeps_live() {
        let _guard = TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let root = unique_root("gc");
        let live = root.join("keep.png");
        let gone_rel = Path::new("gone.png");
        fs::create_dir_all(&root).unwrap();
        fs::write(&live, b"live").unwrap();

        let stamp = SourceStamp::from_path(&live).unwrap();
        let live_thumb = mirror_thumb_path(&root, &live, 300).unwrap();
        atomic_write_thumb(&live_thumb, &stamp, 300, &[0xFF, 0xD8, 0xFF, 0xD9]).unwrap();

        let orphan = root.join(".thumb").join("gone.png.thumb");
        fs::create_dir_all(orphan.parent().unwrap()).unwrap();
        fs::write(&orphan, b"orphan").unwrap();
        assert!(orphan.exists());

        let n = gc_orphan_thumbs(&root);
        assert!(n >= 1);
        assert!(!orphan.exists());
        assert!(live_thumb.exists());
        let _ = gone_rel;
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn scan_skip_helpers() {
        assert!(is_thumb_scan_skip(".thumb", true));
        assert!(is_thumb_scan_skip("a.mp4.thumb", false));
        assert!(is_thumb_scan_skip("a.mp4.s640.thumb", false));
        assert!(!is_thumb_scan_skip("a.mp4", false));
        assert!(!is_thumb_scan_skip("photos", true));
    }

    #[test]
    fn thumb_name_to_media_rel_sized() {
        let rel = Path::new("abc/123/test.mp4.s640.thumb");
        assert_eq!(
            thumb_name_to_media_rel(rel).unwrap(),
            PathBuf::from("abc/123/test.mp4")
        );
        let rel2 = Path::new("test.mp4.thumb");
        assert_eq!(
            thumb_name_to_media_rel(rel2).unwrap(),
            PathBuf::from("test.mp4")
        );
    }
}
