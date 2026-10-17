//! 实况照片（Live Photo）配对：同目录下同 stem 的静帧 + `.mov`。
//! 文件仍按路径识别；列表里把配对 MOV 藏起，并在静帧上挂 `live_video_*`。

use super::models::IndexedFile;

const STILL_EXTS: &[&str] = &["heic", "heif", "jpg", "jpeg"];
const LIVE_VIDEO_EXTS: &[&str] = &["mov"];

fn norm_ext(ext: &str) -> String {
    ext.trim_start_matches('.').to_lowercase()
}

fn file_stem(file_name: &str) -> String {
    std::path::Path::new(file_name)
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or(file_name)
        .to_lowercase()
}

fn is_still(file: &IndexedFile) -> bool {
    file.file_type == "image" && STILL_EXTS.contains(&norm_ext(&file.extension).as_str())
}

fn is_live_video(file: &IndexedFile) -> bool {
    file.file_type == "video" && LIVE_VIDEO_EXTS.contains(&norm_ext(&file.extension).as_str())
}

/// 是否为某张静帧的实况配对视频（应在相册网格中隐藏）
pub fn is_live_paired_video(file: &IndexedFile, folder_files: &[IndexedFile]) -> bool {
    if !is_live_video(file) {
        return false;
    }
    let stem = file_stem(&file.file_name);
    folder_files.iter().any(|still| {
        is_still(still) && file_stem(&still.file_name) == stem && still.uuid != file.uuid
    })
}

/// 为静帧填充 `live_video_uuid` / `live_video_path`；可选过滤掉配对 MOV。
pub fn enrich_and_filter_live_photos(
    files: Vec<IndexedFile>,
    folder_peers: &[IndexedFile],
    hide_paired_videos: bool,
) -> Vec<IndexedFile> {
    // 无外部 peers 时用自身副本做配对查找，避免边移出边借用
    let owned_peers: Option<Vec<IndexedFile>> = if folder_peers.is_empty() {
        Some(files.clone())
    } else {
        None
    };
    let peers: &[IndexedFile] = owned_peers.as_deref().unwrap_or(folder_peers);

    let mut out = Vec::with_capacity(files.len());
    for mut file in files {
        if hide_paired_videos && is_live_paired_video(&file, peers) {
            continue;
        }
        if is_still(&file) {
            let stem = file_stem(&file.file_name);
            if let Some(video) = peers.iter().find(|v| {
                is_live_video(v) && file_stem(&v.file_name) == stem && v.uuid != file.uuid
            }) {
                file.live_video_uuid = Some(video.uuid.clone());
                file.live_video_path = video.current_path.clone();
            }
        }
        out.push(file);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample(
        uuid: &str,
        name: &str,
        file_type: &str,
        extension: &str,
        path: &str,
    ) -> IndexedFile {
        IndexedFile {
            uuid: uuid.into(),
            fingerprint: String::new(),
            current_path: Some(path.into()),
            folder_path: "/src".into(),
            file_name: name.into(),
            file_type: file_type.into(),
            extension: extension.into(),
            file_size: 1,
            created_at: String::new(),
            modified_at: String::new(),
            indexed_at: String::new(),
            source_url: None,
            live_video_uuid: None,
            live_video_path: None,
        }
    }

    #[test]
    fn pairs_heic_with_same_stem_mov() {
        let heic = sample("a", "IMG_1.HEIC", "image", "heic", "/src/IMG_1.HEIC");
        let mov = sample("b", "IMG_1.MOV", "video", "mov", "/src/IMG_1.MOV");
        let other = sample("c", "clip.mp4", "video", "mp4", "/src/clip.mp4");
        let peers = vec![heic.clone(), mov.clone(), other.clone()];

        let enriched = enrich_and_filter_live_photos(peers.clone(), &peers, true);
        assert_eq!(enriched.len(), 2);
        assert!(enriched.iter().any(|f| f.uuid == "c"));
        let still = enriched.iter().find(|f| f.uuid == "a").unwrap();
        assert_eq!(still.live_video_uuid.as_deref(), Some("b"));
        assert_eq!(still.live_video_path.as_deref(), Some("/src/IMG_1.MOV"));
        assert!(!enriched.iter().any(|f| f.uuid == "b"));
    }

    #[test]
    fn plain_heic_unchanged() {
        let heic = sample("a", "solo.HEIC", "image", "heic", "/src/solo.HEIC");
        let peers = vec![heic.clone()];
        let enriched = enrich_and_filter_live_photos(peers.clone(), &peers, true);
        assert_eq!(enriched.len(), 1);
        assert!(enriched[0].live_video_uuid.is_none());
    }
}
